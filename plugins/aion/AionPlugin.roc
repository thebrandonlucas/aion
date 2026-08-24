import parser.Body
import parser.Bytes
import kai.Plugin

AionPlugin := [].{
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

	service_command : Plugin.Command
	service_command = Plugin.Command.{
		argument_policy: AllowArguments,
		body: Body.object([
			Body.required("artifact", String),
			Body.required("provider", String),
			Body.required("model", String),
		]),
		config: NamedConfig({ lookup: QualifiedThenUnqualified, name_rules }),
		config_block: RequiredConfigBlock("service"),
		name: "service",
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
				WriteUtf8({ content: AionPlugin.render_build_flake({}), path: "${directory}/flake.nix" }),
				WriteUtf8({ content: AionPlugin.render_build_nix({}), path: "${directory}/build.nix" }),
				WriteUtf8({
					content: Json.to_str({ name: artifact_name, output, source, system: "x86_64-linux" }),
					path: "${directory}/build.json",
				}),
			]
				.concat(AionPlugin.lock_actions(directory))
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
			Ok(
				Plugin.RenderResult.{
					actions,
					artifacts: [
						{
							attributes: [
								{ key: "backend", value: backend.name },
								{ key: "target.system", value: "x86_64-linux" },
							],
							kind: "kai.build/v1",
							name: artifact_name,
							path: ".kai/artifacts/${artifact_name}",
						},
					],
					outputs: [],
					requests: [],
					requested_packages: [],
				},
			)
		},
		validator: NoValidation,
	}

	service_implementation : Plugin.Implementation
	service_implementation = Plugin.Implementation.{
		actions: [],
		backend: backend.name,
		command: service_command.name,
		renderer: |context| {
			service_name = match context.args {
				[selected] => Ok(selected)
				_ => Err({ byte_offset: None, message: "service requires exactly one name" })
			}?
			artifact_name = Body.get_string(context.config, "artifact") ? |_| {
				byte_offset: None,
				message: "validated service configuration is missing 'artifact'",
			}
			provider = Body.get_string(context.config, "provider") ? |_| {
				byte_offset: None,
				message: "validated service configuration is missing 'provider'",
			}
			model = Body.get_string(context.config, "model") ? |_| {
				byte_offset: None,
				message: "validated service configuration is missing 'model'",
			}
			if service_name != "aion" or artifact_name != "aion-init" or provider != "ppq" or model != "openai/gpt-5.1-codex" {
				return Err({ byte_offset: None, message: "the MVP supports only the fixed Aion agent service" })
			}
			requests = [{ args: ["build", backend.name, artifact_name], status: "service: build ${artifact_name}" }]
			if !context.dependencies_resolved {
				return Ok({ actions: [], artifacts: [], outputs: [], requests, requested_packages: [] })
			}
			build = match context.dependency_artifacts.keep_if(
				|artifact| artifact.kind == "kai.build/v1" and artifact.name == artifact_name,
			) {
				[selected] => Ok(selected)
				[] => Err({ byte_offset: None, message: "build '${artifact_name}' did not produce a kai.build/v1 artifact" })
				_ => Err({ byte_offset: None, message: "build '${artifact_name}' produced multiple artifacts" })
			}?
			directory = ".kai/services/${service_name}"
			artifact_path = ".kai/artifacts/.services/${service_name}"
			actions = [
				WriteUtf8({ content: AionPlugin.render_service_flake({}), path: "${directory}/flake.nix" }),
				WriteUtf8({ content: AionPlugin.render_service_module(provider, model), path: "${directory}/default.nix" }),
				Exec({ args: ["-fL", build.path, "${directory}/aion-init"], command: "cp" }),
			]
				.concat(AionPlugin.lock_actions(directory))
				.concat([
					Exec({
						args: [
							"build",
							"path:${directory}#service",
							"--no-update-lock-file",
							"--out-link",
							artifact_path,
						],
						command: "nix",
					}),
				])
			Ok(
				Plugin.RenderResult.{
					actions,
					artifacts: [
						{
							attributes: [
								{ key: "backend", value: backend.name },
								{ key: "target.system", value: "x86_64-linux" },
							],
							kind: "kai.nixos.service/v1",
							name: service_name,
							path: artifact_path,
						},
					],
					outputs: [],
					requests,
					requested_packages: [],
				},
			)
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
			"    url = \"${AionPlugin.basic_cli_url}\";",
			"    hash = \"${AionPlugin.basic_cli_hash}\";",
			"  };",
			"  rocHttp = pkgs.fetchurl {",
			"    url = \"${AionPlugin.roc_http_url}\";",
			"    hash = \"${AionPlugin.roc_http_hash}\";",
			"  };",
			"in pkgs.runCommand (\"aion-build-\" + config.name) {",
			"  nativeBuildInputs = [ pkgs.rocpkgs.nightly pkgs.llvmPackages.bintools ];",
			"} ''",
			"  cp -R ${AionPlugin.nix_interpolation("source")}/. .",
			"  chmod -R u+w .",
			"  cp ${AionPlugin.nix_interpolation("platform")} ${AionPlugin.basic_cli_name}.tar.zst",
			"  cp ${AionPlugin.nix_interpolation("rocHttp")} ${AionPlugin.roc_http_name}.tar.zst",
			"  roc unbundle ${AionPlugin.basic_cli_name}.tar.zst",
			"  roc unbundle ${AionPlugin.roc_http_name}.tar.zst",
			"  substituteInPlace ${AionPlugin.basic_cli_name}/main.roc --replace-fail '${AionPlugin.roc_http_url}' \"$PWD/${AionPlugin.roc_http_name}/main.roc\"",
			"  substituteInPlace ${AionPlugin.nix_interpolation("config.source")} --replace-fail '${AionPlugin.basic_cli_url}' \"$PWD/${AionPlugin.basic_cli_name}/main.roc\"",
			# Apps that do not declare the http package have nothing to substitute.
			"  substituteInPlace ${AionPlugin.nix_interpolation("config.source")} --replace '${AionPlugin.roc_http_url}' \"$PWD/${AionPlugin.roc_http_name}/main.roc\"",
			"  roc build ${AionPlugin.nix_interpolation("config.source")} --opt=size --output=${AionPlugin.nix_interpolation("config.output")}",
			"  install -Dm755 ${AionPlugin.nix_interpolation("config.output")} $out",
			"''",
		],
		"\n",
	)

	render_service_flake : {} -> Str
	render_service_flake = |_| Str.join_with(
		[
			"{",
			"  inputs.nixpkgs.url = \"github:NixOS/nixpkgs/nixos-unstable\";",
			"  inputs.kai.url = \"github:thebrandonlucas/kai\";",
			"  inputs.kai.inputs.nixpkgs.follows = \"nixpkgs\";",
			"  outputs = { nixpkgs, kai, ... }: let",
			"    system = \"x86_64-linux\";",
			"    pkgs = nixpkgs.legacyPackages.\"x86_64-linux\";",
			"  in { packages.\"x86_64-linux\".service = pkgs.runCommand \"aion-machine-service\" {} ''",
			"    mkdir -p $out",
			"    cp ${AionPlugin.nix_interpolation("./default.nix")} $out/default.nix",
			"    cp ${AionPlugin.nix_interpolation("./aion-init")} $out/aion-init",
			"    cp ${AionPlugin.nix_interpolation("kai.packages.\"x86_64-linux\".kai")}/bin/kai $out/kai",
			"  ''; };",
			"}",
		],
		"\n",
	)

	render_service_module : Str, Str -> Str
	render_service_module = |provider, model| {
		aion_init = AionPlugin.nix_interpolation("aionInit")
		Str.join_with(
			[
				"{ modulesPath, pkgs, ... }:",
				"let",
				"  aionInit = pkgs.runCommand \"aion-init\" {} ''",
				"    install -Dm755 ${AionPlugin.nix_interpolation("./aion-init")} $out/bin/aion-init",
				"  '';",
				"  kaiPackage = pkgs.runCommand \"kai\" {} ''",
				"    install -Dm755 ${AionPlugin.nix_interpolation("./kai")} $out/bin/kai",
				"  '';",
				"in",
				"{",
				"  imports = [ (modulesPath + \"/virtualisation/digital-ocean-config.nix\") ];",
				"  image.efiSupport = false;",
				"  virtualisation.digitalOcean.setSshKeys = false;",
				"  users.mutableUsers = false;",
				"  # Credentials are injected from DigitalOcean metadata at first boot, never baked into the image.",
				"  users.allowNoPasswordLogin = true;",
				"  users.users.root.hashedPassword = \"!\";",
				"  users.users.aion.shell = pkgs.bashInteractive;",
				"  services.openssh.settings = {",
				"    PermitRootLogin = \"no\"; PasswordAuthentication = false;",
				"    KbdInteractiveAuthentication = false;",
				"  };",
				"  networking.firewall.allowedTCPPorts = [ 22 ];",
				"  environment.systemPackages = [ aionInit kaiPackage ];",
				"  environment.etc.\"aion/models.json\".text = builtins.toJSON {",
				"    providers.${provider} = {",
				"      baseUrl = \"https://api.ppq.ai/v1\"; api = \"openai-completions\";",
				"      apiKey = \"!cat /home/aion/.config/aion/model-key\";",
				"      models = [ {",
				"        id = \"${model}\"; name = \"${model}\"; reasoning = true;",
				"        input = [ \"text\" \"image\" ];",
				"        cost = { input = 0; output = 0; cacheRead = 0; cacheWrite = 0; };",
				"        contextWindow = 200000; maxTokens = 32768;",
				"      } ];",
				"    };",
				"  };",
				"  environment.etc.\"aion/settings.json\".text = builtins.toJSON {",
				"    defaultProvider = \"${provider}\"; defaultModel = \"${model}\";",
				"    enableInstallTelemetry = false; enableUpdateCheck = false;",
				"  };",
				"  systemd.tmpfiles.rules = [",
				"    \"d /home/aion/.pi 0700 aion users - -\"",
				"    \"d /home/aion/.pi/agent 0700 aion users - -\"",
				"    \"L+ /home/aion/.pi/agent/models.json - - - - /etc/aion/models.json\"",
				"    \"L+ /home/aion/.pi/agent/settings.json - - - - /etc/aion/settings.json\"",
				"  ];",
				"  systemd.services.aion-ssh-key = {",
				"    description = \"Install the one DigitalOcean SSH key for Aion\";",
				"    wantedBy = [ \"multi-user.target\" ]; before = [ \"sshd.service\" ];",
				"    after = [ \"digitalocean-metadata.service\" ]; requires = [ \"digitalocean-metadata.service\" ];",
				"    serviceConfig = { Type = \"oneshot\"; RemainAfterExit = true; ExecStart = \"${aion_init}/bin/aion-init install-ssh-key\"; };",
				"    unitConfig.ConditionPathExists = \"!/home/aion/.ssh/authorized_keys\";",
				"  };",
				"}",
			],
			"\n",
		)
	}

	nix_interpolation : Str -> Str
	nix_interpolation = |expression| Str.join_with(["$", "{", expression, "}"], "")

	commands : List(Plugin.Command)
	commands = [build_command, service_command]

	backends : List(Plugin.Backend)
	backends = [backend]

	implementations : List(Plugin.Implementation)
	implementations = [build_implementation, service_implementation]
}
