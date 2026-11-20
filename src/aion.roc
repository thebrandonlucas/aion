app [main!] {
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
}

import pf.Cmd
import pf.Duration
import pf.Env
import pf.OsStr
import pf.Path
import pf.Random
import pf.Stdout

import Ansi
import Customer
import Launch
import SshKey
import Vultr
import VultrApi

usage = Str.join_with(
	[
		"Aion - a customer's Kai box on Vultr, installed by kai",
		"",
		"Usage:",
		"  aion customer new <slug> [--tailnet <magicdns-suffix>]",
		"  aion customer list",
		"  aion customer machine new <slug> <machine> [--dry-run]",
		"  aion customer machine install <slug> <machine> [--to <host[:port]>]",
		"  aion customer machine destroy <slug> <machine>",
		"  aion resources          aion-tagged Vultr instances (read-only)",
		"",
		"`machine new` creates a stock Ubuntu instance at once, bills from then on,",
		"and has kai erase it to install the machine. `install --to` installs on a",
		"server aion did not create, such as one in the customer's own account.",
		"Change an installed box with `kai machine switch <machine>` in its repository.",
		"",
		"Environment:",
		"  VULTR_API_KEY            API key, for machine new and destroy (or in .env)",
		"  AION_REGION              Vultr region (default: ${Vultr.default_region})",
		"  AION_PLAN                Vultr plan (default: ${Vultr.default_plan})",
		"  AION_KAI                 kai to run (default: the 0.0.13 release, through nix run)",
		"  AION_CLIENTS             where customer repositories live (default: ~/clients)",
		"  AION_TEMPLATE            the kai-box client skeleton (default: ../kai-box-template/client)",
		"  AION_OPERATOR_KEY        the operator's public key (default: ~/.ssh/id_ed25519.pub)",
		"  AION_RECOVERY_RECIPIENT  the offline recovery key's age recipient, a second Operator (or in .env)",
		"  AION_VULTR_URL           API base URL, for a mock (default: ${VultrApi.default_url})",
	],
	"\n",
)

is_name_byte : U8 -> Bool
is_name_byte = |byte| (byte >= 'a' and byte <= 'z') or (byte >= '0' and byte <= '9')

# A lowercase DNS label, which is also a valid kai machine and host name.
valid_name : Str -> Bool
valid_name = |name| {
	bytes = name.to_utf8()
	length = bytes.len()
	length > 0
		and length <= 63
		and is_name_byte(bytes.get(0) ?? 0)
		and is_name_byte(bytes.get(length - 1) ?? 0)
		and bytes.all(|byte| is_name_byte(byte) or byte == '-')
}

env_or! = |name, fallback| Env.var_str!(OsStr.from_str(name)) ?? fallback

read_key! = |path| SshKey.canonical(Path.read_utf8!(path)?)

# kai 0.0.13, the release whose platform and machine plugin the skeleton
# names, run from its flake at the release commit.
release_kai = ["run", "github:thebrandonlucas/kai/9b0174df172041f00acb5d5387c65af96cd9950a", "--"]

# Runs kai in a customer's repository, showing its output: AION_KAI if set,
# or else the release through nix.
kai! = |directory, argv| {
	kai = env_or!("AION_KAI", "")
	command = if (kai.is_empty()) Cmd.new(OsStr.from_str("nix")).args(strs(release_kai.concat(argv))) else Cmd.new(Path.to_os_str(Path.absolute!(Path.utf8(kai))?)).args(strs(argv))
	ran = command
		.cwd(directory)
		.inherit_stdio()
		.call!()
	match ran {
		Ok(_) => Ok({})
		Err(_) => Err(KaiFailed(Str.join_with(argv, " ")))
	}
}

show_argv = |argv| Str.join_with(["kai"].concat(argv), " ")

strs = |values| values.map(OsStr.from_str)

