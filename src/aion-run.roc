app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.0/F1JVZPYfWP71s8vk6tHcV1Qx1Ef6CZkwswGoCn8VHZmL.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.OsStr
import pf.Path
import pf.Stdout

Entry : { name : Str, value : Str }

usage = Str.join_with(
	[
		"Usage: aion-run <command>",
		"  aion-run shell",
		"  aion-run import-image",
		"  aion-run image-status",
		"  aion-run create-demo",
		"  aion-run create-project <name> <project> <machine>",
		"  aion-run deploy-project <name> <project> <artifact>",
		"  aion-run shell-demo",
		"  aion-run shell-pi-demo",
		"  aion-run destroy-demo",
		"  aion-run delete-image",
		"  aion-run payment-preflight",
		"  aion-run payment-server",
	],
	"\n",
)

unquote = |value| {
	bytes = value.to_utf8()
	length = bytes.len()
	if length >= 2
		and ((bytes.get(0) ?? 0) == 34 and (bytes.get(length - 1) ?? 0) == 34
			or (bytes.get(0) ?? 0) == 39 and (bytes.get(length - 1) ?? 0) == 39) {
		Str.from_utf8_lossy(bytes.drop_first(1).drop_last(1))
	} else {
		value
	}
}

parse_lines = |lines|
	match lines {
		[] => Ok([])
		[first, .. as rest] => {
			line = first.trim()
			remaining = parse_lines(rest)?
			if line.is_empty() or line.starts_with("#") {
				Ok(remaining)
			} else {
				parts = line.split_on("=")
				match parts {
					[name, .. as value_parts] if !name.trim().is_empty() and !value_parts.is_empty() =>
						Ok([{ name: name.trim(), value: unquote(Str.join_with(value_parts, "=").trim()) }].concat(remaining))
					_ => Err(InvalidDotEnvLine("expected KEY=value without shell commands"))
				}
			}
		}
	}

load_dotenv! = || parse_lines(Path.read_utf8!(Path.utf8(".env"))?.split_on("\n"))

require_value = |entries, name|
	match entries.keep_if(|entry| entry.name == name) {
		[{ value, .. }] if !value.is_empty() => Ok(value)
		[] => Err(MissingDotEnvValue(name))
		_ => Err(DuplicateDotEnvValue(name))
	}

unset_args = |names|
	match names {
		[] => []
		[first, .. as rest] => ["-u", first].concat(unset_args(rest))
	}

run! = |program, arguments, environment, unset| {
	exit_code = Cmd.new_str("env")
		.args_str(unset_args(unset).concat([program]).concat(arguments))
		.envs_str(environment)
		.exec_exit_code!() ? |_| CommandLaunchFailed(program)
	if exit_code == 0 Ok({}) else Err(CommandFailed({ program, exit_code }))
}

shell! = |entries| {
	root = Path.display(Env.cwd!()?)
	path = Env.var_str!(OsStr.utf8("PATH"))?
	shell = Env.var_str!(OsStr.utf8("SHELL")) ?? "bash"
	environment = entries.map(|entry| (entry.name, entry.value)).append(("PATH", "${root}/.kai/artifacts:${path}"))
	run!(shell, [], environment, [])
}

import_image! = |entries|
	run!(
		".kai/artifacts/aion",
		["image", "import-local", ".kai/artifacts/images/agent/result/agent.qcow2"],
		[
			("AWS_ACCESS_KEY_ID", require_value(entries, "AWS_ACCESS_KEY_ID")?),
			("AWS_SECRET_ACCESS_KEY", require_value(entries, "AWS_SECRET_ACCESS_KEY")?),
			("DIGITALOCEAN_SPACE_NAME", require_value(entries, "DIGITALOCEAN_SPACE_NAME")?),
			("DIGITALOCEAN_SPACE_REGION", require_value(entries, "DIGITALOCEAN_SPACE_REGION")?),
			("DIGITALOCEAN_TOKEN", require_value(entries, "DIGITALOCEAN_TOKEN")?),
		],
		["AWS_SESSION_TOKEN", "AION_MODEL_API_KEY", "EVERPAID_API_KEY"],
	)

create_project! = |entries, name, project, machine|
	run!(
		".kai/artifacts/aion",
		["create", name, "--project", project, "--machine", machine],
		[
			("AWS_ACCESS_KEY_ID", require_value(entries, "AWS_ACCESS_KEY_ID")?),
			("AWS_SECRET_ACCESS_KEY", require_value(entries, "AWS_SECRET_ACCESS_KEY")?),
			("DIGITALOCEAN_SPACE_NAME", require_value(entries, "DIGITALOCEAN_SPACE_NAME")?),
			("DIGITALOCEAN_SPACE_REGION", require_value(entries, "DIGITALOCEAN_SPACE_REGION")?),
			("DIGITALOCEAN_TOKEN", require_value(entries, "DIGITALOCEAN_TOKEN")?),
		],
		["AWS_SESSION_TOKEN", "AION_MODEL_API_KEY", "EVERPAID_API_KEY"],
	)

