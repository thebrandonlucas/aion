app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.0/F1JVZPYfWP71s8vk6tHcV1Qx1Ef6CZkwswGoCn8VHZmL.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.OsStr
import pf.Path
import pf.Stdin
import pf.Stdout

model_key_path = ".config/aion/model-key"

models_path = ".pi/agent/models.json"

settings_path = ".pi/agent/settings.json"

ssh_key_path = "/home/aion/.ssh/authorized_keys"

metadata_path = "/run/do-metadata/v1.json"

write_private! = |directory, path, bytes| {
	Path.create_all!(directory)?
	temporary = Path.utf8("${Path.display(path)}.new")
	Path.write_bytes!(temporary, bytes)?
	Cmd.new_str("chmod").args_str(["0600", Path.display(temporary)]).exec_cmd!()?
	Path.rename!(temporary, path)
}

install_model_key! = |home, bytes| {
	directory = Path.join(home, ".config/aion")
	write_private!(directory, Path.join(home, model_key_path), bytes)?
	Stdout.line!("model key configured")
}

set_model_key! = || {
	key = Str.from_utf8(Stdin.read_to_end!()?) ? |_| InvalidModelKey
	trimmed = key.trim()
	if trimmed.is_empty() {
		Err(InvalidModelKey)
	} else {
		home = Path.utf8(Env.var_str!(OsStr.utf8("HOME"))?)
		install_model_key!(home, trimmed.to_utf8())
	}
}

# Adopt a key staged by scp at ~/.config/aion/model-key.new. write_private!
# stages through that same ".new" path, so the atomic rename also deletes it.
adopt_model_key! = || {
	home = Path.utf8(Env.var_str!(OsStr.utf8("HOME"))?)
	incoming = Path.join(home, "${model_key_path}.new")
	key = Str.from_utf8(Path.read_bytes!(incoming)?) ? |_| InvalidModelKey
	trimmed = key.trim()
	if trimmed.is_empty() {
		Path.delete!(incoming) ?? {}
		Err(InvalidModelKey)
	} else {
		install_model_key!(home, trimmed.to_utf8())
	}
}

adopt_agent_config! = || {
	home = Path.utf8(Env.var_str!(OsStr.utf8("HOME"))?)
	key = Str.from_utf8(Path.read_bytes!(Path.join(home, "${model_key_path}.new"))?) ? |_| InvalidModelKey
	models = Path.read_bytes!(Path.join(home, "${models_path}.new"))?
	settings = Path.read_bytes!(Path.join(home, "${settings_path}.new"))?
	trimmed = key.trim()
	if trimmed.is_empty() or models.is_empty() or settings.is_empty() {
		Err(InvalidAgentConfig)
	} else {
		write_private!(Path.join(home, ".pi/agent"), Path.join(home, models_path), models)?
		write_private!(Path.join(home, ".pi/agent"), Path.join(home, settings_path), settings)?
		install_model_key!(home, trimmed.to_utf8())
	}
}

install_ssh_key! = || {
	directory = Path.utf8("/home/aion/.ssh")
	metadata = Path.read_utf8!(Path.utf8(metadata_path))?
	parsed : Try({ public_keys : List(Str) }, _)
	parsed = Json.parse(metadata)
	keys = match parsed {
		Ok(value) => value.public_keys
		Err(_) => return Err(InvalidMetadata)
	}
	key = match keys {
		[only] if !only.trim().is_empty() => only.trim()
		_ => return Err(ExpectedOneSshKey)
	}
	path = Path.utf8(ssh_key_path)
	write_private!(directory, path, "${key}\n".to_utf8())?
	Cmd.new_str("chmod").args_str(["0700", Path.display(directory)]).exec_cmd!()?
	Cmd.new_str("chown").args_str(["aion:users", Path.display(directory), Path.display(path)]).exec_cmd!()?
	Stdout.line!("SSH key installed")
}

main! = |args| {
	commands = args.drop_first(1).map(OsStr.display)
	match commands {
		["set-model-key"] => set_model_key!()
		["adopt-model-key"] => adopt_model_key!()
		["adopt-agent-config"] => adopt_agent_config!()
		["install-ssh-key"] => install_ssh_key!()
		_ => Err(InvalidArguments("usage: aion-init set-model-key|adopt-model-key|adopt-agent-config|install-ssh-key"))
	}
}
