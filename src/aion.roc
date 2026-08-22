app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.0/F1JVZPYfWP71s8vk6tHcV1Qx1Ef6CZkwswGoCn8VHZmL.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.OsStr
import pf.Path
import pf.Sleep
import pf.Stdout
import pf.Utc

import AionState
import DigitalOcean
import DigitalOceanApi

usage = Str.join_with(
	[
		"Usage: aion <command>",
		"  aion image import <https-url>",
		"  aion create <name>",
		"  aion <name> shell [pi]",
		"  aion destroy <name>",
	],
	"\n",
)

valid_name = |name| {
	bytes = name.to_utf8()
	!List.is_empty(bytes)
		and List.all(bytes, |b| (b >= 'a' and b <= 'z') or (b >= '0' and b <= '9') or b == '-')
}

require_env! = |name, hint|
	match Env.var_str!(OsStr.utf8(name)) {
		Ok(value) => Ok(value)
		Err(_) => Err(MissingEnv("${name} is not set; ${hint}"))
	}

token! = || require_env!("DIGITALOCEAN_TOKEN", "export a DigitalOcean API token")

poll_image! = |auth, id, tries| {
	image = DigitalOceanApi.get_image!(id, auth)?
	if image.status == "available" {
		Ok(image)
	} else if tries == 0 {
		Err(ImagePollTimeout)
	} else if image.status == "error" {
		Err(ImageImportFailed)
	} else {
		Sleep.seconds!(15)
		poll_image!(auth, id, tries - 1)
	}
}

image_import! = |url| {
	if AionState.has_image!()? {
		Stdout.line!("an image is already imported; remove .aion/image.json to re-import")
	} else {
		auth = token!()?
		image = DigitalOceanApi.import_image!(url, auth)?
		ready = poll_image!(auth, image.id, 120)?
		AionState.save_image!({ id: ready.id, name: ready.name })?
		Stdout.line!("image '${ready.name}' available (id ${U64.to_str(ready.id)})")
	}
}

poll_droplet! = |auth, id, tries| {
	droplet = DigitalOceanApi.get_droplet!(id, auth)?
	has_ip = match DigitalOcean.public_ipv4(droplet) {
		Ok(_) => Bool.True
		Err(_) => Bool.False
	}
	if droplet.status == "active" and has_ip {
		Ok(droplet)
	} else if tries == 0 {
		Err(DropletPollTimeout)
	} else {
		Sleep.seconds!(15)
		poll_droplet!(auth, id, tries - 1)
	}
}

# Cloud-init/metadata key install can lag droplet activation; retry ssh for a
# bounded window before giving up.
wait_for_ssh! = |ip, tries| {
	exit_code = Cmd.new_str("ssh")
		.args_str([
			"-o",
			"BatchMode=yes",
			"-o",
			"ConnectTimeout=10",
			"-o",
			"StrictHostKeyChecking=accept-new",
			"aion@${ip}",
			"mkdir -p ~/.config/aion",
		])
		.exec_exit_code!()?
	if exit_code == 0 {
		Ok({})
	} else if tries == 0 {
		Err(SshNotReady)
	} else {
		Sleep.seconds!(5)
		wait_for_ssh!(ip, tries - 1)
	}
}

# The key travels only inside a mode-0600 file over scp/ssh; never in argv,
# API payloads, logs, or local state. The temp file is deleted on all paths.
enroll_model_key! = |ip, model_key| {
	temporary = Path.utf8(".aion/model-key.${U128.to_str(Utc.now!())}")
	Path.write_bytes!(temporary, model_key.trim().to_utf8())?
	result = enroll_model_key_stage!(ip, temporary)
	delete = Path.delete!(temporary)
	match (result, delete) {
		(Err(error), _) => Err(error)
		(Ok({}), Err(error)) => Err(error)
		(Ok({}), Ok({})) => Ok({})
	}
}