image_status! = |entries|
	run!(
		".kai/artifacts/aion",
		["image", "status"],
		[("DIGITALOCEAN_TOKEN", require_value(entries, "DIGITALOCEAN_TOKEN")?)],
		[
			"AWS_ACCESS_KEY_ID",
			"AWS_SECRET_ACCESS_KEY",
			"AWS_SESSION_TOKEN",
			"AION_MODEL_API_KEY",
			"EVERPAID_API_KEY",
		],
	)

digitalocean_operation! = |entries, arguments, include_model_key| {
	environment = if include_model_key {
		[
			("AION_MODEL_API_KEY", require_value(entries, "AION_MODEL_API_KEY")?),
			("DIGITALOCEAN_TOKEN", require_value(entries, "DIGITALOCEAN_TOKEN")?),
		]
	} else {
		[("DIGITALOCEAN_TOKEN", require_value(entries, "DIGITALOCEAN_TOKEN")?)]
	}
	run!(
		".kai/artifacts/aion",
		arguments,
		environment,
		[
			"AWS_ACCESS_KEY_ID",
			"AWS_SECRET_ACCESS_KEY",
			"AWS_SESSION_TOKEN",
			"DIGITALOCEAN_SPACE_NAME",
			"DIGITALOCEAN_SPACE_REGION",
			"EVERPAID_API_KEY",
		],
	)
}

deploy_project! = |name, project, artifact|
	run!(
		".kai/artifacts/aion",
		["deploy", name, artifact, "--project", project],
		[],
		[
			"AION_MODEL_API_KEY",
			"AWS_ACCESS_KEY_ID",
			"AWS_SECRET_ACCESS_KEY",
			"AWS_SESSION_TOKEN",
			"DIGITALOCEAN_TOKEN",
			"EVERPAID_API_KEY",
		],
	)

shell_demo! = |run_pi|
	run!(
		".kai/artifacts/aion",
		if run_pi ["demo", "shell", "pi"] else ["demo", "shell"],
		[],
		[
			"AION_MODEL_API_KEY",
			"AWS_ACCESS_KEY_ID",
			"AWS_SECRET_ACCESS_KEY",
			"AWS_SESSION_TOKEN",
			"DIGITALOCEAN_TOKEN",
			"EVERPAID_API_KEY",
		],
	)

payment_server! = |entries|
	run!(
		".kai/artifacts/aion-web",
		[],
		[
			("AION_MODEL_API_KEY", require_value(entries, "AION_MODEL_API_KEY")?),
			("DIGITALOCEAN_TOKEN", require_value(entries, "DIGITALOCEAN_TOKEN")?),
			("EVERPAID_API_KEY", require_value(entries, "EVERPAID_API_KEY")?),
		],
		[
			"AWS_ACCESS_KEY_ID",
			"AWS_SECRET_ACCESS_KEY",
			"AWS_SESSION_TOKEN",
			"DIGITALOCEAN_SPACE_NAME",
			"DIGITALOCEAN_SPACE_REGION",
		],
	)

main! = |args|
	match args.drop_first(1).map(OsStr.display) {
		["shell"] => shell!(load_dotenv!()?)
		["import-image"] => import_image!(load_dotenv!()?)
		["image-status"] => image_status!(load_dotenv!()?)
		["create-demo"] => digitalocean_operation!(load_dotenv!()?, ["create", "demo"], Bool.True)
		["create-project", name, project, machine] => create_project!(load_dotenv!()?, name, project, machine)
		["deploy-project", name, project, artifact] => deploy_project!(name, project, artifact)
		["shell-demo"] => shell_demo!(Bool.False)
		["shell-pi-demo"] => shell_demo!(Bool.True)
		["destroy-demo"] => digitalocean_operation!(load_dotenv!()?, ["destroy", "demo"], Bool.False)
		["delete-image"] => digitalocean_operation!(load_dotenv!()?, ["image", "delete"], Bool.False)
		["payment-preflight"] => digitalocean_operation!(load_dotenv!()?, ["payment-preflight", "demo"], Bool.True)
		["payment-server"] => payment_server!(load_dotenv!()?)
		_ => Stdout.line!(usage)
	}
