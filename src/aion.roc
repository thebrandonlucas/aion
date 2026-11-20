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
import DigitalOcean
import DigitalOceanApi
import Instance
import Launch
import SshKey

usage = Str.join_with(
	[
		"Aion - NixOS machines on DigitalOcean, installed by kai",
		"",
		"Usage:",
		"  aion launch <recipe> <name> [--dry-run] [--ssh-public-key-file <path>]",
		"  aion install <name>     retry kai's install on a launched droplet",
		"  aion update <name>      switch the machine to its instance's Kaifile.roc",
		"  aion destroy <name>     delete the droplet and the instance",
		"  aion list",
		"  aion resources        aion-tagged droplets in DigitalOcean (read-only)",
		"  aion customer new <slug> [--tailnet <magicdns-suffix>]",
		"  aion customer list",
		"",
		"A launch creates a droplet at once, bills from then on, and erases it to",
		"install the recipe. A dry run stages .aion/plans/<name>, prints kai's",
		"install plan and the DigitalOcean request, and creates nothing.",
		"",
		"Environment:",
		"  DIGITALOCEAN_TOKEN     API token, for launch and destroy (or in .env)",
		"  AION_KAI               kai to run (default: the 0.0.13 release, through nix run)",
		"  AION_REGION            DigitalOcean region (default: ${Launch.default_region})",
		"  AION_SIZE              Droplet size (default: ${Launch.default_size})",
		"  AION_DIGITALOCEAN_URL  API base URL, for a mock (default: ${DigitalOceanApi.default_url})",
		"  AION_SSH_HOST          reach every launch at this host instead, for a local VM",
		"  AION_CLIENTS           where customer repositories live (default: ~/clients)",
		"  AION_TEMPLATE          the kai-box client skeleton (default: ../kai-box-template/client)",
		"  AION_OPERATOR_KEY      the operator's public key (default: ~/.ssh/id_ed25519.pub)",
		"  AION_RECOVERY_RECIPIENT  the offline recovery key's age recipient, a second Operator (or in .env)",
	],
	"\n",
)

is_name_byte = |byte| (byte >= 'a' and byte <= 'z') or (byte >= '0' and byte <= '9')

# A lowercase DNS label, which is also a valid kai HostName and droplet name.
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

# kai 0.0.13, the release whose platform and machine plugin the recipes
# name, run from its flake at the release commit.
release_kai = ["run", "github:thebrandonlucas/kai/9b0174df172041f00acb5d5387c65af96cd9950a", "--"]

# Runs kai in a launch's project, showing its output: AION_KAI if set, or
# else the release through nix.
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

# The token from the environment, or else from .env. It is only ever sent
# in the Authorization header.
auth! = || {
	token = Env.var_str!(OsStr.from_str("DIGITALOCEAN_TOKEN")) ?? dotenv_value!("DIGITALOCEAN_TOKEN")?
	Ok({ url: env_or!("AION_DIGITALOCEAN_URL", DigitalOceanApi.default_url), token })
}

# Where kai and ssh reach a launch: its address, unless AION_SSH_HOST points
# a test at a local VM, such as an ~/.ssh/config alias.
ssh_host! = |address| env_or!("AION_SSH_HOST", address)

# The operator's key and a launch's aion/ inputs.
launch_inputs! = |name, key_file, domain| {
	if !valid_name(name) {
		return Err(InvalidName("use 1-63 lowercase ASCII letters, digits, or internal '-' characters"))
	}
	home = Env.var_str!(OsStr.from_str("HOME"))?
	operator = read_key!(Path.join(Path.utf8(home), ".ssh/id_ed25519.pub"))?
	customer = if (key_file.is_empty()) operator else read_key!(Path.utf8(key_file))?
	Ok({ operator, inputs: { name, root_keys: Launch.root_keys(customer, operator), operators: [operator], domain } })
}

# A fresh droplet's host key is unknown, and the installed system replaces
# it, so this one probe trusts whatever answers and records nothing.
wait_for_ssh! = |host, attempt| {
	probe = Cmd.new(OsStr.from_str("ssh"))
		.args(strs(["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", "-o", "LogLevel=ERROR", "root@${host}", "true"]))
		.run!()
	ready = match probe {
		Ok(ran) => ran.status == Exited(0)
		Err(_) => Bool.False
	}
	if ready {
		Ok({})
	} else if attempt >= 30 {
		Err(SshNotReady(host))
	} else {
		Duration.sleep!(Duration.seconds(10))?
		wait_for_ssh!(host, attempt + 1)
	}
}

# The droplet's public IPv4 once it is active, polling every 5 seconds.
wait_active! = |id, auth, attempt| {
	droplet = DigitalOceanApi.get_droplet!(id, auth)?
	match (droplet.status, DigitalOcean.public_ipv4(droplet)) {
		("active", Ok(address)) => Ok(address)
		_ if attempt >= 60 => Err(DropletNotActive(id))
		_ => {
			Duration.sleep!(Duration.seconds(5))?
			wait_active!(id, auth, attempt + 1)
		}
	}
}

