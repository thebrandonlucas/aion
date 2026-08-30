app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.0/F1JVZPYfWP71s8vk6tHcV1Qx1Ef6CZkwswGoCn8VHZmL.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.OsStr
import pf.Path
import pf.Random
import pf.Sleep
import pf.Stderr
import pf.Stdin
import pf.Stdout

import AionState
import Ansi
import DigitalOcean
import DigitalOceanApi
import Everpaid
import EverpaidApi

usage = Str.join_with(
	[
		"Aion - ad-hoc agent machines",
		"",
		"Usage: aion <command>",
		"",
		"Commands:",
		"  status      Overview of local Aion state",
		"  resources   Inventory DigitalOcean resources",
		"  machines    List saved machines",
		"  machine     Inspect, connect to, or destroy one machine",
		"  images      Manage the shared machine image",
		"  products    List machine products",
		"  create      Create or recover a machine",
		"  deploy      Deploy an artifact to a machine",
		"",
		"Run 'aion help <command>' for details.",
	],
	"\n",
)

help = |topic|
	match topic {
		"" => usage
		"status" => "Usage: aion status\n\nShow the saved image, machines, pending operations, and payment reservation without querying a provider."
		"resources" => "Usage: aion resources\n\nList Aion-tagged DigitalOcean images, Droplets, and SSH keys with local tracking and billing labels."
		"machines" => "Usage: aion machines\n\nList machines recorded in local Aion state. Use 'aion machine <name> status' to check one against DigitalOcean and SSH."
		"machine" => "Usage: aion machine <name> <command>\n\nCommands:\n  status       Compare local and provider state and probe SSH\n  shell [pi]   Connect over SSH, optionally starting Pi\n  destroy      Delete the Droplet and local machine state"
		"images" => "Usage: aion images <command>\n\nCommands:\n  status                 Show provider import status\n  import <https-url>     Import an HTTPS image\n  import-local <path>    Upload and import a local .qcow2 image\n  reconcile              Recover an available pending import\n  delete                 Delete the imported image"
		"products" => "Usage: aion products\n\nList available machine products and prices."
		"create" => "Usage:\n  aion create <name>\n  aion create <name> <product>\n  aion create <name> --project <directory> --machine <machine>\n  aion recover <name> <droplet-id>"
		"deploy" => "Usage: aion deploy <machine> <artifact> [--project <directory>]"
		_ => usage
	}

help_topic = |topic|
	match topic {
		"image" => "images"
		"recover" => "create"
		_ => topic
	}

is_help_topic = |topic|
	List.any(["", "status", "resources", "machines", "machine", "images", "products", "create", "deploy"], |known| topic == known)

print_help! = |topic| {
	selected = help_topic(topic)
	if is_help_topic(selected) Stdout.line!(help(selected)) else Err(UnknownCommand(topic))
}

is_help_flag = |argument| argument == "-h" or argument == "--help"

is_name_alphanumeric = |byte|
	(byte >= 'a' and byte <= 'z') or (byte >= '0' and byte <= '9')

valid_name = |name| {
	bytes = name.to_utf8()
	length = bytes.len()
	length > 0
		and length <= 63
			and is_name_alphanumeric(bytes.get(0) ?? 0)
				and is_name_alphanumeric(bytes.get(length - 1) ?? 0)
					and List.all(bytes, |byte| is_name_alphanumeric(byte) or byte == '-')
}

is_artifact_byte = |byte|
	is_name_alphanumeric(byte)
		or (byte >= 'A' and byte <= 'Z')
			or byte == '.'
				or byte == '_'
					or byte == '-'

valid_artifact = |name|
	!name.is_empty() and !name.starts_with(".") and List.all(name.to_utf8(), is_artifact_byte)

operation_tag! = |kind|
	Ok("aion-${kind}-${U64.to_str(Random.seed_u64!()?)}-${U64.to_str(Random.seed_u64!()?)}")

operation_status = |operation_tag, stage|
	"Operation tag ${operation_tag}\n${stage}\n"

resource_ids = |resources|
	Str.join_with(resources.map(|resource| U64.to_str(resource.id)), ", ")

operation_tag_from = |droplet|
	match droplet.tags.keep_if(|tag| tag.starts_with("aion-droplet-")) {
		[tag] => Ok(tag)
		[] => Err(DropletOperationTagMissing)
		_ => Err(MultipleDropletOperationTags)
	}

print_existing_droplets! = |droplets|
	match droplets {
		[] => Ok({})
		[first, .. as rest] => {
			addresses = Str.join_with(DigitalOcean.public_ipv4s(first), ", ")
			ip = if addresses.is_empty() "no public IP" else addresses
			Stderr.line!("existing Aion Droplet: ${first.name}, id ${U64.to_str(first.id)}, status ${first.status}, IP ${ip}")?
			Stderr.line!("  recover it: aion recover ${first.name} ${U64.to_str(first.id)}")?
			print_existing_droplets!(rest)
		}
	}

require_env! = |name, hint|
	match Env.var_str!(OsStr.utf8(name)) {
		Ok(value) => Ok(value)
		Err(_) => Err(MissingEnv("${name} is not set; ${hint}"))
	}

token! = || require_env!("DIGITALOCEAN_TOKEN", "export a DigitalOcean API token")

require_nonempty_env! = |name, hint| {
	value = require_env!(name, hint)?
	if value.trim().is_empty() {
		Err(MissingEnv("${name} is empty; ${hint}"))
	} else {
		Ok(value)
	}
}

confirm_operation! = |warning, phrase| {
	Stdout.line!(warning)?
	Stdout.write!("Type '${phrase}' to continue: ")?
	if Stdin.line!()?.trim() == phrase {
		Ok({})
	} else {
		Err(BillingNotConfirmed)
	}
}

reconcile_images! = |auth, operation_tag, attempts_left| {
	match DigitalOceanApi.list_private_images_by_tag!(operation_tag, auth) {
		Ok(images) => {
			if !List.is_empty(images) or attempts_left == 1 {
				Ok(images)
			} else {
				Sleep.seconds!(5)
				reconcile_images!(auth, operation_tag, attempts_left - 1)
			}
		}
		Err(error) => {
			if attempts_left == 1 {
				Err(error)
			} else {
				Sleep.seconds!(5)
				reconcile_images!(auth, operation_tag, attempts_left - 1)
			}
		}
	}
}

resolve_image_post! = |url, auth, operation_tag, status_for| {
	match DigitalOceanApi.import_image_once!(url, operation_tag, auth) {
		PostAccepted(image) => Ok(ImagePostAccepted(image))
		PostRejected(error) => {
			AionState.record_import_status!(status_for("Image import POST was definitively rejected")) ?? {}
			Ok(ImagePostRejected(error))
		}
		PostUncertain(error) => {
			AionState.record_import_status!(status_for("Import POST outcome uncertain; reconciling by operation tag at most 6 times")) ?? {}
			_ = Stderr.line!("image import POST was not retried; reconciling operation tag ${operation_tag}") ?? {}
			images = match reconcile_images!(auth, operation_tag, 6) {
				Ok(found) => found
				Err(reconcile_error) => {
					AionState.record_import_status!(status_for("Import reconciliation failed; manually list private images with this operation tag")) ?? {}
					_ = Stderr.line!("ERROR: image outcome remains uncertain; operation tag ${operation_tag} retained under .aion/image.pending/") ?? {}
					return Ok(ImagePostUnresolved(reconcile_error))
				}
			}
			match images {
				[] => {
					AionState.record_import_status!(status_for("No image found within the reconciliation bound; manually list private images with this operation tag")) ?? {}
					_ = Stderr.line!("ERROR: image outcome remains uncertain; operation tag ${operation_tag} retained under .aion/image.pending/") ?? {}
					Ok(ImagePostUnresolved(error))
				}
				[image] => {
					AionState.record_imported!(image.id, status_for("Reconciled image ID ${U64.to_str(image.id)} after uncertain POST"))?
					_ = Stdout.line!("reconciled image import by operation tag ${operation_tag} (id ${U64.to_str(image.id)})") ?? {}
					Ok(ImagePostAccepted(image))
				}
				many => {
					ids = resource_ids(many)
					AionState.record_import_status!(status_for("Multiple reconciled image IDs: ${ids}; manual recovery required")) ?? {}
					_ = Stderr.line!("ERROR: multiple images found for operation tag ${operation_tag}: ${ids}; pending state retained") ?? {}
					Ok(ImagePostUnresolved(MultipleImagesForOperationTag))
				}
			}
		}
	}
}

