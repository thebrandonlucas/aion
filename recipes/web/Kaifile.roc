# A NixOS server with root SSH keys and Caddy serving /var/www over HTTPS.
# aion writes the aion/ files for each launch: the instance name, the keys
# that may log in as root, the operator key the host key is encrypted to, and
# the domain Caddy serves, the droplet's sslip.io name. The ones here are
# placeholders so the recipe checks on its own. aion copies the provider's
# profile into profiles/ beside a launch's copy of this file, since kai
# reads module files only from inside the project.
app [kaifile] {
	machine: "../../.kai-pin/kai/plugins/machine/main.roc",
	pf: platform "../../.kai-pin/kai/platform/main.roc",
	std: "../../.kai-pin/kai/plugins/std/main.roc",
}

import pf.Kaifile
import std.Config
import std.Std
import machine.Machine

import "aion/name" as name : Str
import "aion/root-keys" as root_keys : Str
import "aion/operators" as operators : Str
import "aion/domain" as domain : Str

lines = |text| text.split_on("\n").map(Str.trim).keep_if(|line| !line.is_empty())

project : List(Config.Setting)
project = [Name("web")]

kaifile = Kaifile.new([
	Std.plugin(project),
	Machine.plugin(
		project,
		[
			Machine(
				"web",
				[
					System("x86_64-linux"),
					StateVersion("25.11"),
					HostName(name.trim()),
					User("root", [SshKeys(lines(root_keys))]),
					Ssh,
					Disk(SingleDisk("/dev/vda")),
					Operators(lines(operators)),
					Services([Caddy([Site(domain.trim(), Files("/var/www"))])]),
					Modules(["profiles/digitalocean.nix"]),
				],
			),
		],
	),
])
