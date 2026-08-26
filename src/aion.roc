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
import DigitalOcean
import DigitalOceanApi
import Everpaid
import EverpaidApi

usage = Str.join_with(
	[
		"Usage: aion <command>",
		"  aion image import <https-url>",
		"  aion image import-local <path>",
		"  aion image status",
		"  aion image delete",
		"  aion create <name>",
		"  aion <name> shell [pi]",
		"  aion destroy <name>",
	],
	"\n",
)

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

operation_tag! = |kind|
	Ok("aion-${kind}-${U64.to_str(Random.seed_u64!()?)}-${U64.to_str(Random.seed_u64!()?)}")

operation_status = |operation_tag, stage|
	"Operation tag ${operation_tag}\n${stage}\n"

resource_ids = |resources|
	Str.join_with(resources.map(|resource| U64.to_str(resource.id)), ", ")

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

secretless_command = |program, arguments|
	Cmd.new_str("env")
		.args_str(["-u", "EVERPAID_API_KEY", "-u", "DIGITALOCEAN_TOKEN", "-u", "AION_MODEL_API_KEY", program].concat(arguments))

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
				"mkdir -p ~/.config/aion",
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

# The key travels only inside a private OS temporary directory over scp/ssh;
# never in argv, API payloads, logs, or .aion state. Cleanup runs on all paths.
enroll_model_key! = |ip, model_key| {
	directory = Path.join(Env.temp_dir!(), "aion-key-${U64.to_str(Random.seed_u64!()?)}")
	Path.create_dir!(directory)?
	temporary = Path.join(directory, "model-key")
	result = enroll_model_key_stage!(ip, model_key, directory, temporary)
	delete = Path.delete_all!(directory)
	match (result, delete) {
		(Err(error), _) => Err(error)
		(Ok({}), Err(error)) => Err(error)
		(Ok({}), Ok({})) => Ok({})
	}
}

enroll_model_key_stage! = |ip, model_key, directory, temporary| {
	secretless_command("chmod", ["0700", Path.display(directory)]).exec_cmd!()?
	Path.write_bytes!(temporary, model_key.trim().to_utf8())?
	secretless_command("chmod", ["0600", Path.display(temporary)]).exec_cmd!()?
	wait_for_ssh!(ip, 30)?
	Cmd.exec!(
		OsStr.utf8("env"),
		[
			OsStr.utf8("-u"),
			OsStr.utf8("EVERPAID_API_KEY"),
			OsStr.utf8("-u"),
			OsStr.utf8("DIGITALOCEAN_TOKEN"),
			OsStr.utf8("-u"),
			OsStr.utf8("AION_MODEL_API_KEY"),
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
			Path.to_os_str(temporary),
			OsStr.utf8("aion@${ip}:~/.config/aion/model-key.new"),
		],
	)?
	Cmd.exec!(
		OsStr.utf8("env"),
		[
			OsStr.utf8("-u"),
			OsStr.utf8("EVERPAID_API_KEY"),
			OsStr.utf8("-u"),
			OsStr.utf8("DIGITALOCEAN_TOKEN"),
			OsStr.utf8("-u"),
			OsStr.utf8("AION_MODEL_API_KEY"),
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
			OsStr.utf8("-o"),
			OsStr.utf8("StrictHostKeyChecking=accept-new"),
			OsStr.utf8("aion@${ip}"),
			OsStr.utf8("aion-init"),
			OsStr.utf8("adopt-model-key"),
		],
	)?
	Ok({})
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

provision_created! = |auth, droplet, name, ssh_key_id, model_key, operation_tag| {
	AionState.record_created!(droplet.id)?
	active = poll_droplet!(auth, droplet.id, 40)?
	ip = DigitalOcean.public_ipv4(active) ? |_| DropletPollTimeout
	enroll_model_key!(ip, model_key)?
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

create! = |name, payment_authorized| {
	if !valid_name(name) {
		Err(InvalidMachineName("use 1-63 lowercase ASCII letters, digits, or internal '-' characters"))
	} else if AionState.has_machine!(name)? {
		Err(MachineAlreadyExists("local machine state or a create operation already exists"))
	} else {
		model_key = require_env!("AION_MODEL_API_KEY", "export a short-lived model API key")?
		if model_key.trim().is_empty() {
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
				Stderr.line!("refusing create: tagged Aion Droplet IDs already exist: ${ids}")?
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
			match provision_created!(auth, droplet, name, ssh_key_id, model_key, operation_tag) {
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
	if payment.status != "settled"
		or payment.amountSats != Everpaid.machine_price_sats
			or !Everpaid.reference_matches_machine(payment.reference, name) {
		Err(PaymentNotAuthorized)
	} else {
		consumed = Path.utf8(".aion/payments/${name}.consumed")
		Path.create_all!(Path.utf8(".aion/payments"))?
		Path.create_dir!(consumed)?
		Path.write_utf8!(Path.join(consumed, "payment-id"), payment_id)?
		create!(name, Bool.True)
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

image_status! = || {
	id = if AionState.has_saved_image!()? {
		image = AionState.read_image!()?
		image.id
	} else {
		AionState.read_pending_image_id!()?
	}
	image = DigitalOceanApi.get_image!(id, token!()?)?
	Stdout.line!("image '${image.name}' (id ${U64.to_str(image.id)}) is ${image.status}")
}

image_delete! = || {
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

main! = |args|
	match args.drop_first(1).map(OsStr.display) {
		["image", "import", url] => image_import!(url)
		["image", "import-local", path] => image_import_local!(Path.utf8(path))
		["image", "status"] => image_status!()
		["image", "delete"] => image_delete!()
		["create", name] => create!(name, Bool.False)
		["create-paid", name] => create_paid!(name)
		["payment-preflight", name] => payment_preflight!(name)
		[name, "shell"] => shell!(name, Bool.False)
		[name, "shell", "pi"] => shell!(name, Bool.True)
		["destroy", name] => destroy!(name)
		_ => Stdout.line!(usage)
	}