poll_image! = |auth, id, attempts_left| {
	if attempts_left == 0 {
		Err(ImagePollTimeout)
	} else {
		match DigitalOceanApi.get_image!(id, auth) {
			Err(error) => {
				if attempts_left == 1 {
					Err(error)
				} else {
					Sleep.seconds!(15)
					poll_image!(auth, id, attempts_left - 1)
				}
			}
			Ok(image) => {
				if image.status == "available" {
					Ok(image)
				} else if image.status == "error" {
					Err(ImageImportFailed)
				} else if attempts_left == 1 {
					Err(ImagePollTimeout)
				} else {
					Sleep.seconds!(15)
					poll_image!(auth, id, attempts_left - 1)
				}
			}
		}
	}
}

image_import! = |url| {
	if AionState.has_image!()? {
		Stdout.line!("image state or a pending import already exists under .aion/; inspect it before re-importing")
	} else if !url.starts_with("https://") {
		Err(ImageUrlMustUseHttps)
	} else {
		confirm_operation!("This imports a custom image into nyc3 and may incur image-storage charges.", "import image")?
		auth = token!()?
		operation_tag = operation_tag!("image")?
		status_for = |stage| operation_status(operation_tag, stage)
		AionState.begin_image_import!(operation_tag, status_for("URL import POST not yet completed"))?
		Stdout.line!("image import operation tag ${operation_tag}; pending state is under .aion/image.pending/")?
		outcome = resolve_image_post!(url, auth, operation_tag, status_for)?
		image = match outcome {
			ImagePostAccepted(found) => found
			ImagePostRejected(error) => return Err(error)
			ImagePostUnresolved(error) => return Err(error)
		}
		AionState.record_imported!(image.id, status_for("Image ID ${U64.to_str(image.id)}; polling import"))?
		_ = Stdout.line!("image import accepted (id ${U64.to_str(image.id)}); polling at most 60 times") ?? {}
		ready = poll_image!(auth, image.id, 60)?
		AionState.save_image!({ id: ready.id, name: ready.name, operation_tag })?
		AionState.clear_image_import!()?
		_ = Stdout.line!("image '${ready.name}' available (id ${U64.to_str(ready.id)})") ?? {}
		Ok({})
	}
}

valid_space_name = |name|
	valid_name(name) and !name.starts_with("-") and !name.ends_with("-")

spaces_config! = || {
	space = require_nonempty_env!("DIGITALOCEAN_SPACE_NAME", "export the private Space name")?
	region = require_nonempty_env!("DIGITALOCEAN_SPACE_REGION", "export nyc3")?
	_ = require_nonempty_env!("AWS_ACCESS_KEY_ID", "export a Space-scoped access key")?
	_ = require_nonempty_env!("AWS_SECRET_ACCESS_KEY", "export its secret")?
	if region != "nyc3" {
		Err(UnsupportedSpaceRegion("only nyc3 is compatible with this Aion image"))
	} else if !valid_space_name(space) {
		Err(InvalidSpaceName("use lowercase ASCII letters, digits, and internal '-' only"))
	} else {
		Ok({ region, space })
	}
}

space_endpoint = |region| "https://${region}.digitaloceanspaces.com"

space_object = |space, key| "s3://${space}/${key}"

space_status = |config, key, stage|
	"Space ${config.space}\nRegion ${config.region}\nObject key ${key}\n${stage}\n"

upload_space_object! = |path, config, key| {
	exit_code = Cmd.new_str("env")
		.args_str([
			"-u",
			"AWS_SESSION_TOKEN",
			"aws",
			"s3",
			"cp",
			Path.display(path),
			space_object(config.space, key),
			"--endpoint-url",
			space_endpoint(config.region),
			"--region",
			config.region,
			"--acl",
			"public-read",
			"--no-progress",
			"--only-show-errors",
		])
		.exec_exit_code!()?
	if exit_code == 0 Ok({}) else Err(SpaceUploadFailed)
}

delete_space_object! = |config, key| {
	exit_code = Cmd.new_str("env")
		.args_str([
			"-u",
			"AWS_SESSION_TOKEN",
			"aws",
			"s3",
			"rm",
			space_object(config.space, key),
			"--endpoint-url",
			space_endpoint(config.region),
			"--region",
			config.region,
			"--only-show-errors",
		])
		.exec_exit_code!()?
	if exit_code == 0 Ok({}) else Err(SpaceObjectDeleteFailed)
}

image_import_local! = |path| {
	if AionState.has_image!()? {
		Err(ImageAlreadyExists)
	} else if !Path.is_file!(path)? or !Path.display(path).ends_with(".qcow2") {
		Err(InvalidLocalImage("path must be a local .qcow2 file"))
	} else {
		config = spaces_config!()?
		auth = token!()?
		confirm_operation!("This uploads one temporary public-read object and imports one custom image into nyc3.", "import local image")?
		key = "aion-imports/aion-agent-${U64.to_str(Random.seed_u64!()?)}-${U64.to_str(Random.seed_u64!()?)}.qcow2"
		operation_tag = operation_tag!("image")?
		status_for = |stage| operation_status(operation_tag, space_status(config, key, stage))
		AionState.begin_image_import!(operation_tag, status_for("Upload not yet completed"))?
		Stdout.line!("image import operation tag ${operation_tag}; pending state is under .aion/image.pending/")?
		match upload_space_object!(path, config, key) {
			Err(error) => {
				AionState.record_import_status!(status_for("Upload outcome uncertain; object retained and lifecycle rule is the fallback")) ?? {}
				return Err(error)
			}
			Ok({}) => {}
		}
		_ = AionState.record_import_status!(status_for("Public-read object uploaded; import POST not yet completed")) ?? {}
		url = "https://${config.space}.${config.region}.digitaloceanspaces.com/${key}"
		outcome = resolve_image_post!(url, auth, operation_tag, status_for)?
		image = match outcome {
			ImagePostAccepted(found) => found
			ImagePostUnresolved(error) => return Err(error)
			ImagePostRejected(error) => {
				AionState.record_import_status!(status_for("Image import POST rejected; immediate source deletion started")) ?? {}
				match delete_space_object!(config, key) {
					Err(delete_error) => {
						AionState.record_import_status!(status_for("Image import POST rejected; source deletion failed; lifecycle rule is the fallback")) ?? {}
						return Err(delete_error)
					}
					Ok({}) => {
						AionState.clear_image_import!()?
						return Err(error)
					}
				}
			}
		}
		id = U64.to_str(image.id)
		AionState.record_imported!(image.id, status_for("Image ID ${id}; polling import"))?
		_ = Stdout.line!("image import accepted (id ${id}); polling at most 60 times") ?? {}
		match poll_image!(auth, image.id, 60) {
			Err(error) => {
				AionState.record_import_status!(status_for("Image ID ${id}; polling did not confirm availability; source retained for recovery")) ?? {}
				Stderr.line!("image readiness is uncertain; source object and operation tag ${operation_tag} retained") ?? {}
				Err(error)
			}
			Ok(ready) => {
				_ = AionState.record_import_status!(status_for("Image ID ${id} available; saving image state and deleting source")) ?? {}
				save = AionState.save_image!({ id: ready.id, name: ready.name, operation_tag })
				delete = delete_space_object!(config, key)
				match (save, delete) {
					(Err(state_error), Err(_)) => {
						AionState.record_import_status!(status_for("Image ID ${id} available; state save failed and source deletion uncertain")) ?? {}
						Err(state_error)
					}
					(Err(state_error), Ok({})) => {
						AionState.record_import_status!(status_for("Image ID ${id} available; source deleted but image state save failed")) ?? {}
						Err(state_error)
					}
					(Ok({}), Err(delete_error)) => {
						AionState.record_import_status!(status_for("Image ID ${id} available and saved; source deletion uncertain")) ?? {}
						Err(delete_error)
					}
					(Ok({}), Ok({})) => {
						AionState.record_import_status!(status_for("Image ID ${id} available and saved; source deleted"))?
						AionState.clear_image_import!()?
						_ = Stdout.line!("image '${ready.name}' available (id ${id}); temporary source deleted") ?? {}
						Ok({})
					}
				}
			}
		}
	}
}

reconcile_droplets! = |auth, operation_tag, attempts_left| {
	match DigitalOceanApi.list_droplets_by_tag!(operation_tag, auth) {
		Ok(droplets) => {
			if !List.is_empty(droplets) or attempts_left == 1 {
				Ok(droplets)
			} else {
				Sleep.seconds!(5)
				reconcile_droplets!(auth, operation_tag, attempts_left - 1)
			}
		}
		Err(error) => {
			if attempts_left == 1 {
				Err(error)
			} else {
				Sleep.seconds!(5)
				reconcile_droplets!(auth, operation_tag, attempts_left - 1)
			}
		}
	}
}

poll_droplet! = |auth, id, attempts_left| {
	if attempts_left == 0 {
		Err(DropletPollTimeout)
	} else {
		droplet = DigitalOceanApi.get_droplet!(id, auth)?
		has_ip = match DigitalOcean.public_ipv4(droplet) {
			Ok(_) => Bool.True
			Err(_) => Bool.False
		}
		if droplet.status == "active" and has_ip {
			Ok(droplet)
		} else if attempts_left == 1 {
			Err(DropletPollTimeout)
		} else {
			Sleep.seconds!(15)
			poll_droplet!(auth, id, attempts_left - 1)
		}
	}
}