# After an uncertain POST, the droplet the operation tag names, if any.
reconcile! = |operation_tag, auth|
	match DigitalOceanApi.list_droplets_by_tag!(operation_tag, auth)? {
		[droplet] => Ok(droplet.id)
		[] => Err(CreateUncertain("no droplet is tagged ${operation_tag}; check `aion list` and DigitalOcean before retrying"))
		_ => Err(CreateUncertain("several droplets are tagged ${operation_tag}; delete the extras in DigitalOcean"))
	}

launch! = |recipe, name, key_file| {
	auth = auth!()?
	region = env_or!("AION_REGION", Launch.default_region)
	size = env_or!("AION_SIZE", Launch.default_size)
	launch = launch_inputs!(name, key_file, Launch.placeholder_domain)?
	directory = Instance.directory(name)
	if Path.exists!(directory)? {
		return Err(InstanceExists("${name} is already launched; `aion destroy ${name}` first"))
	}
	Instance.stage!(Path.join(Path.utf8("recipes"), recipe), Path.utf8("profiles/digitalocean/digitalocean.nix"), "digitalocean.nix", directory, launch.inputs)?
	Stdout.line!(Ansi.heading("Building ${recipe} for ${name} before creating anything"))?
	kai!(directory, ["machine", "build", recipe])?
	if DigitalOceanApi.list_droplets_by_tag!("aion", auth)?.any(|droplet| droplet.name == name) {
		return Err(DropletExists("an aion droplet named ${name} exists; see `aion list`"))
	}
	key = DigitalOceanApi.register_ssh_key!("aion-operator", launch.operator, auth)?
	operation_tag = "aion-droplet-${U64.to_str(Random.seed_u64!()?)}"
	pending = { address: "", droplet_id: 0, name, operation_tag, recipe, region, size, ssh_key_id: key.id, status: "creating" }
	Instance.save!(pending)?
	Stdout.line!(Ansi.heading("Creating droplet ${name} (${size}, ${region}), tagged ${operation_tag}"))?
	body = DigitalOcean.base_droplet_body(name, Launch.base_image, [key.id], operation_tag, region, size)
	id = match DigitalOceanApi.create_droplet_once!(body, auth) {
		PostAccepted(droplet) => droplet.id
		PostRejected(error) => {
			Path.delete_all!(directory) ?? {}
			return Err(error)
		}
		PostUncertain(_) => reconcile!(operation_tag, auth)?
	}
	Instance.save!({ ..pending, droplet_id: id })?
	address = wait_active!(id, auth, 1)?
	created = { ..pending, droplet_id: id, address, status: "created" }
	Instance.save!(created)?
	Path.write_utf8!(Path.join(directory, "aion/domain"), "${Launch.sslip_domain(address)}\n")?
	Stdout.line!(Ansi.heading("Droplet ${U64.to_str(id)} is active at ${address}; waiting for SSH"))?
	install!(name)
}

# Drops every key ~/.ssh/known_hosts holds for `host`, which may be an
# earlier server's at a reused address. ssh-keygen keeps known_hosts.old.
forget_host_key! = |host| {
	_ = Cmd.new(OsStr.from_str("ssh-keygen")).args(strs(["-R", host])).run!()
	{}
}

# Trusts exactly the host key kai made for the machine before it booted, so
# kai's ssh and nix copy can reach it with host-key checking on (kai#496).
pin_host_key! = |state| {
	public = Path.read_utf8!(Path.join(Instance.directory(state.name), "secrets/hosts/${state.recipe}.pub"))?
	key = Str.join_with(public.trim().split_on(" ").take_first(2), " ")
	host = ssh_host!(state.address)
	home = Env.var_str!(OsStr.from_str("HOME"))?
	forget_host_key!(host)
	Path.append_utf8!(Path.join(Path.utf8(home), ".ssh/known_hosts"), "${host} ${key}\n")
}

# Installs a created launch's recipe with kai, erasing the droplet's disk.
# Run again after a failed install; the droplet keeps running meanwhile.
install! = |name| {
	state = Instance.read!(name)?
	host = ssh_host!(state.address)
	installed = match wait_for_ssh!(host, 1) {
		Ok({}) => kai!(Instance.directory(name), Launch.install_argv(state.recipe, host))
		Err(error) => Err(error)
	}
	match installed {
		Ok({}) => {}
		Err(error) => {
			_ = Stdout.line!(Ansi.red("Install failed; droplet ${U64.to_str(state.droplet_id)} is still running. Retry with `aion install ${name}` or remove it with `aion destroy ${name}`.")) ?? {}
			return Err(error)
		}
	}
	pin_host_key!(state)?
	Instance.save!({ ..state, status: "installed" })?
	Stdout.line!(
		Str.join_with(
			[
				Ansi.green("${name} runs ${state.recipe} at ${state.address}"),
				"  ssh root@${state.address}",
				"  aion update ${name}     after changing .aion/instances/${name}/Kaifile.roc",
				"  aion destroy ${name}",
			],
			"\n",
		),
	)
}

