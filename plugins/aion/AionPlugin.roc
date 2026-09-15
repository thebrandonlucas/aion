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
	basic_webserver_name = "42jC1JT3auhHSmv2Ah8mW5F2MXiAakq1UQQ4NQceQjXw"
	basic_webserver_url = "https://github.com/roc-lang/basic-webserver/releases/download/0.16.0/${basic_webserver_name}.tar.zst"
	basic_webserver_hash = "sha256-tujSbdoP2iOzS9F5oChZFYFVprR7Z88yLKv7fT0RIn0="

	name_rules : List(Plugin.TextRule)
	name_rules = [
		NonemptyText("name must not be empty"),
		AllBytes({
			allowed: [AsciiLowercase, AsciiDigit, ExactByte(Bytes.hyphen)],
			message: "name may contain only lowercase ASCII letters, digits, and '-'",
		}),
	]

	build_inputs_field = Body.optional("inputs", StringList)

	build_command : Plugin.Command
	build_command = Plugin.Command.{
		argument_policy: AllowArguments,
		body: Body.object([
			Body.required("environment", Identifier),
			build_inputs_field,
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

	supported_build_targets : List(Plugin.BackendTarget)
	supported_build_targets = [
		{ arch: X64, os: LINUX, value: "x86_64-linux" },
		{ arch: AARCH64, os: LINUX, value: "aarch64-linux" },
		{ arch: X64, os: MACOS, value: "x86_64-darwin" },
		{ arch: AARCH64, os: MACOS, value: "aarch64-darwin" },
	]

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

	Source := { name : Str, url : Str }

	all_sources : Plugin.RenderContext -> Try(List(Source), Plugin.RendererDiagnostic)
	all_sources = |context|
		Plugin.project_configs(context, ["source"]).map_try(
			|entry| {
				source_name = match entry.header {
					["source", selected] | ["source", selected, _] => Ok(selected)
					_ => Err({ byte_offset: None, message: "source declaration requires a name" })
				}?
				url = Body.get_string(entry.config, "url") ? |_|
					{ byte_offset: None, message: "validated source '${source_name}' is missing 'url'" }
				Ok({ name: source_name, url })
			},
		)

	build_implementation : Plugin.Implementation
	build_implementation = Plugin.Implementation.{
		actions: [],
		backend: backend.name,
		command: build_command.name,
		renderer: |context| {
			system = Plugin.target_value(AionPlugin.supported_build_targets, context.host_os, context.host_arch) ? |_|
				{ byte_offset: None, message: "unsupported build platform" }
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
			inputs = Plugin.validated_strings(context.config, AionPlugin.build_inputs_field)?
			sources = AionPlugin.all_sources(context)?
			if !inputs.all(|input| sources.any(|source_input| source_input.name == input)) {
				return Err({ byte_offset: None, message: "build input has no declared source" })
			}
			selected_sources = sources.keep_if(|source_input| inputs.contains(source_input.name))
			directory = ".kai/roc-build"
			actions = [
				WriteUtf8({ content: AionPlugin.render_build_flake(selected_sources, system), path: "${directory}/flake.nix" }),
				WriteUtf8({ content: AionPlugin.render_build_nix({}), path: "${directory}/build.nix" }),
				WriteUtf8({
					content: Json.to_str({ inputs, name: artifact_name, output, source, system }),
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
								{ key: "target.system", value: system },
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
			if service_name != "aion" or artifact_name != "aion-init" {
				return Err({ byte_offset: None, message: "the MVP supports only the Aion agent service" })
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
				WriteUtf8({ content: AionPlugin.render_service_module({}), path: "${directory}/default.nix" }),
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

	render_build_flake : List(Source), Str -> Str
	render_build_flake = |sources, system| {
		source_lines = sources.map(
			|source_input| "  inputs.\"kai-source-${source_input.name}\" = { url = \"${source_input.url}\"; flake = false; };",
		)
		source_attrs = sources.map(
			|source_input| "\"${source_input.name}\" = inputs.\"kai-source-${source_input.name}\";",
		)
		Str.join_with(
			[
				"{",
				"  inputs.nixpkgs.url = \"github:NixOS/nixpkgs/nixos-unstable\";",
				"  inputs.roc-overlay.url = \"github:thebrandonlucas/roc-overlay\";",
			].concat(source_lines).concat([
				"  outputs = inputs@{ nixpkgs, roc-overlay, ... }: let",
				"    system = \"${system}\";",
				"    pkgs = import nixpkgs { inherit system; overlays = [ roc-overlay.overlays.default ]; };",
				"  in {",
				"    legacyPackages.\"${system}\" = pkgs;",
				"    kaiSources = { ${Str.join_with(source_attrs, " ")} };",
				"  };",
				"}",
			]),
			"\n",
		)
	}

	render_build_nix : {} -> Str
	render_build_nix = |_| Str.join_with(
		[
			"let",
			"  config = builtins.fromJSON (builtins.readFile ./build.json);",
			"  flake = builtins.getFlake (toString ./.);",
			"  pkgs = builtins.getAttr config.system flake.legacyPackages;",
			"  lib = pkgs.lib;",
			"  source = pkgs.nix-gitignore.gitignoreFilterRecursiveSource (_: _: true) \".git\\n.kai\" ../..;",
			"  inputLinks = lib.concatMapStringsSep \"\\n\" (name:",
			"    \"ln -s -- ${AionPlugin.nix_interpolation("lib.escapeShellArg (toString (builtins.getAttr name flake.kaiSources))")} .kai/inputs/${AionPlugin.nix_interpolation("lib.escapeShellArg name")}\"",
			"  ) config.inputs;",
			"  bitcoinQrAssets = if builtins.elem \"bitcoin-qr\" config.inputs then toString flake.kaiSources.\"bitcoin-qr\" + \"/dist/bitcoin-qr\" else \"\";",
			"  platform = pkgs.fetchurl {",
			"    url = \"${AionPlugin.basic_cli_url}\";",
			"    hash = \"${AionPlugin.basic_cli_hash}\";",
			"  };",
			"  rocHttp = pkgs.fetchurl {",
			"    url = \"${AionPlugin.roc_http_url}\";",
			"    hash = \"${AionPlugin.roc_http_hash}\";",
			"  };",
			"  basicWebserver = pkgs.fetchurl {",
			"    url = \"${AionPlugin.basic_webserver_url}\";",
			"    hash = \"${AionPlugin.basic_webserver_hash}\";",
			"  };",
			"in pkgs.runCommand (\"aion-build-\" + config.name) {",
			"  nativeBuildInputs = [ pkgs.rocpkgs.nightly pkgs.llvmPackages.bintools ];",
			"} ''",
			"  cp -R ${AionPlugin.nix_interpolation("source")}/. .",
			"  chmod -R u+w .",
			"  mkdir -p .kai/inputs",
			"  ${AionPlugin.nix_interpolation("inputLinks")}",
			"  cp ${AionPlugin.nix_interpolation("platform")} ${AionPlugin.basic_cli_name}.tar.zst",
			"  cp ${AionPlugin.nix_interpolation("rocHttp")} ${AionPlugin.roc_http_name}.tar.zst",
			"  cp ${AionPlugin.nix_interpolation("basicWebserver")} ${AionPlugin.basic_webserver_name}.tar.zst",
			"  roc unbundle ${AionPlugin.basic_cli_name}.tar.zst",
			"  roc unbundle ${AionPlugin.roc_http_name}.tar.zst",
			"  roc unbundle ${AionPlugin.basic_webserver_name}.tar.zst",
			"  substituteInPlace ${AionPlugin.basic_cli_name}/main.roc --replace-fail '${AionPlugin.roc_http_url}' \"$PWD/${AionPlugin.roc_http_name}/main.roc\"",
			"  substituteInPlace ${AionPlugin.basic_webserver_name}/main.roc --replace-fail '${AionPlugin.roc_http_url}' \"$PWD/${AionPlugin.roc_http_name}/main.roc\"",
			"  substituteInPlace ${AionPlugin.nix_interpolation("config.source")} --replace '${AionPlugin.basic_cli_url}' \"$PWD/${AionPlugin.basic_cli_name}/main.roc\"",
			"  substituteInPlace ${AionPlugin.nix_interpolation("config.source")} --replace '${AionPlugin.basic_webserver_url}' \"$PWD/${AionPlugin.basic_webserver_name}/main.roc\"",
			# Apps that do not declare the http package or browser assets have nothing to substitute.
			"  substituteInPlace ${AionPlugin.nix_interpolation("config.source")} --replace '${AionPlugin.roc_http_url}' \"$PWD/${AionPlugin.roc_http_name}/main.roc\"",
			"  substituteInPlace ${AionPlugin.nix_interpolation("config.source")} --replace-quiet 'BITCOIN_QR_ASSETS' ${AionPlugin.nix_interpolation("lib.escapeShellArg bitcoinQrAssets")}",
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
			"  inputs.kai.url = \"github:thebrandonlucas/kai/master\";",
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

	render_service_module : {} -> Str
	render_service_module = |_| {
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
				"  nix.settings.experimental-features = [ \"nix-command\" \"flakes\" ];",
				"  nix.settings.trusted-users = [ \"root\" \"aion\" ];",
				"  # Credentials are injected from DigitalOcean metadata at first boot, never baked into the image.",
				"  users.allowNoPasswordLogin = true;",
				"  users.users.root.hashedPassword = \"!\";",
				"  users.users.aion.shell = pkgs.bashInteractive;",
				"  # Unlock the account for public-key SSH; remote password authentication remains disabled.",
				"  users.users.aion.hashedPassword = \"\";",
				"  services.openssh.settings = {",
				"    PermitRootLogin = \"no\"; PasswordAuthentication = false;",
				"    KbdInteractiveAuthentication = false;",
				"  };",
				"  networking.firewall.allowedTCPPorts = [ 22 ];",
				"  environment.systemPackages = [ aionInit kaiPackage ];",
				"  systemd.tmpfiles.rules = [",
				"    \"d /home/aion/.pi 0700 aion users - -\"",
				"    \"d /home/aion/.pi/agent 0700 aion users - -\"",
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