unset_env_args = |names|
	match names {
		[] => []
		[first, .. as rest] => ["-u", first].concat(unset_env_args(rest))
	}

secretless_command = |program, arguments|
	Cmd.new_str("env")
		.args_str(
			unset_env_args([
				"AION_MODEL_API_KEY",
				"AWS_ACCESS_KEY_ID",
				"AWS_SECRET_ACCESS_KEY",
				"AWS_SESSION_TOKEN",
				"DIGITALOCEAN_SPACE_NAME",
				"DIGITALOCEAN_SPACE_REGION",
				"DIGITALOCEAN_TOKEN",
				"EVERPAID_API_KEY",
			]).concat([program]).concat(arguments),
		)

# Cloud-init/metadata key install can lag droplet activation; retry ssh for a
# bounded window before giving up.
wait_for_ssh! = |ip, attempts_left| {
	if attempts_left == 0 {
		Err(SshNotReady)
	} else {
		exit_code = secretless_command(
			"timeout",
			[
				"--kill-after=5s",
				"20s",
				"ssh",
				"-o",
				"BatchMode=yes",
				"-o",
				"ConnectTimeout=10",
				"-o",
				"ConnectionAttempts=1",
				"-o",
				"StrictHostKeyChecking=accept-new",
				"aion@${ip}",
				"mkdir -p ~/.config/aion ~/.pi/agent && chmod 0700 ~/.config/aion ~/.pi ~/.pi/agent",
			],
		)
			.exec_exit_code!()?
		if exit_code == 0 {
			Ok({})
		} else if attempts_left == 1 {
			Err(SshNotReady)
		} else {
			Sleep.seconds!(5)
			wait_for_ssh!(ip, attempts_left - 1)
		}
	}
}

render_models_config = ||
	Json.to_str({
		providers: {
			ppq: {
				api: "openai-completions",
				apiKey: "!cat /home/aion/.config/aion/model-key",
				baseUrl: "https://api.ppq.ai/v1",
				models: [
					{
						contextWindow: 200000,
						cost: { cacheRead: 0, cacheWrite: 0, input: 0, output: 0 },
						id: "openai/gpt-5.1-codex",
						input: ["text", "image"],
						maxTokens: 32768,
						name: "openai/gpt-5.1-codex",
						reasoning: Bool.True,
					},
				],
			},
		},
	})

render_pi_settings = ||
	Json.to_str({
		defaultModel: "openai/gpt-5.1-codex",
		defaultProvider: "ppq",
		enableInstallTelemetry: Bool.False,
	})

secretless_os_env = [
	OsStr.utf8("-u"),
	OsStr.utf8("AION_MODEL_API_KEY"),
	OsStr.utf8("-u"),
	OsStr.utf8("AWS_ACCESS_KEY_ID"),
	OsStr.utf8("-u"),
	OsStr.utf8("AWS_SECRET_ACCESS_KEY"),
	OsStr.utf8("-u"),
	OsStr.utf8("AWS_SESSION_TOKEN"),
	OsStr.utf8("-u"),
	OsStr.utf8("DIGITALOCEAN_SPACE_NAME"),
	OsStr.utf8("-u"),
	OsStr.utf8("DIGITALOCEAN_SPACE_REGION"),
	OsStr.utf8("-u"),
	OsStr.utf8("DIGITALOCEAN_TOKEN"),
	OsStr.utf8("-u"),
	OsStr.utf8("EVERPAID_API_KEY"),
]

copy_agent_file! = |ip, source, destination|
	Cmd.exec!(
		OsStr.utf8("env"),
		secretless_os_env.concat([
			OsStr.utf8("timeout"),
			OsStr.utf8("--kill-after=5s"),
			OsStr.utf8("30s"),
			OsStr.utf8("scp"),
			OsStr.utf8("-p"),
			OsStr.utf8("-o"),
			OsStr.utf8("BatchMode=yes"),
			OsStr.utf8("-o"),
			OsStr.utf8("ConnectTimeout=10"),
			OsStr.utf8("-o"),
			OsStr.utf8("ConnectionAttempts=1"),
			OsStr.utf8("-o"),
			OsStr.utf8("StrictHostKeyChecking=accept-new"),
			Path.to_os_str(source),
			OsStr.utf8("aion@${ip}:${destination}"),
		]),
	)

run_agent_command! = |ip, arguments|
	Cmd.exec!(
		OsStr.utf8("env"),
		secretless_os_env.concat([
			OsStr.utf8("timeout"),
			OsStr.utf8("--kill-after=5s"),
			OsStr.utf8("30s"),
			OsStr.utf8("ssh"),
			OsStr.utf8("-o"),
			OsStr.utf8("BatchMode=yes"),
			OsStr.utf8("-o"),
			OsStr.utf8("ConnectTimeout=10"),
			OsStr.utf8("-o"),
			OsStr.utf8("ConnectionAttempts=1"),
			OsStr.utf8("aion@${ip}"),
		]).concat(arguments),
	)

# The key and user configuration travel only inside a private OS temporary
# directory over scp/ssh. Cleanup runs on all paths.
enroll_agent_config! = |ip, model_key| {
	directory = Path.join(Env.temp_dir!(), "aion-config-${U64.to_str(Random.seed_u64!()?)}")
	Path.create_dir!(directory)?
	key_path = Path.join(directory, "model-key")
	models_path = Path.join(directory, "models.json")
	settings_path = Path.join(directory, "settings.json")
	result = enroll_agent_config_stage!(ip, model_key, directory, key_path, models_path, settings_path)
	delete = Path.delete_all!(directory)
	match (result, delete) {
		(Err(error), _) => Err(error)
		(Ok({}), Err(error)) => Err(error)
		(Ok({}), Ok({})) => Ok({})
	}
}

enroll_agent_config_stage! = |ip, model_key, directory, key_path, models_path, settings_path| {
	secretless_command("chmod", ["0700", Path.display(directory)]).exec_cmd!()?
	Path.write_bytes!(key_path, model_key.trim().to_utf8())?
	Path.write_utf8!(models_path, render_models_config())?
	Path.write_utf8!(settings_path, render_pi_settings())?
	secretless_command(
		"chmod",
		["0600", Path.display(key_path), Path.display(models_path), Path.display(settings_path)],
	).exec_cmd!()?
	wait_for_ssh!(ip, 30)?
	copy_agent_file!(ip, key_path, "~/.config/aion/model-key.new")?
	copy_agent_file!(ip, models_path, "~/.pi/agent/models.json.new")?
	copy_agent_file!(ip, settings_path, "~/.pi/agent/settings.json.new")?
	run_agent_command!(
		ip,
		[
			OsStr.utf8("chmod"),
			OsStr.utf8("0600"),
			OsStr.utf8("/home/aion/.config/aion/model-key.new"),
			OsStr.utf8("/home/aion/.pi/agent/models.json.new"),
			OsStr.utf8("/home/aion/.pi/agent/settings.json.new"),
		],
	)?
	run_agent_command!(ip, [OsStr.utf8("mv"), OsStr.utf8("/home/aion/.pi/agent/models.json.new"), OsStr.utf8("/home/aion/.pi/agent/models.json")])?
	run_agent_command!(ip, [OsStr.utf8("mv"), OsStr.utf8("/home/aion/.pi/agent/settings.json.new"), OsStr.utf8("/home/aion/.pi/agent/settings.json")])?
	run_agent_command!(ip, [OsStr.utf8("mv"), OsStr.utf8("/home/aion/.config/aion/model-key.new"), OsStr.utf8("/home/aion/.config/aion/model-key")])?
	Ok({})
}

ssh_key_identity = |key|
	match key.split_on(" ").keep_if(|part| !part.is_empty()) {
		["ssh-ed25519", encoded, ..] if encoded.to_utf8().len() >= 16 and encoded.to_utf8().all(
			|byte|
				(byte >= 'a' and byte <= 'z')
					or (byte >= 'A' and byte <= 'Z')
						or (byte >= '0' and byte <= '9')
							or byte == '+'
								or byte == '/'
									or byte == '=',
		) => Some("ssh-ed25519 ${encoded}")
		_ => None
	}

gump_public_key! = || {
	home = require_env!("HOME", "needed to locate ~/.ssh/gump_aion.pub")?
	ssh = Path.join(Path.utf8(home), ".ssh")
	public_key = Path.join(ssh, "gump_aion.pub")
	operator_key = Path.join(ssh, "id_ed25519.pub")
	if !Path.is_file!(public_key)? {
		return Err(MissingGumpPublicKey("generate ~/.ssh/gump_aion and ~/.ssh/gump_aion.pub"))
	}
	gump_key = Path.read_utf8!(public_key)?.trim()
	gump_identity = ssh_key_identity(gump_key)
	if gump_identity == None {
		return Err(InvalidGumpPublicKey)
	}
	if Path.is_file!(operator_key)? and ssh_key_identity(Path.read_utf8!(operator_key)?.trim()) == gump_identity {
		return Err(GumpKeyMustBeSeparate("gump_aion.pub must differ from id_ed25519.pub"))
	}
	Ok(public_key)
}

