import parser.Fields
import kai.Kaifile
import kai.Plugin

AionBuildPlugin := [].{
	plugin : Plugin.Definition
	plugin = Plugin.Definition.{ backends, implementations, name, schema }

	name = "aion-build"

	basic_cli_name = "F1JVZPYfWP71s8vk6tHcV1Qx1Ef6CZkwswGoCn8VHZmL"
	basic_cli_url = "https://github.com/roc-lang/basic-cli/releases/download/0.22.0/${basic_cli_name}.tar.zst"
	basic_cli_hash = "sha256-04xUSXYJU4IHIf9/kjbfTghdgokYBFvZDfuTLWUg7kc="
	roc_http_name = "6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS"
	roc_http_url = "https://github.com/roc-lang/http/releases/download/1.0.0/${roc_http_name}.tar.zst"
	roc_http_hash = "sha256-6e+qlQ5y9vds326vAEJFcvppsEumEnMjV6wEU2ePArQ="
	basic_webserver_name = "42jC1JT3auhHSmv2Ah8mW5F2MXiAakq1UQQ4NQceQjXw"
	basic_webserver_url = "https://github.com/roc-lang/basic-webserver/releases/download/0.16.0/${basic_webserver_name}.tar.zst"
	basic_webserver_hash = "sha256-tujSbdoP2iOzS9F5oChZFYFVprR7Z88yLKv7fT0RIn0="

	overlays_field = Kaifile.optional("overlays", StringList)

	environment_block = Kaifile.named_block({
		header: "environment <environment>",
		fields: [
			Kaifile.required("packages", StringList),
			overlays_field,
		],
		name_rules: [NonemptyText("environment name must not be empty")],
	})

	inputs_field = Kaifile.optional("inputs", StringList)

	build_block = Kaifile.named_block({
		header: "build <artifact>",
		fields: [
			Kaifile.required_reference("environment", environment_block),
			inputs_field,
			Kaifile.required("run", StringList),
			Kaifile.required("output", String),
		],
		name_rules: [
			NonemptyText("artifact name must not be empty"),
			DisallowedPrefix({ message: "artifact name must not start with '.'", prefix: "." }),
			AllBytes({
				allowed: [AsciiUppercase, AsciiLowercase, AsciiDigit, ExactByte('.'), ExactByte('_'), ExactByte('-')],
				message: "artifact name may contain only ASCII letters, digits, '.', '_', and '-'",
			}),
		],
	})

	command_syntax = Plugin.command_syntax("build", [Plugin.required_argument("artifact")])
	command = Plugin.command_with_block({ syntax: command_syntax, block: build_block })
	switch_syntax = Plugin.command_syntax("aion-switch", [])
	switch_command = Plugin.command_only(switch_syntax)
	validate_syntax = Plugin.command_syntax("aion-validate", [Plugin.required_argument("machine")])
	validate_command = Plugin.command_only(validate_syntax)
	schema = { blocks: [build_block, environment_block], commands: [command, switch_command, validate_command] }

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
	backends = [backend]

	supported_targets : List(Plugin.SupportedBackendTarget)
	supported_targets = [
		{ arch: X64, os: LINUX, value: "x86_64-linux" },
		{ arch: AARCH64, os: LINUX, value: "aarch64-linux" },
		{ arch: X64, os: MACOS, value: "x86_64-darwin" },
		{ arch: AARCH64, os: MACOS, value: "aarch64-darwin" },
	]

	Source := { name : Str, url : Str }

	source_name_rules = [
		NonemptyText("source name must not be empty"),
		DisallowedPrefix({ message: "source name must not start with '.'", prefix: "." }),
		AllBytes({
			allowed: [AsciiUppercase, AsciiLowercase, AsciiDigit, ExactByte('.'), ExactByte('_'), ExactByte('-')],
			message: "source name may contain only ASCII letters, digits, '.', '_', and '-'",
		}),
	]

	source_url_rules = [
		NonemptyText("source URL must not be empty"),
		BytesInRanges({
			excluded: ['"', '$', '\\'],
			message: "source URL contains characters unsafe for Nix output",
			ranges: [{ max: '~', min: '!' }],
		}),
	]

	validate_sources = |sources, seen|
		match sources {
			[] => Ok({})
			[first, .. as rest] => {
				Plugin.implementation_validation(
					Plugin.validate_text(first.name, source_name_rules)
						.concat(Plugin.validate_text(first.url, source_url_rules)),
				)?
				if seen.contains(first.name) {
					Err({ byte_offset: None, message: "source '${first.name}' is declared more than once" })
				} else {
					AionBuildPlugin.validate_sources(rest, seen.append(first.name))
				}
			}
		}

	all_sources = |input| {
		sources = Plugin.blocks_of_kind(input, ["source"]).map_try(
			|entry| {
				source_name = match entry.header {
					["source", selected] | ["source", selected, _] => Ok(selected)
					_ => Err({ byte_offset: None, message: "source declaration requires a name" })
				}?
				url = Fields.get_string(entry.fields, "url") ? |_|
					{ byte_offset: None, message: "validated source '${source_name}' is missing 'url'" }
				Ok({ name: source_name, url })
			},
		)?
		AionBuildPlugin.validate_sources(sources, [])?
		Ok(sources)
	}

	validate_inputs = |inputs, sources, seen|
		match inputs {
			[] => Ok({})
			[first, .. as rest] => {
				Plugin.implementation_validation(Plugin.validate_text(first, source_name_rules))?
				if seen.contains(first) {
					Err({ byte_offset: None, message: "build input '${first}' is selected more than once" })
				} else if !sources.any(|source| source.name == first) {
					Err({ byte_offset: None, message: "build input '${first}' has no declared source" })
				} else {
					AionBuildPlugin.validate_inputs(rest, sources, seen.append(first))
				}
			}
		}

	plan : Plugin.CommandPlanningInput -> Try(Plugin.BackendCommandPlan, Plugin.BackendPlanningDiagnostic)
	plan = |input| {
		artifact_name = match input.command_arguments {
			[selected] => Ok(selected)
			_ => Err({ byte_offset: None, message: "build requires exactly one artifact name" })
		}?
		run = Fields.get_strings(input.command_fields, "run") ? |_|
			{ byte_offset: None, message: "validated build block is missing 'run'" }
		source = match run {
			["roc", "build", selected, ..] => Ok(selected)
			_ => Err({ byte_offset: None, message: "Aion builds must run 'roc build <source> ...'" })
		}?
		output = Fields.get_string(input.command_fields, "output") ? |_|
			{ byte_offset: None, message: "validated build block is missing 'output'" }
		Plugin.implementation_validation(
			Plugin.validate_text(
				output,
				[
					NonemptyText("build output must not be empty"),
					DisallowedPrefix({ message: "build output must be relative", prefix: "/" }),
					ForbiddenPathSegments({ message: "build output must not contain '.' or '..' path segments", segments: [".", ".."] }),
				],
			),
		)?
		inputs = Plugin.validated_strings(input.command_fields, AionBuildPlugin.inputs_field)?
		environment = Plugin.referenced_fields(input, "environment")?
		environment_packages = Fields.get_strings(environment, "packages") ? |_|
			{ byte_offset: None, message: "validated environment block is missing 'packages'" }
		overlays = Plugin.validated_strings(environment, AionBuildPlugin.overlays_field)?
		if overlays != ["github:thebrandonlucas/roc-overlay"] {
			return Err({ byte_offset: None, message: "Aion builds require only the roc-overlay environment overlay" })
		}
		sources = AionBuildPlugin.all_sources(input)?
		AionBuildPlugin.validate_inputs(inputs, sources, [])?
		system = Plugin.target_value(supported_targets, input.host.os, input.host.arch) ? |_|
			{ byte_offset: None, message: "unsupported build platform" }
		directory = Plugin.workspace_path(input.workspace_root, "builds/${artifact_name}")
		artifact_path = Plugin.workspace_path(input.workspace_root, "artifacts/builds/${artifact_name}")
		build_json = Json.to_str({ inputs, name: artifact_name, output, pkgs: environment_packages, run, source, system })
		Ok(
			Plugin.BackendCommandPlan.{
				artifacts: [
					{
						attributes: [
							{ key: "backend", value: backend.name },
							{ key: "nix.pkgs-flake", value: directory },
							{ key: "target.system", value: system },
						],
						kind: "kai.build/v1",
						name: artifact_name,
						path: artifact_path,
					},
				],
				prerequisite_commands: [],
				requested_packages: environment_packages,
				steps: [
					WriteFile({ contents: AionBuildPlugin.render_flake(sources, system), path: "${directory}/flake.nix" }),
					WriteFile({ contents: AionBuildPlugin.render_build_nix(input.workspace_root), path: "${directory}/build.nix" }),
					WriteFile({ contents: build_json, path: "${directory}/build.json" }),
				].concat(AionBuildPlugin.lock_steps(directory)).concat([
					WriteFile({ contents: "", path: Plugin.workspace_path(input.workspace_root, "artifacts/builds/.keep") }),
					RunProgram({ arguments: ["build", "--file", "${directory}/build.nix", "--out-link", artifact_path], program: "nix" }),
				]),
			},
		)
	}

	implementations = [
		Plugin.Implementation.{
			backend: backend.name,
			command: command_syntax.name,
			plan,
			validator: NoValidation,
		},
		Plugin.Implementation.{
			backend: backend.name,
			command: switch_syntax.name,
			plan: switch_plan,
			validator: NoValidation,
		},
		Plugin.Implementation.{
			backend: backend.name,
			command: validate_syntax.name,
			plan: validate_plan,
			validator: NoValidation,
		},
	]

	recipe_machine_name = |input| {
		names = Plugin.effective_blocks_of_kind(input, ["machine"]).map(
			|block|
				match block.header {
					["machine", found] | ["machine", found, _] => found
					_ => ""
				},
		)
		match names {
			[first] => Ok(first)
			_ => Err({ byte_offset: None, message: "Aion recipes require exactly one machine" })
		}
	}

	validate_plan = |input| {
		machine_name = AionBuildPlugin.recipe_machine_name(input)?
		expected = match input.command_arguments {
			[selected] => Ok(selected)
			_ => Err({ byte_offset: None, message: "aion-validate requires one machine name" })
		}?
		if machine_name != expected {
			return Err({ byte_offset: None, message: "Aion recipe machine '${machine_name}' must match directory slug '${expected}'" })
		}
		Ok(Plugin.BackendCommandPlan.{ artifacts: [], prerequisite_commands: [], requested_packages: [], steps: [] })
	}

	switch_plan = |input| {
		machine_name = AionBuildPlugin.recipe_machine_name(input)?
		directory = Plugin.workspace_path(input.workspace_root, "aion/local")
		Ok(
			Plugin.BackendCommandPlan.{
				artifacts: [],
				prerequisite_commands: [{ arguments: ["machine", backend.name, machine_name], description: "aion-switch: machine ${machine_name}" }],
				requested_packages: [],
				steps: [
					RunProgram({ arguments: ["-p", directory], program: "mkdir" }),
					RunProgram({ arguments: ["-rf", "${directory}/machine"], program: "rm" }),
					RunProgram({ arguments: ["-RH", "--preserve=mode", "--", Plugin.workspace_path(input.workspace_root, "machines/${machine_name}"), "${directory}/machine"], program: "cp" }),
					WriteFile({ contents: AionBuildPlugin.render_switch_flake(machine_name), path: "${directory}/flake.nix" }),
					WriteFile({ contents: AionBuildPlugin.render_digital_ocean_module({}), path: "${directory}/digital-ocean.nix" }),
				]
					.concat(AionBuildPlugin.wrapper_lock_steps(directory))
					.concat([
						Confirm("WARNING: This will replace the running Aion system with machine '${machine_name}'.\nContinue? [y/N]"),
						RunProgram({ arguments: ["switch", "--flake", "path:${directory}#${machine_name}", "--no-update-lock-file"], program: "nixos-rebuild" }),
					]),
			},
		)
	}

	lock_steps = |directory| [
		RunProgram({
			arguments: ["flake", "lock", "path:${directory}", "--reference-lock-file", "Kaifile.lock", "--output-lock-file", "Kaifile.lock"],
			program: "nix",
		}),
		RunProgram({
			arguments: ["flake", "lock", "path:${directory}", "--reference-lock-file", "Kaifile.lock", "--output-lock-file", "${directory}/flake.lock"],
			program: "nix",
		}),
	]

	wrapper_lock_steps = |directory| [
		RunProgram({
			arguments: ["flake", "lock", "path:${directory}", "--reference-lock-file", "Kaifile.lock", "--output-lock-file", "${directory}/flake.lock"],
			program: "nix",
		}),
	]

	render_switch_flake = |machine_name|
		Str.join_with(
			[
				"{",
				"  inputs.machine.url = \"path:./machine\";",
				"  outputs = { machine, ... }: {",
				"    nixosConfigurations.\"${machine_name}\" = machine.nixosConfigurations.\"${machine_name}\".extendModules {",
				"      modules = [ ./digital-ocean.nix ];",
				"    };",
				"  };",
				"}",
			],
			"\n",
		)

	render_digital_ocean_module = |_|
		\\{ lib, modulesPath, ... }:
		\\{
		\\  imports = [ (modulesPath + "/virtualisation/digital-ocean-config.nix") ];
		\\  boot.loader.grub.enable = lib.mkForce true;
		\\  fileSystems."/" = lib.mkForce { device = "/dev/disk/by-label/nixos"; fsType = "ext4"; autoResize = true; };
		\\  users.users.root.hashedPassword = "!";
		\\  virtualisation.digitalOcean = { setRootPassword = false; setSshKeys = true; };
		\\  services.openssh = { enable = true; settings = { KbdInteractiveAuthentication = false; PasswordAuthentication = false; PermitRootLogin = "prohibit-password"; }; };
		\\  networking.firewall.allowedTCPPorts = [ 22 ];
		\\  nix.settings.experimental-features = [ "nix-command" "flakes" ];
		\\}

	render_flake = |sources, system| {
		source_lines = sources.map(|source_input|
			"  inputs.\"kai-source-${source_input.name}\" = { url = \"${source_input.url}\"; flake = false; };")
		source_attrs = sources.map(|source_input|
			"\"${source_input.name}\" = inputs.\"kai-source-${source_input.name}\";")
		Str.join_with(
			[
				"{",
				"  inputs.nixpkgs.url = \"github:NixOS/nixpkgs/nixos-unstable\";",
				"  inputs.overlay0.url = \"github:thebrandonlucas/roc-overlay\";",
			].concat(source_lines).concat([
				"  outputs = inputs@{ nixpkgs, overlay0, ... }: let",
				"    system = \"${system}\";",
				"    pkgs = import nixpkgs { inherit system; overlays = [ overlay0.overlays.default ]; };",
				"  in {",
				"    legacyPackages.\"${system}\" = pkgs;",
				"    kaiSources = { ${Str.join_with(source_attrs, " ")} };",
				"  };",
				"}",
			]),
			"\n",
		)
	}

	render_build_nix = |workspace_root| {
		ignore_paths = if workspace_root == ".kai" ".git\\n.kai" else ".git\\n.kai\\n/${workspace_root}"
		Str.join_with(
			[
				"let",
				"  config = builtins.fromJSON (builtins.readFile ./build.json);",
				"  flake = builtins.getFlake (toString ./.);",
				"  pkgs = builtins.getAttr config.system flake.legacyPackages;",
				"  lib = pkgs.lib;",
				"  resolvePackage = name: lib.attrByPath (lib.splitString \".\" name) (throw (\"Kai build package '\" + name + \"' was not found\")) pkgs;",
				"  source = pkgs.nix-gitignore.gitignoreFilterRecursiveSource (_: _: true) \"${ignore_paths}\" ../../../.;",
				"  inputLinks = lib.concatMapStringsSep \"\\n\" (name: \"ln -s -- ${AionBuildPlugin.nix_interpolation("lib.escapeShellArg (toString (builtins.getAttr name flake.kaiSources))")} .kai/inputs/${AionBuildPlugin.nix_interpolation("lib.escapeShellArg name")}\") config.inputs;",
				"  bitcoinQrAssets = if builtins.elem \"bitcoin-qr\" config.inputs then toString flake.kaiSources.\"bitcoin-qr\" + \"/dist/bitcoin-qr\" else \"\";",
				"  platform = pkgs.fetchurl { url = \"${basic_cli_url}\"; hash = \"${basic_cli_hash}\"; };",
				"  rocHttp = pkgs.fetchurl { url = \"${roc_http_url}\"; hash = \"${roc_http_hash}\"; };",
				"  basicWebserver = pkgs.fetchurl { url = \"${basic_webserver_url}\"; hash = \"${basic_webserver_hash}\"; };",
				"in pkgs.runCommand (\"kai-build-\" + config.name) { nativeBuildInputs = map resolvePackage config.pkgs; } ''",
				"  cp -R ${AionBuildPlugin.nix_interpolation("source")}/. .",
				"  chmod -R u+w .",
				"  mkdir -p .kai/inputs",
				"  ${AionBuildPlugin.nix_interpolation("inputLinks")}",
				"  cp ${AionBuildPlugin.nix_interpolation("platform")} ${basic_cli_name}.tar.zst",
				"  cp ${AionBuildPlugin.nix_interpolation("rocHttp")} ${roc_http_name}.tar.zst",
				"  cp ${AionBuildPlugin.nix_interpolation("basicWebserver")} ${basic_webserver_name}.tar.zst",
				"  roc unbundle ${basic_cli_name}.tar.zst",
				"  roc unbundle ${roc_http_name}.tar.zst",
				"  roc unbundle ${basic_webserver_name}.tar.zst",
				"  substituteInPlace ${basic_cli_name}/main.roc --replace-fail '${roc_http_url}' \"$PWD/${roc_http_name}/main.roc\"",
				"  substituteInPlace ${basic_webserver_name}/main.roc --replace-fail '${roc_http_url}' \"$PWD/${roc_http_name}/main.roc\"",
				"  substituteInPlace ${AionBuildPlugin.nix_interpolation("lib.escapeShellArg config.source")} --replace-quiet '${basic_cli_url}' \"$PWD/${basic_cli_name}/main.roc\"",
				"  substituteInPlace ${AionBuildPlugin.nix_interpolation("lib.escapeShellArg config.source")} --replace-quiet '${basic_webserver_url}' \"$PWD/${basic_webserver_name}/main.roc\"",
				"  substituteInPlace ${AionBuildPlugin.nix_interpolation("lib.escapeShellArg config.source")} --replace-quiet '${roc_http_url}' \"$PWD/${roc_http_name}/main.roc\"",
				"  substituteInPlace ${AionBuildPlugin.nix_interpolation("lib.escapeShellArg config.source")} --replace-quiet 'BITCOIN_QR_ASSETS' ${AionBuildPlugin.nix_interpolation("lib.escapeShellArg bitcoinQrAssets")}",
				"  artifact=${AionBuildPlugin.nix_interpolation("lib.escapeShellArg config.output")}",
				"  rm -rf -- \"$artifact\"",
				"  ${AionBuildPlugin.nix_interpolation("lib.escapeShellArgs config.run")}",
				"  if [ ! -e \"$artifact\" ]; then echo \"Kai build output does not exist: $artifact\" >&2; exit 1; fi",
				"  if [ -d \"$artifact\" ]; then cp -R -- \"$artifact\" \"$out\"; else cp -- \"$artifact\" \"$out\"; fi",
				"''",
			],
			"\n",
		)
	}

	nix_interpolation = |expression| Str.join_with(["$", "{", expression, "}"], "")
}