# A KEY=value line of the ignored .env, without quotes.
dotenv_value! = |name| {
	lines = (Path.read_utf8!(Path.utf8(".env")) ?? "").split_on("\n")
	match lines.keep_if(|line| line.starts_with("${name}=")) {
		[line] => Ok(line.drop_prefix("${name}=").trim().drop_prefix("\"").drop_suffix("\""))
		_ => Err(MissingSetting("set ${name}, in the environment or .env"))
	}
}

# The API key from the environment, or else from .env. It is only ever sent
# in the Authorization header.
auth! = || {
	token = Env.var_str!(OsStr.from_str("VULTR_API_KEY")) ?? dotenv_value!("VULTR_API_KEY")?
	Ok({ url: env_or!("AION_VULTR_URL", VultrApi.default_url), token })
}

# The operator's public key: the one the instance is created with for
# nixos-anywhere, root's on the box, and its first Operator.
operator_key! = || {
	home = Env.var_str!(OsStr.from_str("HOME"))?
	read_key!(Path.utf8(env_or!("AION_OPERATOR_KEY", "${home}/.ssh/id_ed25519.pub")))
}

# The offline recovery key's age recipient, every box's second Operator, so
# its host key and secrets outlive the loss of the operator's own key.
recovery_recipient! = || {
	recipient = Env.var_str!(OsStr.from_str("AION_RECOVERY_RECIPIENT")) ?? dotenv_value!("AION_RECOVERY_RECIPIENT")?
	if recipient.starts_with("age1") and !recipient.contains(" ") {
		Ok(recipient)
	} else {
		Err(InvalidRecoveryRecipient("AION_RECOVERY_RECIPIENT must be one age1... recipient, from age-keygen run offline"))
	}
}

clients_root! = || {
	home = Env.var_str!(OsStr.from_str("HOME"))?
	Ok(Path.utf8(env_or!("AION_CLIENTS", "${home}/clients")))
}

customer_new! = |slug, tailnet| {
	# The box's host name is <slug>-box, which must stay a DNS label.
	if !valid_name(slug) or slug.to_utf8().len() > 59 {
		return Err(InvalidName("use 1-59 lowercase ASCII letters, digits, or internal '-' characters"))
	}
	operator = operator_key!()?
	recovery = recovery_recipient!()?
	directory = Path.join(clients_root!()?, slug)
	if Path.exists!(directory)? {
		return Err(CustomerExists(Path.display(directory)))
	}
	skeleton = Path.utf8(env_or!("AION_TEMPLATE", "../kai-box-template/client"))
	Customer.create!(skeleton, directory, { name: slug, root_keys: [operator], operators: [operator, recovery], tailnet })?
	initialized = Cmd.new(OsStr.from_str("git")).args(strs(["init", "--quiet"])).cwd(directory).inherit_stdio().call!()
	if initialized.is_err() {
		return Err(GitInitFailed(Path.display(directory)))
	}
	tailnet_step = if (tailnet.is_empty()) ["  0. write the customer's tailnet, its MagicDNS suffix such as tail1234.ts.net, to aion/tailnet"] else []
	Stdout.line!(
		Str.join_with(
			[Ansi.green("Created customer ${slug} in ${Path.display(directory)}"), "Next, there:"]
				.concat(tailnet_step)
				.concat([
					"  1. work through ONBOARDING.md: the tailnet, then each secret with `kai secret set box ...`",
					"  2. kai update",
					"  3. aion customer machine new ${slug} box",
				]),
			"\n",
		),
	)
}

customer_list! = || {
	root = clients_root!()?
	customers = Customer.names!(root)?
	if customers.is_empty() {
		return Stdout.line!("no customers in ${Path.display(root)}")
	}
	for slug in customers {
		directory = Path.join(root, slug)
		machines = Customer.machine_names!(directory)?
		if machines.is_empty() {
			Stdout.line!("${slug}  (no machines)")?
		}
		for machine in machines {
			line = match Customer.read_machine!(directory, machine) {
				Ok(s) => "${slug}  ${machine}  ${s.status}  ${s.address}  vultr ${s.id}  ${s.region} ${s.plan}"
				Err(_) => "${slug}  ${machine}  (no readable aion/machines/${machine}.json)"
			}
			Stdout.line!(line)?
		}
	}
	Ok({})
}