authorize_gump! = |ip, executable| {
	public_key = gump_public_key!()?
	wait_for_ssh!(ip, 30)?
	copy_agent_file!(ip, public_key, "~/.config/aion/gump-key.pub")?
	exit_code = secretless_command(
		"timeout",
		[
			"--kill-after=5s",
			"30s",
			"ssh",
			"-o",
			"BatchMode=yes",
			"-o",
			"ConnectTimeout=10",
			"aion@${ip}",
			executable,
			"service",
			"authorize",
			"--root",
			"/home/aion/.gump",
			"--username",
			"aion",
			"--public-key",
			"/home/aion/.config/aion/gump-key.pub",
			"--yes",
		],
	)
		.exec_exit_code!()?
	if exit_code == 0 Ok({}) else Err(GumpAuthorizationFailed)
}

delete_reconciled_droplets! = |auth, droplets| {
	match droplets {
		[] => Ok({})
		[first, .. as rest] => {
			current = DigitalOceanApi.delete_droplet!(first.id, auth)
			remaining = delete_reconciled_droplets!(auth, rest)
			match (current, remaining) {
				(Err(error), _) => Err(error)
				(Ok({}), Err(error)) => Err(error)
				(Ok({}), Ok({})) => Ok({})
			}
		}
	}
}

resolve_droplet_post! = |auth, name, image_id, ssh_key_id, operation_tag| {
	match DigitalOceanApi.create_droplet_once!(name, image_id, ssh_key_id, operation_tag, auth) {
		PostAccepted(droplet) => Ok(droplet)
		PostUncertain(error) => {
			AionState.record_creation_status!(operation_status(operation_tag, "Droplet create POST outcome uncertain; reconciling by operation tag at most 6 times")) ?? {}
			_ = Stderr.line!("Droplet create POST was not retried; reconciling operation tag ${operation_tag}") ?? {}
			droplets = match reconcile_droplets!(auth, operation_tag, 6) {
				Ok(found) => found
				Err(reconcile_error) => {
					AionState.record_creation_status!(operation_status(operation_tag, "Create reconciliation failed; manually list Droplets with this operation tag")) ?? {}
					_ = Stderr.line!("ERROR: create outcome remains uncertain; operation tag ${operation_tag} retained under .aion/create.pending/") ?? {}
					return Err(reconcile_error)
				}
			}
			if List.is_empty(droplets) {
				AionState.record_creation_status!(operation_status(operation_tag, "No Droplet found within the reconciliation bound; manually list Droplets with this operation tag")) ?? {}
				_ = Stderr.line!("ERROR: create outcome remains uncertain; operation tag ${operation_tag} retained under .aion/create.pending/") ?? {}
				Err(PostOutcomeUncertain(error))
			} else {
				ids = resource_ids(droplets)
				AionState.record_creation_status!(operation_status(operation_tag, "Reconciled Droplet IDs ${ids}; automatic deletion started")) ?? {}
				_ = Stderr.line!("uncertain create found Droplet IDs ${ids} for operation tag ${operation_tag}; deleting automatically") ?? {}
				match delete_reconciled_droplets!(auth, droplets) {
					Err(delete_error) => {
						AionState.record_creation_status!(operation_status(operation_tag, "Reconciled Droplet IDs ${ids}; automatic deletion not confirmed; delete manually")) ?? {}
						_ = Stderr.line!("ERROR: automatic deletion was not confirmed for Droplet IDs ${ids}; pending state retained") ?? {}
						Err(delete_error)
					}
					Ok({}) => {
						AionState.record_creation_status!(operation_status(operation_tag, "Reconciled Droplet IDs ${ids}; deletion returned 204"))?
						AionState.clear_creation!()?
						_ = Stderr.line!("automatic cleanup returned 204 for reconciled Droplet IDs ${ids}; operation tag ${operation_tag}") ?? {}
						Err(PostOutcomeUncertain(error))
					}
				}
			}
		}
		PostRejected(error) => {
			AionState.record_creation_status!(operation_status(operation_tag, "Droplet create POST was definitively rejected; operation state retained for inspection")) ?? {}
			Err(error)
		}
	}
}

provision_created! = |auth, droplet, name, ssh_key_id, model_key, operation_tag, provision_agent| {
	AionState.record_created!(droplet.id)?
	active = poll_droplet!(auth, droplet.id, 40)?
	ip = DigitalOcean.public_ipv4(active) ? |_| DropletPollTimeout
	if provision_agent {
		enroll_agent_config!(ip, model_key)?
	} else {
		wait_for_ssh!(ip, 30)?
	}
	AionState.save_machine!({ id: active.id, ip, name, operation_tag, ssh_key_id })?
	Ok(ip)
}

cleanup_created! = |auth, droplet_id, operation_tag, failure| {
	AionState.record_creation_status!(operation_status(operation_tag, "Droplet ID ${U64.to_str(droplet_id)}; provisioning failed; automatic deletion started")) ?? {}
	match DigitalOceanApi.delete_droplet!(droplet_id, auth) {
		Ok({}) => {
			match AionState.clear_creation!() {
				Err(_) => Stderr.line!("warning: cleanup was confirmed but pending state remains for operation tag ${operation_tag}") ?? {}
				Ok({}) => {}
			}
			Stderr.line!("provisioning failed; automatic cleanup confirmed for Droplet ID ${U64.to_str(droplet_id)}; operation tag ${operation_tag}") ?? {}
			Err(failure)
		}
		Err(cleanup_error) => {
			AionState.record_creation_status!(operation_status(operation_tag, "Droplet ID ${U64.to_str(droplet_id)}; automatic deletion not confirmed; delete manually")) ?? {}
			Stderr.line!("ERROR: automatic cleanup could not be confirmed for Droplet ID ${U64.to_str(droplet_id)}; operation tag ${operation_tag}; delete it manually") ?? {}
			Err(cleanup_error)
		}
	}
}

create! = |name, payment_authorized, provision_agent| {
	if !valid_name(name) {
		Err(InvalidMachineName("use 1-63 lowercase ASCII letters, digits, or internal '-' characters"))
	} else if AionState.has_machine!(name)? {
		Err(MachineAlreadyExists("run 'aion status' for local state and 'aion resources' for provider IDs and IPs"))
	} else {
		model_key = if provision_agent require_env!("AION_MODEL_API_KEY", "export a short-lived model API key")? else ""
		if provision_agent and model_key.trim().is_empty() {
			Err(EmptyModelKey)
		} else {
			image = AionState.read_image!()?
			home = require_env!("HOME", "needed to locate ~/.ssh/id_ed25519.pub")?
			public_key = Path.read_utf8!(Path.join(Path.utf8(home), ".ssh/id_ed25519.pub"))?.trim()
			if !payment_authorized {
				confirm_operation!("This creates one s-2vcpu-4gb Droplet in nyc3 and starts hourly billing.", "create ${name}")?
			}
			auth = token!()?
			operation_tag = operation_tag!("droplet")?
			AionState.begin_creation!(name, operation_tag)?
			Stdout.line!("Droplet create operation tag ${operation_tag}; pending state is under .aion/create.pending/")?
			existing = match DigitalOceanApi.list_droplets_by_tag!("aion", auth) {
				Ok(droplets) => droplets
				Err(error) => {
					AionState.record_creation_status!(operation_status(operation_tag, "Aion Droplet preflight failed; no create POST was sent")) ?? {}
					AionState.clear_creation!() ?? {}
					return Err(error)
				}
			}
			if !List.is_empty(existing) {
				ids = resource_ids(existing)
				AionState.record_creation_status!(operation_status(operation_tag, "Refused before POST because tagged Aion Droplet IDs already exist: ${ids}")) ?? {}
				Stderr.line!("create refused because existing Aion Droplets may still be billing:")?
				print_existing_droplets!(existing)?
				Stderr.line!("  inspect everything: aion resources")?
				AionState.clear_creation!()?
				return Err(AionDropletAlreadyExists(ids))
			}
			key = match DigitalOceanApi.register_ssh_key!("aion-${name}", public_key, auth) {
				Ok(found) => found
				Err(error) => {
					AionState.record_creation_status!(operation_status(operation_tag, "SSH key enrollment failed; no Droplet create POST was sent")) ?? {}
					AionState.clear_creation!() ?? {}
					return Err(error)
				}
			}
			ssh_key_id = match key {
				RegisteredKey(created) => created.id
				ReusedKey(reused) => reused.id
			}
			droplet = resolve_droplet_post!(auth, name, image.id, ssh_key_id, operation_tag)?
			match provision_created!(auth, droplet, name, ssh_key_id, model_key, operation_tag, provision_agent) {
				Err(error) => cleanup_created!(auth, droplet.id, operation_tag, error)
				Ok(ip) => {
					match AionState.clear_creation!() {
						Err(_) => Stderr.line!("warning: machine state was saved but pending state remains; Droplet ID ${U64.to_str(droplet.id)}, operation tag ${operation_tag}") ?? {}
						Ok({}) => {}
					}
					_ = Stdout.line!("machine '${name}' active at ${ip} (Droplet ID ${U64.to_str(droplet.id)}, operation tag ${operation_tag})") ?? {}
					Ok({})
				}
			}
		}
	}
}

