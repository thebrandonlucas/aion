# Local non-secret machine state under .aion/ (git-ignored).
import pf.Path

AionState := [].{
	ImageState : { id : U64, name : Str, operation_tag : Str }
	MachineState : { id : U64, ip : Str, name : Str, operation_tag : Str, operator_ssh_access : Bool, ssh_key_id : U64 }
	PreviousMachineState : { id : U64, ip : Str, name : Str, operation_tag : Str, ssh_key_id : U64 }
	LegacyImageState : { id : U64, name : Str }
	LegacyMachineState : { id : U64, ip : Str, name : Str, ssh_key_id : U64 }
	ProjectImageState : { image : Str, machine : Str, project : Str }

	image_path = Path.utf8(".aion/image.json")

	project_image_path = Path.utf8(".aion/project-image.json")

	image_import_path = Path.utf8(".aion/image.pending")

	image_operation_path = Path.utf8(".aion/image.operation")

	machine_directory = Path.utf8(".aion/machines")

	machine_path = |name| Path.join(machine_directory, "${name}.json")

	creation_path = Path.utf8(".aion/create.pending")

	payment_reservation_path = Path.utf8(".aion/payments/reservation/machine")

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

	read_pending_image_operation_tag! = || {
		operation_tag = Path.read_utf8!(Path.join(image_import_path, "operation-tag"))?.trim()
		if operation_tag.is_empty() Err(InvalidPendingImageState) else Ok(operation_tag)
	}

	has_pending_image! = || Path.is_dir!(image_import_path)

	begin_image_operation! = || {
		Path.create_all!(Path.utf8(".aion"))?
		Path.create_dir!(image_operation_path)
	}

	has_image_operation! = || Path.is_dir!(image_operation_path)

	clear_image_operation! = || Path.delete_all!(image_operation_path)

	read_pending_image_status! = || Path.read_utf8!(Path.join(image_import_path, "status"))

	clear_image_import! = || Path.delete_all!(image_import_path)

	has_saved_machine! = |name| Path.exists!(machine_path(name))

	has_machine! = |name| {
		if has_saved_machine!(name)? {
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

	record_creation_access! = |operator_ssh_access, ssh_key_id| {
		write_creation_file!("operator-ssh-access", if operator_ssh_access "true" else "false")?
		write_creation_file!("ssh-key-id", U64.to_str(ssh_key_id))
	}

	record_created! = |droplet_id| {
		write_creation_file!("droplet-id", U64.to_str(droplet_id))?
		record_creation_status!("Droplet ID ${U64.to_str(droplet_id)}\n")
	}

	has_pending_creation! = || Path.is_dir!(creation_path)

	read_pending_creation_name! = || {
		name = Path.read_utf8!(Path.join(creation_path, "name"))?.trim()
		if name.is_empty() Err(InvalidPendingCreationState) else Ok(name)
	}

	read_pending_creation_id! = || {
		text = Path.read_utf8!(Path.join(creation_path, "droplet-id"))?
		match U64.from_str(text) {
			Ok(id) => Ok(id)
			Err(_) => Err(InvalidPendingCreationState)
		}
	}

	read_pending_creation_operation_tag! = || {
		operation_tag = Path.read_utf8!(Path.join(creation_path, "operation-tag"))?.trim()
		if operation_tag.is_empty() Err(InvalidPendingCreationState) else Ok(operation_tag)
	}

	has_pending_creation_access! = || {
		has_operator = Path.is_file!(Path.join(creation_path, "operator-ssh-access"))?
		has_key = Path.is_file!(Path.join(creation_path, "ssh-key-id"))?
		if has_operator == has_key Ok(has_operator) else Err(InvalidPendingCreationState)
	}

	read_pending_creation_access! = || {
		operator = Path.read_utf8!(Path.join(creation_path, "operator-ssh-access"))?.trim()
		ssh_key_id = U64.from_str(Path.read_utf8!(Path.join(creation_path, "ssh-key-id"))?.trim())?
		match operator {
			"true" => Ok({ operator_ssh_access: Bool.True, ssh_key_id })
			"false" => Ok({ operator_ssh_access: Bool.False, ssh_key_id })
			_ => Err(InvalidPendingCreationState)
		}
	}

	read_pending_creation_status! = || Path.read_utf8!(Path.join(creation_path, "status"))

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
		temporary = Path.utf8(".aion/image.json.new")
		Path.write_utf8!(temporary, Json.to_str(state))?
		Path.rename!(temporary, image_path)
	}

	decode_machine = |text| {
		decoded : Try(MachineState, _)
		decoded = Json.parse(text)
		match decoded {
			Ok(state) => Ok(state)
			Err(_) => {
				previous : Try(PreviousMachineState, _)
				previous = Json.parse(text)
				match previous {
					Ok(state) => Ok({ id: state.id, ip: state.ip, name: state.name, operation_tag: state.operation_tag, operator_ssh_access: Bool.True, ssh_key_id: state.ssh_key_id })
					Err(_) => {
						legacy : Try(LegacyMachineState, _)
						legacy = Json.parse(text)
						match legacy {
							Ok(state) => Ok({ id: state.id, ip: state.ip, name: state.name, operation_tag: "legacy-unknown", operator_ssh_access: Bool.True, ssh_key_id: state.ssh_key_id })
							Err(_) => Err(InvalidMachineState)
						}
					}
				}
			}
		}
	}

	read_machine! = |name| decode_machine(Path.read_utf8!(machine_path(name))?)

	read_machine_paths! = |paths|
		match paths {
			[] => Ok([])
			[first, .. as rest] => {
				filename = Path.filename(first).map_ok(Path.display) ?? ""
				remaining = read_machine_paths!(rest)?
				if !filename.ends_with(".json") {
					Ok(remaining)
				} else {
					name = Str.from_utf8_lossy(filename.to_utf8().drop_last(5))
					snapshot = match Path.read_utf8!(first) {
						Err(_) => InvalidMachine(name)
						Ok(text) => match decode_machine(text) {
							Err(_) => InvalidMachine(name)
							Ok(state) if state.name == name => SavedMachine(state)
							Ok(_) => InvalidMachine(name)
						}
					}
					Ok([snapshot].concat(remaining))
				}
			}
		}

	read_machines! = ||
		if Path.is_dir!(machine_directory)? {
			read_machine_paths!(Path.list!(machine_directory)?)
		} else {
			Ok([])
		}

	save_machine! : MachineState => Try({}, _)
	save_machine! = |state| {
		Path.create_all!(Path.utf8(".aion/machines"))?
		Path.write_utf8!(machine_path(state.name), Json.to_str(state))
	}

	delete_image! = || {
		Path.delete!(image_path)?
		if Path.exists!(project_image_path)? Path.delete!(project_image_path) else Ok({})
	}

	save_project_image! = |state| Path.write_utf8!(project_image_path, Json.to_str(state))

	has_project_image! = || Path.is_file!(project_image_path)

	read_project_image! : () => Try(ProjectImageState, _)
	read_project_image! = || Json.parse(Path.read_utf8!(project_image_path)?)

	read_payment_reservation! = ||
		if Path.is_file!(payment_reservation_path)? {
			Ok(Some(Path.read_utf8!(payment_reservation_path)?.trim()))
		} else {
			Ok(None)
		}

	delete_machine! = |name| Path.delete!(machine_path(name))
}
