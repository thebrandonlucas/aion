import parser.Body
import parser.Bytes
import kai.Plugin

MachinePlugin := [].{
	name = "aion"

	basic_cli_name = "F1JVZPYfWP71s8vk6tHcV1Qx1Ef6CZkwswGoCn8VHZmL"
	basic_cli_url = "https://github.com/roc-lang/basic-cli/releases/download/0.22.0/${basic_cli_name}.tar.zst"
	basic_cli_hash = "sha256-04xUSXYJU4IHIf9/kjbfTghdgokYBFvZDfuTLWUg7kc="
	roc_http_name = "6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS"
	roc_http_url = "https://github.com/roc-lang/http/releases/download/1.0.0/${roc_http_name}.tar.zst"
	roc_http_hash = "sha256-6e+qlQ5y9vds326vAEJFcvppsEumEnMjV6wEU2ePArQ="

	name_rules : List(Plugin.TextRule)
	name_rules = [
		NonemptyText("name must not be empty"),
		AllBytes({
			allowed: [AsciiLowercase, AsciiDigit, ExactByte(Bytes.hyphen)],
			message: "name may contain only lowercase ASCII letters, digits, and '-'",
		}),
	]

	build_command : Plugin.Command
	build_command = Plugin.Command.{
		argument_policy: AllowArguments,
		body: Body.object([
			Body.required("environment", Identifier),
			Body.required("source", String),
			Body.required("output", String),
		]),
		config: NamedWithRelatedConfig({
			lookup: QualifiedThenUnqualified,
			name_rules,
			related_block: "environment",
			related_body: Body.object([
				Body.required("packages", StringList),
				Body.optional("overlays", StringList),
			]),
			related_field: "environment",
		}),
		config_block: RequiredConfigBlock("build"),
		name: "build",
	}

	machine_command : Plugin.Command
	machine_command = Plugin.Command.{
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

	lock_actions : Str -> List(Plugin.Action)
	lock_actions = |directory| [
		Exec({
			args: [
				"flake",
				"lock",
				"path:${directory}",
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
				"path:${directory}",
				"--reference-lock-file",
				"kai.lock",
				"--output-lock-file",
				"${directory}/flake.lock",
			],
			command: "nix",
		}),
	]

	build_implementation : Plugin.Implementation
	build_implementation = Plugin.Implementation.{
		actions: [],
		backend: backend.name,
		command: build_command.name,
		renderer: |context| {
			artifact_name = match context.args {
				[selected] => Ok(selected)
				_ => Err({ byte_offset: None, message: "build requires exactly one artifact name" })
			}?
			source = Body.get_string(context.config, "source") ? |_| {
				byte_offset: None,
				message: "validated build configuration is missing 'source'",
			}
			output = Body.get_string(context.config, "output") ? |_| {
				byte_offset: None,
				message: "validated build configuration is missing 'output'",
			}
			directory = ".kai/roc-build"
			actions = [
				WriteUtf8({ content: MachinePlugin.render_build_flake({}), path: "${directory}/flake.nix" }),
				WriteUtf8({ content: MachinePlugin.render_build_nix({}), path: "${directory}/build.nix" }),
				WriteUtf8({
					content: Json.to_str({ name: artifact_name, output, source, system: "x86_64-linux" }),
					path: "${directory}/build.json",
				}),
			]
				.concat(MachinePlugin.lock_actions(directory))
				.concat([
					Exec({
						args: [
							"build",
							"--file",
							"${directory}/build.nix",
							"--print-build-logs",
							"--out-link",
							".kai/artifacts/${artifact_name}",
						],
						command: "nix",
					}),
				])
			Ok(Plugin.RenderResult.{ actions, outputs: [], requests: [], requested_packages: [] })
		},
		validator: NoValidation,
	}

	machine_implementation : Plugin.Implementation
	machine_implementation = Plugin.Implementation.{
		actions: [WriteConfigUtf8({ output: "flake", path: ".kai/machines/agent/flake.nix" })],
		backend: backend.name,
		command: machine_command.name,
		renderer: |context| {
			machine_name = match context.args {
				[selected] => Ok(selected)
				_ => Err({ byte_offset: None, message: "machine-build requires exactly one machine name" })
			}?
			system = Body.get_string(context.config, "system") ? |_| {
				byte_offset: None,
				message: "validated machine configuration is missing 'system'",
			}
			provider = Body.get_string(context.config, "provider") ? |_| {
				byte_offset: None,
				message: "validated machine configuration is missing 'provider'",
			}
			model = Body.get_string(context.config, "model") ? |_| {
				byte_offset: None,
				message: "validated machine configuration is missing 'model'",
			}
			if machine_name != "agent" or system != "x86_64-linux" {
				Err({ byte_offset: None, message: "the MVP supports only machine 'agent' on x86_64-linux" })
			} else {
				directory = ".kai/machines/agent"
				copy_init = Exec({
					# -f replaces the previous read-only copy of the Nix store artifact.
					args: ["-fL", ".kai/artifacts/aion-init", "${directory}/aion-init"],
					command: "cp",
				})
				actions = [copy_init].concat(MachinePlugin.lock_actions(directory)).concat([
					Exec({
						args: [
							"build",
							"path:${directory}#agent",
							"--no-update-lock-file",
							"--print-build-logs",
							"--out-link",
							".kai/artifacts/agent-image",
						],
						command: "nix",
					}),
				])
				Ok(
					Plugin.RenderResult.{
						actions,
						outputs: [{ name: "flake", text: MachinePlugin.render_machine_flake(system, provider, model) }],
						requests: [],
						requested_packages: [],
					},
				)
			}
		},
		validator: NoValidation,
	}

	render_build_flake : {} -> Str
	render_build_flake = |_| Str.join_with(
		[
			"{",
			"  inputs.nixpkgs.url = \"github:NixOS/nixpkgs/nixos-unstable\";",
			"  inputs.roc-overlay.url = \"github:thebrandonlucas/roc-overlay\";",
			"  outputs = { nixpkgs, roc-overlay, ... }: let",
			"    system = \"x86_64-linux\";",
			"    pkgs = import nixpkgs { inherit system; overlays = [ roc-overlay.overlays.default ]; };",
			"  in { legacyPackages.\"x86_64-linux\" = pkgs; };",
			"}",
		],
		"\n",
	)

	render_build_nix : {} -> Str
	render_build_nix = |_| Str.join_with(
		[
			"let",
			"  config = builtins.fromJSON (builtins.readFile ./build.json);",
			"  flake = builtins.getFlake (toString ./.);",
			"  pkgs = builtins.getAttr config.system flake.legacyPackages;",
			"  source = pkgs.nix-gitignore.gitignoreFilterRecursiveSource (_: _: true) \".git\\n.kai\" ../..;",
			"  platform = pkgs.fetchurl {",
			"    url = \"${MachinePlugin.basic_cli_url}\";",
			"    hash = \"${MachinePlugin.basic_cli_hash}\";",
			"  };",
			"  rocHttp = pkgs.fetchurl {",
			"    url = \"${MachinePlugin.roc_http_url}\";",
			"    hash = \"${MachinePlugin.roc_http_hash}\";",
			"  };",
			"in pkgs.runCommand (\"aion-build-\" + config.name) {",
			"  nativeBuildInputs = [ pkgs.rocpkgs.nightly pkgs.llvmPackages.bintools ];",
			"} ''",
			"  cp -R ${MachinePlugin.nix_interpolation("source")}/. .",
			"  chmod -R u+w .",
			"  cp ${MachinePlugin.nix_interpolation("platform")} ${MachinePlugin.basic_cli_name}.tar.zst",
			"  cp ${MachinePlugin.nix_interpolation("rocHttp")} ${MachinePlugin.roc_http_name}.tar.zst",
			"  roc unbundle ${MachinePlugin.basic_cli_name}.tar.zst",
			"  roc unbundle ${MachinePlugin.roc_http_name}.tar.zst",
			"  substituteInPlace ${MachinePlugin.basic_cli_name}/main.roc --replace-fail '${MachinePlugin.roc_http_url}' \"$PWD/${MachinePlugin.roc_http_name}/main.roc\"",
			"  substituteInPlace ${MachinePlugin.nix_interpolation("config.source")} --replace-fail '${MachinePlugin.basic_cli_url}' \"$PWD/${MachinePlugin.basic_cli_name}/main.roc\"",
			# Apps that do not declare the http package have nothing to substitute.
			"  substituteInPlace ${MachinePlugin.nix_interpolation("config.source")} --replace '${MachinePlugin.roc_http_url}' \"$PWD/${MachinePlugin.roc_http_name}/main.roc\"",
			"  roc build ${MachinePlugin.nix_interpolation("config.source")} --opt=size --output=${MachinePlugin.nix_interpolation("config.output")}",
			"  install -Dm755 ${MachinePlugin.nix_interpolation("config.output")} $out",
			"''",
		],
		"\n",
	)

	render_machine_flake : Str, Str, Str -> Str
	render_machine_flake = |system, provider, model| {
		aion_init = MachinePlugin.nix_interpolation("aionInit")
		Str.join_with(
			[
				"{",
				"  inputs.nixpkgs.url = \"github:NixOS/nixpkgs/nixos-unstable\";",
				"  inputs.kai.url = \"github:thebrandonlucas/kai\";",
				"  outputs = { nixpkgs, kai, ... }:",
				"    let",
				"      system = \"${system}\";",
				"      pkgs = nixpkgs.legacyPackages.\"${system}\";",
				"      initBinary = ./aion-init;",
				"      aionInit = pkgs.runCommand \"aion-init\" {} ''",
				"        install -Dm755 ${MachinePlugin.nix_interpolation("initBinary")} $out/bin/aion-init",
				"      '';",
				"      kaiPackage = kai.packages.\"${system}\".kai;",
				"      machine = nixpkgs.lib.nixosSystem {",
				"        inherit system;",
				"        modules = [ ({ modulesPath, pkgs, ... }: {",
				"          imports = [ (modulesPath + \"/virtualisation/digital-ocean-image.nix\") ];",
				"          image.baseName = \"aion-agent\";",
				"          virtualisation.diskSize = 8192;",
				"          virtualisation.digitalOcean.setSshKeys = false;",
				"          users.mutableUsers = false;",
				"          # Credentials are injected from DigitalOcean metadata at first boot, never baked into the image.",
				"          users.allowNoPasswordLogin = true;",
				"          users.users.root.hashedPassword = \"!\";",
				"          users.users.aion = {",
				"            isNormalUser = true; createHome = true; home = \"/home/aion\";",
				"            shell = pkgs.bashInteractive;",
				"          };",
				"          services.openssh.settings = {",
				"            PermitRootLogin = \"no\"; PasswordAuthentication = false;",
				"            KbdInteractiveAuthentication = false;",
				"          };",
				"          networking.firewall.allowedTCPPorts = [ 22 ];",
				"          environment.systemPackages = [ aionInit kaiPackage pkgs.git pkgs.pi-coding-agent ];",
				"          environment.etc.\"aion/models.json\".text = builtins.toJSON {",
				"            providers.${provider} = {",
				"              baseUrl = \"https://api.ppq.ai/v1\"; api = \"openai-completions\";",
				"              apiKey = \"!cat /home/aion/.config/aion/model-key\";",
				"              models = [ {",
				"                id = \"${model}\"; name = \"${model}\"; reasoning = true;",
				"                input = [ \"text\" \"image\" ];",
				"                cost = { input = 0; output = 0; cacheRead = 0; cacheWrite = 0; };",
				"                contextWindow = 200000; maxTokens = 32768;",
				"              } ];",
				"            };",
				"          };",
				"          environment.etc.\"aion/settings.json\".text = builtins.toJSON {",
				"            defaultProvider = \"${provider}\"; defaultModel = \"${model}\";",
				"            enableInstallTelemetry = false; enableUpdateCheck = false;",
				"          };",
				"          systemd.tmpfiles.rules = [",
				"            \"d /home/aion/.pi 0700 aion users - -\"",
				"            \"d /home/aion/.pi/agent 0700 aion users - -\"",
				"            \"L+ /home/aion/.pi/agent/models.json - - - - /etc/aion/models.json\"",
				"            \"L+ /home/aion/.pi/agent/settings.json - - - - /etc/aion/settings.json\"",
				"          ];",
				"          systemd.services.aion-ssh-key = {",
				"            description = \"Install the one DigitalOcean SSH key for Aion\";",
				"            wantedBy = [ \"multi-user.target\" ]; before = [ \"sshd.service\" ];",
				"            after = [ \"digitalocean-metadata.service\" ]; requires = [ \"digitalocean-metadata.service\" ];",
				"            serviceConfig = { Type = \"oneshot\"; RemainAfterExit = true; ExecStart = \"${aion_init}/bin/aion-init install-ssh-key\"; };",
				"            unitConfig.ConditionPathExists = \"!/home/aion/.ssh/authorized_keys\";",
				"          };",
				"          system.stateVersion = \"25.11\";",
				"        }) ];",
				"      };",
				"    in {",
				"      nixosConfigurations.agent = machine;",
				"      packages.\"${system}\".agent = machine.config.system.build.digitalOceanImage;",
				"    };",
				"}",
			],
			"\n",
		)
	}

	nix_interpolation : Str -> Str
	nix_interpolation = |expression| Str.join_with(["$", "{", expression, "}"], "")

	commands : List(Plugin.Command)
	commands = [build_command, machine_command]

	backends : List(Plugin.Backend)
	backends = [backend]

	implementations : List(Plugin.Implementation)
	implementations = [build_implementation, machine_implementation]
}
