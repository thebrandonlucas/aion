# Local non-secret machine state under .aion/ (git-ignored).
import pf.Path

AionState := [].{
	ImageState : { id : U64, name : Str, operation_tag : Str }
	MachineState : { id : U64, ip : Str, name : Str, operation_tag : Str, ssh_key_id : U64 }
	LegacyImageState : { id : U64, name : Str }
	LegacyMachineState : { id : U64, ip : Str, name : Str, ssh_key_id : U64 }

	image_path = Path.utf8(".aion/image.json")

	image_import_path = Path.utf8(".aion/image.pending")

	machine_path = |name| Path.utf8(".aion/machines/${name}.json")

	creation_path = Path.utf8(".aion/create.pending")

	has_saved_image! = || Path.exists!(image_path)

	has_image! = || {
		if has_saved_image!()? {
			Ok(Bool.True)
		} else {
			Path.exists!(image_import_path)
		}
	}

	write_import_file! = |name, content| {
		path = Path.join(image_import_path, name)
		temporary = Path.join(image_import_path, "${name}.new")
		Path.write_utf8!(temporary, content)?
		Path.rename!(temporary, path)
	}

	begin_image_import! = |operation_tag, status| {
		Path.create_all!(Path.utf8(".aion"))?
		Path.create_dir!(image_import_path)?
		if Path.exists!(image_path)? {
			Path.delete_all!(image_import_path) ?? {}
			Err(ImageAlreadyExists)
		} else {
			write_import_file!("operation-tag", operation_tag)?
			write_import_file!("status", status)
		}
	}

	record_import_status! = |status| write_import_file!("status", status)

	record_imported! = |image_id, status| {
		write_import_file!("image-id", U64.to_str(image_id))?
		_ = write_import_file!("status", status) ?? {}
		Ok({})
	}

	read_pending_image_id! = || {
		text = Path.read_utf8!(Path.join(image_import_path, "image-id"))?
		match U64.from_str(text) {
			Ok(id) => Ok(id)
			Err(_) => Err(InvalidPendingImageState)
		}
	}

	clear_image_import! = || Path.delete_all!(image_import_path)

	has_machine! = |name| {
		if Path.exists!(machine_path(name))? {
			Ok(Bool.True)
		} else {
			Path.exists!(creation_path)
		}
	}

	write_creation_file! = |name, content| {
		path = Path.join(creation_path, name)
		temporary = Path.join(creation_path, "${name}.new")
		Path.write_utf8!(temporary, content)?
		Path.rename!(temporary, path)
	}

	begin_creation! = |name, operation_tag| {
		Path.create_all!(Path.utf8(".aion/machines"))?
		# Directory creation is atomic, so concurrent local creates cannot POST.
		Path.create_dir!(creation_path)?
		if Path.exists!(machine_path(name))? {
			Path.delete_all!(creation_path) ?? {}
			Err(MachineAlreadyExists("saved machine state appeared while acquiring the create guard"))
		} else {
			write_creation_file!("name", name)?
			write_creation_file!("operation-tag", operation_tag)?
			write_creation_file!("status", "Droplet create POST not yet completed\n")
		}
	}

	record_creation_status! = |status| write_creation_file!("status", status)

	record_created! = |droplet_id|
		record_creation_status!("Droplet ID ${U64.to_str(droplet_id)}\n")

	clear_creation! = || Path.delete_all!(creation_path)

	read_image! = || {
		text = Path.read_utf8!(image_path)?
		decoded : Try(ImageState, _)
		decoded = Json.parse(text)
		match decoded {
			Ok(state) => Ok(state)
			Err(_) => {
				legacy : Try(LegacyImageState, _)
				legacy = Json.parse(text)
				match legacy {
					Ok(state) => Ok({ id: state.id, name: state.name, operation_tag: "legacy-unknown" })
					Err(_) => Err(InvalidImageState)
				}
			}
		}
	}

	save_image! = |state| {
		Path.create_all!(Path.utf8(".aion"))?
		Path.write_utf8!(image_path, Json.to_str(state))
	}

	read_machine! = |name| {
		text = Path.read_utf8!(machine_path(name))?
		decoded : Try(MachineState, _)
		decoded = Json.parse(text)
		match decoded {
			Ok(state) => Ok(state)
			Err(_) => {
				legacy : Try(LegacyMachineState, _)
				legacy = Json.parse(text)
				match legacy {
					Ok(state) => Ok({ id: state.id, ip: state.ip, name: state.name, operation_tag: "legacy-unknown", ssh_key_id: state.ssh_key_id })
					Err(_) => Err(InvalidMachineState)
				}
			}
		}
	}

	save_machine! : MachineState => Try({}, _)
	save_machine! = |state| {
		Path.create_all!(Path.utf8(".aion/machines"))?
		Path.write_utf8!(machine_path(state.name), Json.to_str(state))
	}

	delete_image! = || Path.delete!(image_path)

	delete_machine! = |name| Path.delete!(machine_path(name))
}