customer_directory! = |slug| {
	directory = Path.join(clients_root!()?, slug)
	if !Path.exists!(directory)? {
		return Err(UnknownCustomer("no customer ${slug} in ${Path.display(clients_root!()?)}"))
	}
	Ok(directory)
}

# A customer's machine is <slug>-<machine>: its Vultr label and its host
# name, which kai's Host reaches by MagicDNS on the customer's tailnet.
host_name = |slug, machine| "${slug}-${machine}"

check_machine_name = |slug, machine|
	if valid_name(machine) and valid_name(host_name(slug, machine)) {
		Ok({})
	} else {
		Err(InvalidName("${host_name(slug, machine)} must be a DNS label of at most 63 lowercase letters, digits and '-'"))
	}

# Refuses unless this laptop is on the customer's tailnet, whose MagicDNS
# suffix `tailscale status --json` names when it is the current one.
check_tailnet! = |directory| {
	tailnet = Customer.tailnet!(directory)?
	if tailnet.is_empty() {
		return Err(NoTailnet("write the customer's MagicDNS suffix, such as tail1234.ts.net, to aion/tailnet"))
	}
	status = Cmd.new(OsStr.from_str("tailscale")).args(strs(["status", "--json"])).capture!() ?? ""
	if status.contains("\"MagicDNSSuffix\": \"${tailnet}\"") {
		Ok(tailnet)
	} else {
		Err(WrongTailnet("this laptop is not on ${tailnet}; find its account with `tailscale switch --list` and run `tailscale switch <account>`"))
	}
}

# `host[:port]` as ssh's host and port options, so a local VM behind a
# forwarded port can stand in for a server.
ssh_target = |target|
	match target.split_on(":") {
		[host, port] => { host, port_options: ["-p", port] }
		_ => { host: target, port_options: [] }
	}

# A fresh server's host key is unknown, and the install replaces it, so this
# probe trusts whatever answers and records nothing.
wait_for_ssh! = |target, attempt| {
	t = ssh_target(target)
	probe = Cmd.new(OsStr.from_str("ssh"))
		.args(strs(t.port_options.concat(["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", "-o", "LogLevel=ERROR", "root@${t.host}", "true"])))
		.run!()
	ready = match probe {
		Ok(ran) => ran.status == Exited(0)
		Err(_) => Bool.False
	}
	if ready {
		Ok({})
	} else if attempt >= 30 {
		Err(SshNotReady(target))
	} else {
		Duration.sleep!(Duration.seconds(10))?
		wait_for_ssh!(target, attempt + 1)
	}
}

# Waits, up to 5 minutes, for the installed box on the tailnet, trusting
# only the host key kai placed, as kai's own commands do.
wait_for_tailnet! = |directory, machine, host, attempt| {
	public = Path.read_utf8!(Path.join(directory, "secrets/hosts/${machine}.pub"))?
	known_hosts = Path.join(directory, ".kai/aion-known-hosts")
	Path.write_utf8!(known_hosts, "${machine} ${Str.join_with(public.trim().split_on(" ").take_first(2), " ")}\n")?
	probe = Cmd.new(OsStr.from_str("ssh"))
		.args(strs(["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-o", "UserKnownHostsFile=${Path.display(known_hosts)}", "-o", "GlobalKnownHostsFile=/dev/null", "-o", "StrictHostKeyChecking=yes", "-o", "HostKeyAlias=${machine}", "-o", "LogLevel=ERROR", "root@${host}", "true"]))
		.run!()
	ready = match probe {
		Ok(ran) => ran.status == Exited(0)
		Err(_) => Bool.False
	}
	if ready {
		Ok({})
	} else if attempt >= 30 {
		Err(NotOnTailnet("${host} did not join; log in on Vultr's web console as root (the root-password-hash secret) and read `journalctl -u tailscaled-autoconnect`"))
	} else {
		Duration.sleep!(Duration.seconds(10))?
		wait_for_tailnet!(directory, machine, host, attempt + 1)
	}
}