kai_command! = |operator_directory| {
	match Env.var_str!(OsStr.utf8("AION_KAI")) {
		Ok(command) if !command.trim().is_empty() => Ok(command)
		_ => {
			project_kai = Path.join(operator_directory, "kai")
			if Path.is_executable!(project_kai)? {
				Ok(Path.display(project_kai))
			} else {
				Ok("kai")
			}
		}
	}
}

project_create_preflight! = |name| {
	if !valid_name(name) {
		return Err(InvalidMachineName("use 1-63 lowercase ASCII letters, digits, or internal '-' characters"))
	}
	if AionState.has_machine!(name)? {
		return Err(MachineAlreadyExists("run 'aion status' for local state and 'aion resources' for provider IDs and IPs"))
	}
	existing = DigitalOceanApi.list_droplets_by_tag!("aion", token!()?)?
	if existing.is_empty() {
		Ok({})
	} else {
		Stderr.line!("create refused because existing Aion Droplets may still be billing:")?
		print_existing_droplets!(existing)?
		Stderr.line!("  inspect everything: aion resources")?
		Err(AionDropletAlreadyExists(resource_ids(existing)))
	}
}

Product : { description : Str, machine : Str, priceSats : U64, project : Str, title : Str }

read_product! : Str => Try({ config : Product, project : Str }, _)
read_product! = |name| {
	if !valid_name(name) {
		return Err(InvalidProductName("use 1-63 lowercase ASCII letters, digits, or internal '-' characters"))
	}
	product_directory = Path.join(Path.utf8("products"), name)
	config : Product
	config = Json.parse(Path.read_utf8!(Path.join(product_directory, "product.json"))?)?
	if config.title.trim().is_empty() or config.description.trim().is_empty() or !valid_artifact(config.machine) {
		return Err(InvalidProductMetadata(name))
	}
	project = Path.join(product_directory, config.project)
	if !Path.is_file!(Path.join(project, "Kaifile"))? {
		return Err(ProductKaifileMissing(name))
	}
	Ok({ config, project: Path.display(project) })
}

print_products! = |paths|
	match paths {
		[] => Ok({})
		[first, .. as rest] => {
			name = Path.filename(first).map_ok(Path.display) ?? ""
			if Path.is_dir!(first)? and valid_name(name) and Path.is_file!(Path.join(first, "product.json"))? {
				product = read_product!(name)?
				price = if product.config.priceSats == 0 "free" else "${U64.to_str(product.config.priceSats)} sats"
				Stdout.line!("${name}\t${price}\t${product.config.title} — ${product.config.description}")?
			}
			print_products!(rest)
		}
	}

products! = || {
	catalog = Path.utf8("products")
	if !Path.is_dir!(catalog)? {
		Err(ProductCatalogMissing("products"))
	} else {
		print_products!(Path.list!(catalog)?)
	}
}

build_project_image! = |project, machine| {
	operator_directory = Env.cwd!()?
	project_directory = Path.utf8(project)
	if !Path.is_dir!(project_directory)? {
		return Err(DeploymentProjectMissing(project))
	}
	Env.set_cwd!(project_directory)?
	project_root = Env.cwd!()?
	kai_command = kai_command!(project_root)?
	result = Cmd.new_str(kai_command).args_str(["image", machine]).exec_exit_code!()
	image = Path.join(project_root, ".kai/artifacts/images/${machine}/result/${machine}.qcow2")
	identity = match secretless_command("realpath", [Path.display(image)]).exec_output!() {
		Ok(output) => output.stdout_utf8.trim()
		Err(_) => ""
	}
	restore = Env.set_cwd!(operator_directory)
	match (result, restore) {
		(Err(error), _) => Err(error)
		(Ok(_), Err(error)) => Err(error)
		(Ok(0), Ok({})) => if Path.is_file!(image)? and !identity.is_empty() Ok({ identity, image, project: Path.display(project_root) }) else Err(ProjectImageMissing(Path.display(image)))
		(Ok(_), Ok({})) => Err(KaiImageBuildFailed)
	}
}

create_project! = |name, project, machine| {
	if !valid_artifact(machine) {
		return Err(InvalidMachineName("use ASCII letters, digits, '.', '_', and internal '-' characters"))
	}
	project_create_preflight!(name)?
	if machine == "gump" {
		_ = gump_public_key!()?
	}
	built = build_project_image!(project, machine)?
	if AionState.has_saved_image!()? {
		saved = AionState.read_project_image!()?
		if saved.machine != machine or saved.project != built.project or saved.image != built.identity {
			return Err(ProjectImageMismatch("delete the saved image before selecting another project machine or build"))
		}
	} else {
		match image_import_local!(built.image) {
			Err(error) => {
				if AionState.has_saved_image!() ?? Bool.False {
					AionState.save_project_image!({ image: built.identity, machine, project: built.project }) ?? {}
				}
				return Err(error)
			}
			Ok({}) => AionState.save_project_image!({ image: built.identity, machine, project: built.project })?
		}
	}
	create!(name, Bool.False, machine == "gump")?
	if machine == "gump" {
		created = AionState.read_machine!(name)?
		authorize_gump!(created.ip, "/run/current-system/sw/bin/gump")
	} else {
		Ok({})
	}
}

create_product! = |name, product_name| {
	product = read_product!(product_name)?
	create_project!(name, product.project, product.config.machine)
}

operator_ssh_key! = |auth| {
	home = require_env!("HOME", "needed to locate ~/.ssh/id_ed25519.pub")?
	public_key = Path.read_utf8!(Path.join(Path.utf8(home), ".ssh/id_ed25519.pub"))?.trim()
	match DigitalOceanApi.list_ssh_keys!(auth)?.keep_if(|key| key.public_key.trim() == public_key) {
		[first, ..] => Ok(first)
		[] => Err(NoMatchingSshKey)
	}
}

recover! = |name, id| {
	if !valid_name(name) {
		return Err(InvalidMachineName("use 1-63 lowercase ASCII letters, digits, or internal '-' characters"))
	}
	if AionState.has_saved_machine!(name)? {
		return Err(MachineAlreadyExists("saved machine state already exists; run 'aion status'"))
	}
	if AionState.has_pending_creation!()? {
		pending_name = AionState.read_pending_creation_name!()?
		pending_id = AionState.read_pending_creation_id!()?
		if pending_name != name or pending_id != id {
			return Err(PendingCreationDoesNotMatch({ id: pending_id, name: pending_name }))
		}
	}
	auth = token!()?
	droplet = DigitalOceanApi.get_droplet!(id, auth)?
	ip = DigitalOcean.public_ipv4(droplet) ? |_| DropletNotRecoverable({ id, name, status: droplet.status })
	operation_tag = operation_tag_from(droplet)?
	if droplet.name != name or droplet.status != "active" or !List.any(droplet.tags, |tag| tag == "aion") {
		return Err(DropletNotRecoverable({ id, name, status: droplet.status }))
	}
	if AionState.has_pending_creation!()? {
		pending_tag = AionState.read_pending_creation_operation_tag!()?
		if pending_tag != operation_tag {
			return Err(PendingCreationTagDoesNotMatch)
		}
	}
	ssh_key = operator_ssh_key!(auth)?
	if AionState.has_project_image!()? {
		project = AionState.read_project_image!()?
		if project.machine == "gump" {
			authorize_gump!(ip, "/run/current-system/sw/bin/gump")?
		} else {
			wait_for_ssh!(ip, 30)?
		}
	} else {
		model_key = require_nonempty_env!("AION_MODEL_API_KEY", "needed to finish agent provisioning")?
		enroll_agent_config!(ip, model_key)?
	}
	AionState.save_machine!({ id, ip, name, operation_tag, ssh_key_id: ssh_key.id })?
	if AionState.has_pending_creation!()? {
		AionState.clear_creation!()?
	}
	Stdout.line!("recovered machine '${name}' at ${ip} (Droplet ID ${U64.to_str(id)}, operation tag ${operation_tag})")
}

recover_argument! = |name, id|
	match U64.from_str(id) {
		Ok(parsed) => recover!(name, parsed)
		Err(_) => Err(InvalidDropletId(id))
	}

