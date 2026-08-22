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

ssh_key_path = "/home/aion/.ssh/authorized_keys"

metadata_path = "/run/do-metadata/v1.json"

write_private! = |directory, path, bytes| {
	Path.create_all!(directory)?
	temporary = Path.utf8("${Path.display(path)}.new")
	Path.write_bytes!(temporary, bytes)?
	Cmd.new_str("chmod").args_str(["0600", Path.display(temporary)]).exec_cmd!()?
	Path.rename!(temporary, path)
}

set_model_key! = || {
	key = Str.from_utf8(Stdin.read_to_end!()?) ? |_| InvalidModelKey
	trimmed = key.trim()
	if trimmed.is_empty() {
		Err(InvalidModelKey)
	} else {
		home = Path.utf8(Env.var_str!(OsStr.utf8("HOME"))?)
		directory = Path.join(home, ".config/aion")
		write_private!(directory, Path.join(home, model_key_path), trimmed.to_utf8())?
		Stdout.line!("model key configured")
	}
}

install_ssh_key! = || {
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
	write_private!(Path.utf8("/home/aion/.ssh"), Path.utf8(ssh_key_path), "${key}\n".to_utf8())?
	Stdout.line!("SSH key installed")
}

main! = |args| {
	commands = args.drop_first(1).map(OsStr.display)
	match commands {
		["set-model-key"] => set_model_key!()
		["install-ssh-key"] => install_ssh_key!()
		_ => Err(InvalidArguments("usage: aion-init set-model-key|install-ssh-key"))
	}
}