# The instance's public IPv4 once Vultr has installed and booted it,
# polling every 5 seconds for up to 10 minutes.
wait_ready! = |id, auth, attempt| {
	instance = VultrApi.get_instance!(id, auth)?
	match Vultr.ready_address(instance) {
		Ok(address) => Ok(address)
		Err(NotReady) if attempt >= 120 => Err(InstanceNotReady(id))
		Err(NotReady) => {
			Duration.sleep!(Duration.seconds(5))?
			wait_ready!(id, auth, attempt + 1)
		}
	}
}

# After an uncertain POST, the instance the operation tag names, if any.
reconcile! = |operation_tag, auth|
	match VultrApi.list_instances_by_tag!(operation_tag, auth)? {
		[instance] => Ok(instance.id)
		[] => Err(CreateUncertain("no instance is tagged ${operation_tag}; check `aion resources` and Vultr before retrying"))
		_ => Err(CreateUncertain("several instances are tagged ${operation_tag}; delete the extras in Vultr"))
	}

machine_new! = |slug, machine, dry_run| {
	check_machine_name(slug, machine)?
	directory = customer_directory!(slug)?
	if Path.exists!(Customer.machine_path(directory, machine))? {
		return Err(MachineExists("aion/machines/${machine}.json exists; `aion customer machine destroy ${slug} ${machine}` first"))
	}
	label = host_name(slug, machine)
	region = env_or!("AION_REGION", Vultr.default_region)
	plan = env_or!("AION_PLAN", Vultr.default_plan)
	operator = operator_key!()?
	Stdout.line!(Ansi.heading("Building ${machine} for ${slug} before creating anything"))?
	kai!(directory, ["machine", "build", machine])?
	if dry_run {
		Stdout.line!(Ansi.heading("kai's install plan for root@${Launch.example_address}"))?
		kai!(directory, Launch.dry_install_argv(machine, Launch.example_address))?
		body = Vultr.instance_body(label, region, plan, ["<operator key id>"], ["aion", "aion-${slug}", "aion-op-DRY-RUN"])
		return Stdout.line!(
			Str.join_with(
				[
					Ansi.heading("A real run would then"),
					"1. register the operator key if Vultr lacks it, and POST ${VultrApi.default_url}/v2/instances once:",
					"   ${Str.inspect(body)}",
					"2. poll the instance until it is active, then wait for SSH on its IPv4",
					"3. run, in ${Path.display(directory)}: ${show_argv(Launch.install_argv(machine, "<ipv4>"))}",
					"4. wait for root@${label} on the customer's tailnet",
					"",
					Ansi.dim("Dry run: nothing was sent to Vultr."),
				],
				"\n",
			),
		)
	}
	_ = check_tailnet!(directory)?
	auth = auth!()?
	if VultrApi.list_instances_by_tag!("aion-${slug}", auth)?.any(|instance| instance.label == label) {
		return Err(InstanceExists("an aion instance labelled ${label} exists; see `aion resources`"))
	}
	key = VultrApi.ensure_ssh_key!("aion-operator", operator, auth)?
	operation_tag = "aion-op-${U64.to_str(Random.seed_u64!()?)}"
	pending = { address: "", id: "", machine, operation_tag, plan, region, status: "creating" }
	Customer.save_machine!(directory, pending)?
	Stdout.line!(Ansi.heading("Creating instance ${label} (${plan}, ${region}), tagged ${operation_tag}"))?
	body = Vultr.instance_body(label, region, plan, [key.id], ["aion", "aion-${slug}", operation_tag])
	id = match VultrApi.create_instance_once!(body, auth) {
		PostAccepted(instance) => instance.id
		PostRejected(error) => {
			Customer.forget_machine!(directory, machine) ?? {}
			return Err(error)
		}
		PostUncertain(_) => reconcile!(operation_tag, auth)?
	}
	Customer.save_machine!(directory, { ..pending, id })?
	address = wait_ready!(id, auth, 1)?
	Customer.save_machine!(directory, { ..pending, id, address, status: "created" })?
	Stdout.line!(Ansi.heading("Instance ${id} is active at ${address}; waiting for SSH"))?
	install!(slug, machine, address)
}