deploy_in_project! = |kai_command, machine, artifact| {
	kaifile = Path.utf8("Kaifile")
	if !Path.is_file!(kaifile)? {
		return Err(DeploymentKaifileMissing)
	}
	deployment = "aion-${artifact}"
	generated = Path.utf8(".kai/aion-deploy.Kaifile")
	Path.create_all!(Path.utf8(".kai"))?
	config = Path.read_utf8!(kaifile)?
	Path.write_utf8!(
		generated,
		"${config}\n\ndeploy ${deployment} {\n  artifact: \"${artifact}\"\n  to: \"ssh://aion@${machine.ip}\"\n}\n",
	)?
	result = Cmd.new_str(kai_command)
		.args_str(["-f", Path.display(generated), "deploy", deployment])
		.exec_exit_code!()
	cleanup = Path.delete!(generated)
	match (result, cleanup) {
		(Err(error), _) => Err(error)
		(Ok(_), Err(error)) => Err(error)
		(Ok(0), Ok({})) => {
			Stdout.line!("deployed artifact '${artifact}' to machine '${machine.name}'")?
			Stdout.line!("remote artifact: /home/aion/.local/state/kai/deployments/${deployment}/current")
		}
		(Ok(_), Ok({})) => Err(KaiDeploymentFailed)
	}
}

deploy! = |machine_name, artifact, project| {
	if !valid_name(machine_name) {
		return Err(InvalidMachineName("use 1-63 lowercase ASCII letters, digits, or internal '-' characters"))
	}
	if !valid_artifact(artifact) {
		return Err(InvalidArtifactName("use ASCII letters, digits, '.', '_', and internal '-' characters"))
	}
	machine = AionState.read_machine!(machine_name)?
	if artifact == "gump" {
		_ = gump_public_key!()?
	}
	operator_directory = Env.cwd!()?
	project_directory = Path.utf8(project)
	if !Path.is_dir!(project_directory)? {
		return Err(DeploymentProjectMissing(project))
	}
	Env.set_cwd!(project_directory)?
	project_root = Env.cwd!()?
	kai_command = kai_command!(project_root)?
	result = deploy_in_project!(kai_command, machine, artifact)
	restore = Env.set_cwd!(operator_directory)
	match (result, restore) {
		(Err(error), _) => Err(error)
		(Ok({}), Err(error)) => Err(error)
		(Ok({}), Ok({})) => {
			if artifact == "gump" {
				authorize_gump!(machine.ip, "/home/aion/.local/state/kai/deployments/aion-gump/current")
			} else {
				Ok({})
			}
		}
	}
}

everpaid_create_invoice! = |name, reference| {
	if !valid_name(name) or !Everpaid.reference_matches_machine(reference, name) {
		return Err(InvalidEverpaidInvoiceRequest)
	}
	api_key = require_nonempty_env!("EVERPAID_API_KEY", "needed to create an invoice")?
	invoice = EverpaidApi.create_invoice!(Everpaid.machine_price_sats, name, reference, api_key)?
	Stdout.line!(Json.to_str(invoice))
}

everpaid_get_payment! = |id| {
	api_key = require_nonempty_env!("EVERPAID_API_KEY", "needed to read a payment")?
	payment = EverpaidApi.get_payment!(id, api_key)?
	Stdout.line!(Json.to_str(payment))
}

payment_preflight! = |name| {
	if !valid_name(name) {
		return Err(InvalidMachineName("use 1-63 lowercase ASCII letters, digits, or internal '-' characters"))
	}
	if AionState.has_machine!(name)? {
		return Err(MachineAlreadyExists("local machine state or a create operation already exists"))
	}
	_ = AionState.read_image!()?
	model_key = require_nonempty_env!("AION_MODEL_API_KEY", "export a short-lived model API key")?
	_ = model_key
	home = require_env!("HOME", "needed to locate ~/.ssh/id_ed25519.pub")?
	public_key = Path.read_utf8!(Path.join(Path.utf8(home), ".ssh/id_ed25519.pub"))?.trim()
	if public_key.is_empty() {
		return Err(EmptySshPublicKey)
	}
	existing = DigitalOceanApi.list_droplets_by_tag!("aion", token!()?)?
	if List.is_empty(existing) Ok({}) else Err(AionDropletAlreadyExists(resource_ids(existing)))
}

create_paid! = |name| {
	payment_id = require_nonempty_env!("AION_EVERPAID_PAYMENT_ID", "paid creates may only come from the Aion web server")?
	everpaid_key = require_nonempty_env!("EVERPAID_API_KEY", "needed to verify settlement")?
	payment = EverpaidApi.get_payment!(payment_id, everpaid_key)?
	saved_order : Try({ payment_id : Str, reference : Str }, _)
	saved_order = Json.parse(Path.read_utf8!(Path.utf8(".aion/payments/${name}.json"))?)
	order = saved_order?
	if payment.status != "settled"
		or payment.amountSats != Everpaid.machine_price_sats
			or order.payment_id != payment.id
				or order.reference != payment.reference
					or !Everpaid.reference_matches_machine(payment.reference, name) {
		Err(PaymentNotAuthorized)
	} else {
		consumed = Path.utf8(".aion/payments/${name}.consumed")
		Path.create_all!(Path.utf8(".aion/payments"))?
		Path.create_dir!(consumed)?
		Path.write_utf8!(Path.join(consumed, "payment-id"), payment_id)?
		create!(name, Bool.True, Bool.True)
	}
}

saved_machine_ids = |snapshots|
	match snapshots {
		[] => []
		[InvalidMachine(_), .. as rest] => saved_machine_ids(rest)
		[SavedMachine(machine), .. as rest] => [machine.id].concat(saved_machine_ids(rest))
	}

saved_ssh_key_ids = |snapshots|
	match snapshots {
		[] => []
		[InvalidMachine(_), .. as rest] => saved_ssh_key_ids(rest)
		[SavedMachine(machine), .. as rest] => [machine.ssh_key_id].concat(saved_ssh_key_ids(rest))
	}

resource_labels = |saved, pending, uncertain| {
	tracked = if saved and pending {
		"saved,pending"
	} else if saved {
		"saved"
	} else if pending {
		"pending"
	} else {
		"untracked"
	}
	if uncertain "${tracked},tracking-uncertain" else tracked
}

resource_label_color = |label|
	if label.contains("uncertain") or label.contains("untracked") {
		Ansi.red(label)
	} else if label.contains("pending") {
		Ansi.yellow(label)
	} else {
		Ansi.green(label)
	}

provider_status_color = |status|
	if status == "active" or status == "available" {
		Ansi.green(status)
	} else if status == "deleted" or status == "error" {
		Ansi.red(status)
	} else {
		Ansi.yellow(status)
	}

print_images! = |images, saved_id, pending_id, pending_tag, uncertain|
	match images {
		[] => Ok({})
		[first, .. as rest] => {
			saved = saved_id == Some(first.id)
			pending = pending_id == Some(first.id) or match pending_tag {
				Some(tag) => List.any(first.tags, |candidate| candidate == tag)
				None => Bool.False
			}
			billing = if first.status == "deleted" Ansi.dim("not-billable") else Ansi.yellow("potentially-billable-storage")
			status = provider_status_color(first.status)
			label = resource_label_color(resource_labels(saved, pending, uncertain))
			Stdout.line!("  ${Ansi.dim(U64.to_str(first.id))}  ${status}  ${Ansi.cyan(first.name)}  [${label}] ${billing}")?
			print_images!(rest, saved_id, pending_id, pending_tag, uncertain)
		}
	}

print_droplets! = |droplets, saved_ids, pending_id, pending_tag, uncertain|
	match droplets {
		[] => Ok({})
		[first, .. as rest] => {
			saved = List.any(saved_ids, |id| id == first.id)
			pending = pending_id == Some(first.id) or match pending_tag {
				Some(tag) => List.any(first.tags, |candidate| candidate == tag)
				None => Bool.False
			}
			addresses = Str.join_with(DigitalOcean.public_ipv4s(first), ",")
			ip = if addresses.is_empty() Ansi.red("no-public-ip") else Ansi.cyan(addresses)
			status = provider_status_color(first.status)
			label = resource_label_color(resource_labels(saved, pending, uncertain))
			billing = Ansi.yellow("billable-compute")
			Stdout.line!("  ${Ansi.dim(U64.to_str(first.id))}  ${status}  ${Ansi.cyan(first.name)}  ${ip}  [${label}] ${billing}")?
			print_droplets!(rest, saved_ids, pending_id, pending_tag, uncertain)
		}
	}

print_ssh_keys! = |keys, saved_ids, uncertain|
	match keys {
		[] => Ok({})
		[first, .. as rest] => {
			if first.name.starts_with("aion-") {
				saved = List.any(saved_ids, |id| id == first.id)
				label = resource_label_color(resource_labels(saved, Bool.False, uncertain))
				Stdout.line!("  ${Ansi.dim(U64.to_str(first.id))}  ${Ansi.cyan(first.name)}  [${label}]")?
			}
			print_ssh_keys!(rest, saved_ids, uncertain)
		}
	}