enroll_model_key_stage! = |ip, temporary| {
	Cmd.new_str("chmod").args_str(["0600", Path.display(temporary)]).exec_cmd!()?
	wait_for_ssh!(ip, 30)?
	Cmd.exec!(
		OsStr.utf8("scp"),
		[
			OsStr.utf8("-p"),
			OsStr.utf8("-o"),
			OsStr.utf8("StrictHostKeyChecking=accept-new"),
			Path.to_os_str(temporary),
			OsStr.utf8("aion@${ip}:~/.config/aion/model-key.new"),
		],
	)?
	Cmd.exec!(
		OsStr.utf8("ssh"),
		[
			OsStr.utf8("-o"),
			OsStr.utf8("StrictHostKeyChecking=accept-new"),
			OsStr.utf8("aion@${ip}"),
			OsStr.utf8("aion-init"),
			OsStr.utf8("adopt-model-key"),
		],
	)?
	Stdout.line!("model key enrolled")
}

create! = |name| {
	if !valid_name(name) {
		Err(InvalidMachineName("name may contain only lowercase ASCII letters, digits, and '-'"))
	} else {
		auth = token!()?
		model_key = require_env!("AION_MODEL_API_KEY", "export a short-lived model API key")?
		if model_key.trim().is_empty() {
			Err(EmptyModelKey)
		} else {
			image = AionState.read_image!()?
			home = require_env!("HOME", "needed to locate ~/.ssh/id_ed25519.pub")?
			public_key = Path.read_utf8!(Path.join(Path.utf8(home), ".ssh/id_ed25519.pub"))?.trim()
			key = DigitalOceanApi.register_ssh_key!("aion-${name}", public_key, auth)?
			ssh_key_id = match key {
				RegisteredKey(created) => created.id
				ReusedKey(existing) => existing.id
			}
			droplet = DigitalOceanApi.create_droplet!(name, image.id, ssh_key_id, auth)?
			active = poll_droplet!(auth, droplet.id, 120)?
			ip = match DigitalOcean.public_ipv4(active) {
				Ok(found) => found
				Err(_) => return Err(DropletPollTimeout)
			}
			AionState.save_machine!({ id: active.id, ip, name, ssh_key_id })?
			Stdout.line!("machine '${name}' active at ${ip}")?
			enroll_model_key!(ip, model_key)
		}
	}
}

shell! = |name, run_pi| {
	machine = AionState.read_machine!(name)?
	base = [
		OsStr.utf8("-o"),
		OsStr.utf8("StrictHostKeyChecking=accept-new"),
		OsStr.utf8("aion@${machine.ip}"),
	]
	arguments =
		if run_pi {
			[OsStr.utf8("-t")].concat(base).concat([
				OsStr.utf8("pi"),
				OsStr.utf8("--provider"),
				OsStr.utf8("ppq"),
				OsStr.utf8("--model"),
				OsStr.utf8("openai/gpt-5.1-codex"),
			])
		} else {
			base
		}
	Cmd.exec!(OsStr.utf8("ssh"), arguments)
}

destroy! = |name| {
	auth = token!()?
	machine = AionState.read_machine!(name)?
	DigitalOceanApi.delete_droplet!(machine.id, auth)?
	AionState.delete_machine!(name)?
	image_note = match AionState.read_image!() {
		Ok(image) => "image id ${U64.to_str(image.id)}"
		Err(_) => "image state not found"
	}
	Stdout.line!("droplet ${U64.to_str(machine.id)} deleted; local state removed")?
	Stdout.line!("retained for manual cleanup: ${image_note}, ssh key id ${U64.to_str(machine.ssh_key_id)} (aion-${name})")
}

main! = |args|
	match args.drop_first(1).map(OsStr.display) {
		["image", "import", url] => image_import!(url)
		["create", name] => create!(name)
		[name, "shell"] => shell!(name, Bool.False)
		[name, "shell", "pi"] => shell!(name, Bool.True)
		["destroy", name] => destroy!(name)
		_ => Stdout.line!(usage)
	}