# Installs the machine with kai over whatever runs at `target`, erasing it:
# the instance `machine new` created, or with --to another server, such as
# one in the customer's own account. Run again after a failed install.
install! = |slug, machine, target| {
	check_machine_name(slug, machine)?
	directory = customer_directory!(slug)?
	saved = Customer.read_machine!(directory, machine)
	address = if (target.is_empty()) (saved?).address else target
	_ = check_tailnet!(directory)?
	installed = match wait_for_ssh!(address, 1) {
		Ok({}) => kai!(directory, Launch.install_argv(machine, address))
		Err(error) => Err(error)
	}
	match installed {
		Ok({}) => {}
		Err(error) => {
			_ = Stdout.line!(Ansi.red("Install failed; the server is still running. Retry with `aion customer machine install ${slug} ${machine}`.")) ?? {}
			return Err(error)
		}
	}
	match saved {
		Ok(state) => Customer.save_machine!(directory, { ..state, status: "installed" })?
		Err(_) => {}
	}
	host = "${host_name(slug, machine)}.${Customer.tailnet!(directory)?}"
	Stdout.line!(Ansi.heading("Installed; waiting for ${host} on the tailnet"))?
	wait_for_tailnet!(directory, machine, host, 1)?
	Stdout.line!(
		Str.join_with(
			[
				Ansi.green("${slug}'s ${machine} runs at root@${host}"),
				"  commit ${Path.display(directory)}: machines/, secrets/ and aion/ record the install",
				"  kai machine switch ${machine}     there, after changing the Kaifile",
				"  aion customer machine destroy ${slug} ${machine}",
			],
			"\n",
		),
	)
}

destroy! = |slug, machine| {
	directory = customer_directory!(slug)?
	state = Customer.read_machine!(directory, machine)?
	if state.id.is_empty() {
		return Err(NoInstanceId("${machine} has no instance id; look for tag ${state.operation_tag} in Vultr"))
	}
	VultrApi.delete_instance!(state.id, auth!()?)?
	Customer.forget_machine!(directory, machine)?
	Stdout.line!("deleted instance ${state.id}; remove ${host_name(slug, machine)} from the customer's tailnet in its admin console")
}

# aion-tagged instances as Vultr reports them; reads only.
resources! = || {
	instances = VultrApi.list_instances_by_tag!("aion", auth!()?)?
	if instances.is_empty() {
		return Stdout.line!("no aion instances")
	}
	for i in instances {
		Stdout.line!("${i.label}  instance ${i.id}  ${i.status}/${i.server_status}  ${i.main_ip}  ${i.region} ${i.plan}  ${Str.join_with(i.tags, ",")}")?
	}
	Ok({})
}

main! = |args| {
	arguments = args.map(OsStr.display)
	match arguments {
		["customer", "new", slug] => customer_new!(slug, "")
		["customer", "new", slug, "--tailnet", tailnet] => customer_new!(slug, tailnet)
		["customer", "list"] => customer_list!()
		["customer", "machine", "new", slug, machine] => machine_new!(slug, machine, Bool.False)
		["customer", "machine", "new", slug, machine, "--dry-run"] => machine_new!(slug, machine, Bool.True)
		["customer", "machine", "install", slug, machine] => install!(slug, machine, "")
		["customer", "machine", "install", slug, machine, "--to", target] => install!(slug, machine, target)
		["customer", "machine", "destroy", slug, machine] => destroy!(slug, machine)
		["resources"] => resources!()
		_ => Stdout.line!(usage)
	}
}