resources! = || {
	auth = token!()?
	has_image = AionState.has_saved_image!()?
	image = match AionState.read_image!() {
		Ok(saved) => Some(saved.id)
		Err(_) => None
	}
	has_pending_image = AionState.has_pending_image!()?
	pending_image = match AionState.read_pending_image_id!() {
		Ok(id) => Some(id)
		Err(_) => None
	}
	pending_image_tag = match AionState.read_pending_image_operation_tag!() {
		Ok(tag) => Some(tag)
		Err(_) => None
	}
	image_tracking_uncertain = (has_image and image == None) or (has_pending_image and pending_image_tag == None)
	machines = AionState.read_machines!()?
	invalid_machine = List.any(
		machines,
		|snapshot| match snapshot {
			InvalidMachine(_) => Bool.True
			SavedMachine(_) => Bool.False
		},
	)
	machine_ids = saved_machine_ids(machines)
	key_ids = saved_ssh_key_ids(machines)
	pending_droplet = match AionState.read_pending_creation_id!() {
		Ok(id) => Some(id)
		Err(_) => None
	}
	pending_droplet_tag = match AionState.read_pending_creation_operation_tag!() {
		Ok(tag) => Some(tag)
		Err(_) => None
	}
	has_pending_creation = AionState.has_pending_creation!()?
	machine_tracking_uncertain = invalid_machine or (has_pending_creation and pending_droplet_tag == None)
	Stdout.line!(Ansi.heading("DigitalOcean Aion resources"))?
	images_ok = match DigitalOceanApi.list_private_images_by_tag!("aion", auth) {
		Err(_) => {
			Stdout.line!("${Ansi.bold("images:")} ${Ansi.red("unavailable")}")?
			Bool.False
		}
		Ok(images) => {
			Stdout.line!(Ansi.bold("images:"))?
			if images.is_empty() Stdout.line!(Ansi.dim("  none"))? else print_images!(images, image, pending_image, pending_image_tag, image_tracking_uncertain)?
			Bool.True
		}
	}
	droplets_ok = match DigitalOceanApi.list_droplets_by_tag!("aion", auth) {
		Err(_) => {
			Stdout.line!("${Ansi.bold("droplets:")} ${Ansi.red("unavailable")}")?
			Bool.False
		}
		Ok(droplets) => {
			Stdout.line!(Ansi.bold("droplets:"))?
			if droplets.is_empty() Stdout.line!(Ansi.dim("  none"))? else print_droplets!(droplets, machine_ids, pending_droplet, pending_droplet_tag, machine_tracking_uncertain)?
			Bool.True
		}
	}
	keys_ok = match DigitalOceanApi.list_ssh_keys!(auth) {
		Err(_) => {
			Stdout.line!("${Ansi.bold("ssh keys:")} ${Ansi.red("unavailable")}")?
			Bool.False
		}
		Ok(keys) => {
			Stdout.line!(Ansi.bold("ssh keys:"))?
			aion_keys = keys.keep_if(|key| key.name.starts_with("aion-"))
			if aion_keys.is_empty() Stdout.line!(Ansi.dim("  none"))? else print_ssh_keys!(aion_keys, key_ids, machine_tracking_uncertain)?
			Bool.True
		}
	}
	if images_ok and droplets_ok and keys_ok Ok({}) else Err(ResourceInventoryIncomplete)
}

print_machine_snapshots! = |snapshots|
	match snapshots {
		[] => Ok({})
		[InvalidMachine(name), .. as rest] => {
			Stdout.line!(Ansi.red("  ${name}: invalid local state"))?
			print_machine_snapshots!(rest)
		}
		[SavedMachine(machine), .. as rest] => {
			Stdout.line!("  ${Ansi.cyan(machine.name)}: ${Ansi.green("recorded")}, id ${Ansi.dim(U64.to_str(machine.id))}, ip ${Ansi.cyan(machine.ip)}, operation ${Ansi.dim(machine.operation_tag)}")?
			print_machine_snapshots!(rest)
		}
	}

machines! = || {
	machines = AionState.read_machines!()?
	if machines.is_empty() {
		Stdout.line!(Ansi.dim("No machines recorded."))
	} else {
		Stdout.line!(Ansi.heading("Machines"))?
		print_machine_snapshots!(machines)
	}
}

print_pending! = |label, status| {
	Stdout.line!(Ansi.yellow("${label}:"))?
	Stdout.write!(Ansi.yellow(status))?
	if status.ends_with("\n") Ok({}) else Stdout.line!("")
}

status! = || {
	Stdout.line!(Ansi.heading("Local Aion state"))?
	Stdout.line!(Ansi.dim("Provider not queried"))?
	match AionState.has_saved_image!() {
		Err(_) => Stdout.line!("${Ansi.bold("image:")} ${Ansi.red("local state unreadable")}")?
		Ok(Bool.False) => Stdout.line!("${Ansi.bold("image:")} ${Ansi.dim("none recorded")}")?
		Ok(Bool.True) => match AionState.read_image!() {
			Err(_) => Stdout.line!("${Ansi.bold("image:")} ${Ansi.red("invalid local state")}")?
			Ok(image) => Stdout.line!("${Ansi.bold("image:")} ${Ansi.green("recorded")} '${Ansi.cyan(image.name)}', id ${Ansi.dim(U64.to_str(image.id))}, operation ${Ansi.dim(image.operation_tag)}")?
		}
	}
	machines = AionState.read_machines!()?
	Stdout.line!(Ansi.bold("machines:"))?
	if machines.is_empty() {
		Stdout.line!(Ansi.dim("  none recorded"))?
	} else {
		print_machine_snapshots!(machines)?
	}
	if AionState.has_project_image!()? {
		match AionState.read_project_image!() {
			Err(_) => Stdout.line!("${Ansi.bold("project image:")} ${Ansi.red("invalid local state")}")?
			Ok(project) => Stdout.line!("${Ansi.bold("project image:")} machine ${Ansi.cyan(project.machine)}, project ${project.project}, build ${Ansi.dim(project.image)}")?
		}
	} else {
		Stdout.line!("${Ansi.bold("project image:")} ${Ansi.dim("none recorded")}")?
	}
	if AionState.has_image_operation!()? {
		Stdout.line!(Ansi.yellow("image operation lock: active; inspect running processes before removing .aion/image.operation"))?
	} else {
		Stdout.line!("${Ansi.bold("image operation lock:")} ${Ansi.dim("none")}")?
	}
	if AionState.has_pending_image!()? {
		match AionState.read_pending_image_status!() {
			Err(_) => Stdout.line!("pending image import: status unreadable")?
			Ok(pending) => print_pending!("pending image import", pending)?
		}
	} else {
		Stdout.line!("${Ansi.bold("pending image import:")} ${Ansi.dim("none")}")?
	}
	if AionState.has_pending_creation!()? {
		match AionState.read_pending_creation_status!() {
			Err(_) => Stdout.line!("pending machine create: status unreadable")?
			Ok(pending) => print_pending!("pending machine create", pending)?
		}
	} else {
		Stdout.line!("${Ansi.bold("pending machine create:")} ${Ansi.dim("none")}")?
	}
	match AionState.read_payment_reservation!()? {
		None => Stdout.line!("${Ansi.bold("payment reservation:")} ${Ansi.dim("none")}")
		Some(name) if name.is_empty() => Stdout.line!("${Ansi.bold("payment reservation:")} ${Ansi.red("invalid")}")
		Some(name) => Stdout.line!("${Ansi.bold("payment reservation:")} machine ${Ansi.yellow(name)}")
	}
}

ssh_probe! = |ip| {
	exit_code = secretless_command(
		"timeout",
		[
			"--kill-after=2s",
			"12s",
			"ssh",
			"-o",
			"BatchMode=yes",
			"-o",
			"ConnectTimeout=8",
			"-o",
			"ConnectionAttempts=1",
			"-o",
			"StrictHostKeyChecking=yes",
			"-o",
			"UpdateHostKeys=no",
			"aion@${ip}",
			"true",
		],
	)
		.exec_exit_code!()?
	if exit_code == 0 Ok({}) else Err(SshCheckFailed)
}

