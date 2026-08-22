import parser.Body
import parser.Bytes
import kai.Plugin

MachinePlugin := [].{
	name = "aion-machine"

	name_rules : List(Plugin.TextRule)
	name_rules = [
		NonemptyText("machine name must not be empty"),
		AllBytes({
			allowed: [AsciiLowercase, AsciiDigit, ExactByte(Bytes.hyphen)],
			message: "machine name may contain only lowercase ASCII letters, digits, and '-'",
		}),
	]

	command : Plugin.Command
	command = Plugin.Command.{
		argument_policy: AllowArguments,
		body: Body.object([
			Body.required("system", String),
			Body.required("region", String),
			Body.required("size", String),
			Body.required("provider", String),
			Body.required("model", String),
			Body.required("packages", StringList),
		]),
		config: NamedConfig({ lookup: QualifiedThenUnqualified, name_rules }),
		config_block: RequiredConfigBlock("machine"),
		name: "machine-build",
	}

	backend : Plugin.Backend
	backend = Plugin.Backend.{
		determinate_system: Plugin.DeterminateSystem.{
			default_package_source: "nixpkgs",
			driver: Program("nix"),
			kind: Nix,
		},
		fallback: NoFallback,
		name: "nix",
		required_packages: [],
	}

	flake_template : Plugin.ActionTemplate
	flake_template = WriteConfigUtf8({
		output: "flake",
		path: ".kai/machines/agent/flake.nix",
	})

	implementation : Plugin.Implementation
	implementation = Plugin.Implementation.{
		actions: [
			flake_template,
			Exec({
				args: [
					"flake",
					"lock",
					"path:.kai/machines/agent",
					"--reference-lock-file",
					"kai.lock",
					"--output-lock-file",
					"kai.lock",
				],
				command: "nix",
			}),
			Exec({
				args: [
					"flake",
					"lock",
					"path:.kai/machines/agent",
					"--reference-lock-file",
					"kai.lock",
					"--output-lock-file",
					".kai/machines/agent/flake.lock",
				],
				command: "nix",
			}),
			Exec({
				args: [
					"build",
					"path:.kai/machines/agent#agent",
					"--no-update-lock-file",
					"--out-link",
					".kai/artifacts/agent-image",
				],
				command: "nix",
			}),
		],
		backend: backend.name,
		command: command.name,
		renderer: |context| {
			machine_name = match context.args {
				[selected] => Ok(selected)
				_ => Err({ byte_offset: None, message: "machine-build requires exactly one machine name" })
			}?
			system = Body.get_string(context.config, "system") ? |_| {
				byte_offset: None,
				message: "validated machine configuration is missing 'system'",
			}
			if machine_name != "agent" or system != "x86_64-linux" {
				Err({ byte_offset: None, message: "the MVP supports only machine 'agent' on x86_64-linux" })
			} else {
				Ok(
					Plugin.RenderResult.{
						actions: [],
						outputs: [{ name: "flake", text: MachinePlugin.render_flake(machine_name, system) }],
						requests: [],
						requested_packages: [],
					},
				)
			}
		},
		validator: NoValidation,
	}

	render_flake : Str, Str -> Str
	render_flake = |machine_name, system|
		Str.join_with(
			[
				"{",
				"  inputs.nixpkgs.url = \"github:NixOS/nixpkgs/nixos-unstable\";",
				"  outputs = { nixpkgs, ... }:",
				"    let pkgs = nixpkgs.legacyPackages.\"${system}\";",
				"    in {",
				"      packages.\"${system}\".agent = pkgs.writeText \"aion-${machine_name}-image\" \"machine backend ready\";",
				"    };",
				"}",
			],
			"\n",
		)

	commands : List(Plugin.Command)
	commands = [command]

	backends : List(Plugin.Backend)
	backends = [backend]

	implementations : List(Plugin.Implementation)
	implementations = [implementation]
}