update! = |name| {
	state = Instance.read!(name)?
	if state.status != "installed" {
		return Err(NotInstalled("${name} is ${state.status}; run `aion install ${name}`"))
	}
	kai!(Instance.directory(name), Launch.switch_argv(state.recipe, ssh_host!(state.address)))
}

destroy! = |name| {
	auth = auth!()?
	state = Instance.read!(name)?
	if state.droplet_id == 0 {
		return Err(NoDropletId("${name} has no droplet id; look for tag ${state.operation_tag} in DigitalOcean"))
	}
	DigitalOceanApi.delete_droplet!(state.droplet_id, auth)?
	forget_host_key!(ssh_host!(state.address))
	Path.delete_all!(Instance.directory(name))?
	Stdout.line!("deleted droplet ${U64.to_str(state.droplet_id)} and .aion/instances/${name}")
}

# aion-tagged droplets as DigitalOcean reports them; reads only.
resources! = || {
	auth = auth!()?
	droplets = DigitalOceanApi.list_droplets_by_tag!("aion", auth)?
	if droplets.is_empty() {
		return Stdout.line!("no aion droplets")
	}
	for d in droplets {
		address = DigitalOcean.public_ipv4(d) ?? "-"
		Stdout.line!("${d.name}  droplet ${U64.to_str(d.id)}  ${d.status}  ${address}  ${d.region.slug} ${d.size_slug}  ${Str.join_with(d.tags, ",")}")?
	}
	Ok({})
}

list! = || {
	for name in Instance.names!()? {
		line = match Instance.read!(name) {
			Ok(s) => "${name}  ${s.recipe}  ${s.status}  ${s.address}  droplet ${U64.to_str(s.droplet_id)}  ${s.region} ${s.size}"
			Err(_) => "${name}  (no readable instance.json)"
		}
		Stdout.line!(line)?
	}
	Ok({})
}

launch_dry_run! = |recipe, name, key_file| {
	region = env_or!("AION_REGION", Launch.default_region)
	size = env_or!("AION_SIZE", Launch.default_size)
	address = Launch.example_address
	launch = launch_inputs!(name, key_file, Launch.sslip_domain(address))?
	target = Instance.plan_directory(name)
	Path.delete_all!(target) ?? {}
	Instance.stage!(Path.join(Path.utf8("recipes"), recipe), Path.utf8("profiles/digitalocean/digitalocean.nix"), "digitalocean.nix", target, launch.inputs)?
	Stdout.line!(Ansi.heading("Staged ${Path.display(target)} from recipes/${recipe}"))?
	kai!(target, ["check"])?
	Stdout.line!(Ansi.heading("kai's install plan for root@${address}"))?
	kai!(target, Launch.dry_install_argv(recipe, address))?
	body = DigitalOcean.base_droplet_body(name, Launch.base_image, [0], "aion-droplet-DRY-RUN", region, size)
	Stdout.line!(
		Str.join_with(
			[
				Ansi.heading("A launch would then"),
				"1. build ${recipe}, register the operator key, and POST ${DigitalOceanApi.default_url}/v2/droplets once:",
				"   ${Str.inspect(body)}",
				"   (ssh_keys is the operator key's DigitalOcean id; the tag is unique per launch)",
				"2. poll the droplet until it is active, and write aion/domain from its IPv4",
				"3. run, in .aion/instances/${name}: ${show_argv(Launch.install_argv(recipe, "<ipv4>"))}",
				"4. update later with: ${show_argv(Launch.switch_argv(recipe, "<ipv4>"))}",
				"",
				Ansi.dim("Dry run: nothing was sent to DigitalOcean."),
			],
			"\n",
		),
	)
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
				.concat(
					[
						"  1. work through ONBOARDING.md: the tailnet, then each secret with `kai secret set box ...`",
						"  2. kai update",
						"  3. aion customer machine new ${slug} box",
					],
				),
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

main! = |args| {
	arguments = args.map(OsStr.display)
	match arguments {
		["customer", "new", slug] => customer_new!(slug, "")
		["customer", "new", slug, "--tailnet", tailnet] => customer_new!(slug, tailnet)
		["customer", "list"] => customer_list!()
		["launch", recipe, name, "--dry-run"] => launch_dry_run!(recipe, name, "")
		["launch", recipe, name, "--dry-run", "--ssh-public-key-file", path] => launch_dry_run!(recipe, name, path)
		["launch", recipe, name] => launch!(recipe, name, "")
		["launch", recipe, name, "--ssh-public-key-file", path] => launch!(recipe, name, path)
		["install", name] => install!(name)
		["update", name] => update!(name)
		["destroy", name] => destroy!(name)
		["list"] => list!()
		["resources"] => resources!()
		_ => Stdout.line!(usage)
	}
}
