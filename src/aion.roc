app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.OsStr
import pf.Path
import pf.Stdout

import Ansi
import DigitalOcean
import Instance
import Launch
import SshKey

usage = Str.join_with(
	[
		"Aion - NixOS machines on DigitalOcean, installed by kai",
		"",
		"Usage:",
		"  aion launch <recipe> <name> --dry-run [--ssh-public-key-file <path>]",
		"",
		"A dry run stages the launch in .aion/plans/<name>, checks it with kai, prints",
		"kai's install plan and the DigitalOcean request, and creates nothing.",
		"",
		"Environment:",
		"  AION_KAI     kai to run (default: .kai-pin/kai-bin/kai)",
		"  AION_REGION  DigitalOcean region (default: ${Launch.default_region})",
		"  AION_SIZE    Droplet size (default: ${Launch.default_size})",
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

# Runs kai in a launch's project, showing its output.
kai! = |directory, argv| {
	kai = Path.absolute!(Path.utf8(env_or!("AION_KAI", ".kai-pin/kai-bin/kai")))?
	ran = Cmd.new(Path.to_os_str(kai))
		.args(argv.map(OsStr.from_str))
		.cwd(directory)
		.inherit_stdio()
		.call!()
	match ran {
		Ok(_) => Ok({})
		Err(_) => Err(KaiFailed(Str.join_with(argv, " ")))
	}
}

show_argv = |argv| Str.join_with(["kai"].concat(argv), " ")

launch_dry_run! = |recipe, name, key_file| {
	if !valid_name(name) {
		return Err(InvalidName("use 1-63 lowercase ASCII letters, digits, or internal '-' characters"))
	}
	home = Env.var_str!(OsStr.from_str("HOME"))?
	operator = read_key!(Path.join(Path.utf8(home), ".ssh/id_ed25519.pub"))?
	customer = if (key_file.is_empty()) operator else read_key!(Path.utf8(key_file))?
	region = env_or!("AION_REGION", Launch.default_region)
	size = env_or!("AION_SIZE", Launch.default_size)
	address = Launch.example_address
	inputs = {
		name,
		root_keys: Launch.root_keys(customer, operator),
		operators: [operator],
		domain: Launch.sslip_domain(address),
	}
	target = Instance.plan_directory(name)
	Path.delete_all!(target) ?? {}
	Instance.stage!(
		Path.join(Path.utf8("recipes"), recipe),
		Path.utf8("profiles/digitalocean/digitalocean.nix"),
		"digitalocean.nix",
		target,
		inputs,
	)?
	Stdout.line!(Ansi.heading("Staged ${Path.display(target)} from recipes/${recipe}"))?
	kai!(target, ["check"])?
	Stdout.line!(Ansi.heading("kai's install plan for root@${address}"))?
	kai!(target, Launch.dry_install_argv(recipe, address))?
	body = DigitalOcean.base_droplet_body(name, Launch.base_image, [0], "aion-droplet-DRY-RUN", region, size)
	Stdout.line!(
		Str.join_with(
			[
				Ansi.heading("A launch would then"),
				"1. ask you to type 'create ${name}'",
				"2. POST https://api.digitalocean.com/v2/droplets once, with",
				"   ${Str.inspect(body)}",
				"   (ssh_keys is the operator key's DigitalOcean id; the tag is unique per launch)",
				"3. poll the droplet until it is active, and write aion/domain from its IPv4",
				"4. run, in .aion/instances/${name}: ${show_argv(Launch.install_argv(recipe, "<ipv4>"))}",
				"5. update later with: ${show_argv(Launch.switch_argv(recipe, "<ipv4>"))}",
				"",
				Ansi.dim("Dry run: nothing was sent to DigitalOcean."),
			],
			"\n",
		),
	)
}

main! = |args| {
	arguments = args.map(OsStr.display)
	match arguments {
		["launch", recipe, name, "--dry-run"] => launch_dry_run!(recipe, name, "")
		["launch", recipe, name, "--dry-run", "--ssh-public-key-file", path] => launch_dry_run!(recipe, name, path)
		["launch", _, _, ..] => Err(LiveLaunchNotEnabled("only --dry-run for now; a live launch creates a billable droplet"))
		_ => Stdout.line!(usage)
	}
}