check! = |name| {
	if !valid_name(name) {
		return Err(InvalidMachineName("use 1-63 lowercase ASCII letters, digits, or internal '-' characters"))
	}
	machine = AionState.read_machine!(name)?
	if machine.name != name {
		return Err(MachineStateMismatch)
	}
	Stdout.line!("${Ansi.bold("local:")} name ${Ansi.cyan(machine.name)}, id ${Ansi.dim(U64.to_str(machine.id))}, ip ${Ansi.cyan(machine.ip)}, operation ${Ansi.dim(machine.operation_tag)}")?
	droplet = DigitalOceanApi.get_droplet!(machine.id, token!()?)?
	addresses = DigitalOcean.public_ipv4s(droplet)
	ip_list = Str.join_with(addresses, ",")
	provider_ips = if ip_list.is_empty() "none" else ip_list
	Stdout.line!("${Ansi.bold("provider:")} name ${Ansi.cyan(droplet.name)}, status ${provider_status_color(droplet.status)}, ips ${Ansi.cyan(provider_ips)}")?
	has_aion_tag = List.any(droplet.tags, |tag| tag == "aion")
	has_operation_tag = machine.operation_tag == "legacy-unknown" or List.any(droplet.tags, |tag| tag == machine.operation_tag)
	ip_matches = List.any(addresses, |ip| ip == machine.ip)
	if droplet.name != machine.name or droplet.status != "active" or !has_aion_tag or !has_operation_tag or !ip_matches {
		Stdout.line!(Ansi.yellow("ssh: skipped because local and provider state do not agree"))?
		Err(MachineStateMismatch)
	} else {
		match ssh_probe!(machine.ip) {
			Err(error) => {
				Stdout.line!(Ansi.red("ssh: unreachable or host key not trusted"))?
				Err(error)
			}
			Ok({}) => Stdout.line!(Ansi.green("ssh: reachable"))
		}
	}
}

shell! = |name, run_pi| {
	if !valid_name(name) {
		return Err(InvalidMachineName("use 1-63 lowercase ASCII letters, digits, or internal '-' characters"))
	}
	machine = AionState.read_machine!(name)?
	base = [
		OsStr.utf8("-o"),
		OsStr.utf8("StrictHostKeyChecking=accept-new"),
		OsStr.utf8("aion@${machine.ip}"),
	]
	arguments = if run_pi [OsStr.utf8("-t")].concat(base).concat([OsStr.utf8("pi")]) else base
	Cmd.exec!(OsStr.utf8("ssh"), arguments)
}

image_status! = || {
	id = if AionState.has_saved_image!()? {
		image = AionState.read_image!()?
		image.id
	} else {
		AionState.read_pending_image_id!()?
	}
	image = DigitalOceanApi.get_image!(id, token!()?)?
	Stdout.line!("image '${Ansi.cyan(image.name)}' (id ${Ansi.dim(U64.to_str(image.id))}) is ${provider_status_color(image.status)}")
}

image_reconcile_locked! = || {
	if AionState.has_saved_image!()? {
		Err(ImageAlreadyExists)
	} else {
		id = AionState.read_pending_image_id!()?
		operation_tag = AionState.read_pending_image_operation_tag!()?
		image = DigitalOceanApi.get_image!(id, token!()?)?
		tags_match = List.any(image.tags, |tag| tag == "aion") and List.any(image.tags, |tag| tag == operation_tag)
		if image.status != "available" {
			Err(ImageNotAvailable(image.status))
		} else if !tags_match {
			Err(PendingImageDoesNotMatchProvider)
		} else if AionState.has_saved_image!()? {
			Err(ImageAlreadyExists)
		} else {
			AionState.save_image!({ id: image.id, name: image.name, operation_tag })?
			status = match AionState.read_pending_image_status!() {
				Ok(previous) => "${previous.trim()}\n"
				Err(_) => "Operation tag ${operation_tag}\n"
			}
			match AionState.record_import_status!("${status}Image ID ${U64.to_str(image.id)} recovered into local state; pending source cleanup remains\n") {
				Ok({}) => {}
				Err(_) => Stderr.line!("warning: image state recovered but pending status could not be updated") ?? {}
			}
			Stdout.line!("image '${image.name}' (id ${U64.to_str(image.id)}) recovered; pending source state retained for lifecycle cleanup")
		}
	}
}

image_reconcile! = || {
	AionState.begin_image_operation!()?
	result = image_reconcile_locked!()
	unlock = AionState.clear_image_operation!()
	match (result, unlock) {
		(Err(error), _) => Err(error)
		(Ok({}), Err(error)) => Err(error)
		(Ok({}), Ok({})) => Ok({})
	}
}

image_delete_locked! = || {
	candidate = if AionState.has_saved_image!()? {
		image = AionState.read_image!()?
		{ image, saved: Bool.True }
	} else {
		pending_id = AionState.read_pending_image_id!()?
		{ image: { id: pending_id, name: "pending import", operation_tag: "see .aion/image.pending/operation-tag" }, saved: Bool.False }
	}
	id = U64.to_str(candidate.image.id)
	confirm_operation!("This permanently deletes imported image '${candidate.image.name}' (id ${id}).", "delete image ${id}")?
	auth = token!()?
	match DigitalOceanApi.delete_image!(candidate.image.id, auth) {
		Err(error) => {
			Stderr.line!("ERROR: image deletion could not be confirmed for image ID ${id}; local state retained") ?? {}
			Err(error)
		}
		Ok({}) => {
			if candidate.saved {
				AionState.delete_image!()?
				_ = Stdout.line!("image deletion returned 204; local image state removed") ?? {}
				Ok({})
			} else {
				_ = Stdout.line!("pending image deletion returned 204; pending state retained for source-object recovery") ?? {}
				Ok({})
			}
		}
	}
}

image_delete! = || {
	AionState.begin_image_operation!()?
	result = image_delete_locked!()
	unlock = AionState.clear_image_operation!()
	match (result, unlock) {
		(Err(error), _) => Err(error)
		(Ok({}), Err(error)) => Err(error)
		(Ok({}), Ok({})) => Ok({})
	}
}

destroy! = |name| {
	if !valid_name(name) {
		return Err(InvalidMachineName("use 1-63 lowercase ASCII letters, digits, or internal '-' characters"))
	}
	machine = AionState.read_machine!(name)?
	auth = token!()?
	match DigitalOceanApi.delete_droplet!(machine.id, auth) {
		Err(error) => {
			Stderr.line!("ERROR: deletion could not be confirmed for Droplet ID ${U64.to_str(machine.id)}, operation tag ${machine.operation_tag}; local state retained") ?? {}
			Err(error)
		}
		Ok({}) => {
			AionState.delete_machine!(name)?
			image_note = match AionState.read_image!() {
				Ok(image) => "image id ${U64.to_str(image.id)}"
				Err(_) => "image state not found"
			}
			_ = Stdout.line!("droplet deletion returned 204; local state removed") ?? {}
			_ = Stdout.line!("retained for manual cleanup: ${image_note}, ssh key id ${U64.to_str(machine.ssh_key_id)} (aion-${name}), operation tag ${machine.operation_tag}") ?? {}
			Ok({})
		}
	}
}

main! = |args| {
	arguments = args.drop_first(1).map(OsStr.display)
	if List.any(arguments, is_help_flag) {
		topic = match arguments {
			["-h", ..] | ["--help", ..] => ""
			[first, ..] => first
			[] => ""
		}
		print_help!(topic)
	} else match arguments {
		[] => print_help!("")
		["help"] => print_help!("")
		["help", topic, ..] => print_help!(topic)
		["status"] => status!()
		["resources"] => resources!()
		["machines"] => machines!()
		["images", "import", url] => image_import!(url)
		["images", "import-local", path] => image_import_local!(Path.utf8(path))
		["images", "status"] => image_status!()
		["images", "reconcile"] => image_reconcile!()
		["images", "delete"] => image_delete!()
		["image", "import", url] => image_import!(url)
		["image", "import-local", path] => image_import_local!(Path.utf8(path))
		["image", "status"] => image_status!()
		["image", "reconcile"] => image_reconcile!()
		["image", "delete"] => image_delete!()
		["products"] => products!()
		["create", name] => create!(name, Bool.False, Bool.True)
		["create", name, product] => create_product!(name, product)
		["create", name, "--project", project, "--machine", machine] => create_project!(name, project, machine)
		["recover", name, id] => recover_argument!(name, id)
		["create-paid", name] => create_paid!(name)
		["everpaid-create-invoice", name, reference] => everpaid_create_invoice!(name, reference)
		["everpaid-get-payment", id] => everpaid_get_payment!(id)
		["payment-preflight", name] => payment_preflight!(name)
		["deploy", machine, artifact] => deploy!(machine, artifact, ".")
		["deploy", machine, artifact, "--project", project] => deploy!(machine, artifact, project)
		["machine", name, "status"] => check!(name)
		["machine", name, "shell"] => shell!(name, Bool.False)
		["machine", name, "shell", "pi"] => shell!(name, Bool.True)
		["machine", name, "destroy"] => destroy!(name)
		[name, "check"] => check!(name)
		[name, "shell"] => shell!(name, Bool.False)
		[name, "shell", "pi"] => shell!(name, Bool.True)
		["destroy", name] => destroy!(name)
		_ => Stdout.line!(usage)
	}
}
