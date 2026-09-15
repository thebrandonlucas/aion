# Local non-secret machine state under .aion/ (git-ignored).
import pf.Path

AionState := [].{
	ImageState : { id : U64, name : Str, operation_tag : Str, region : Str, ssh_user : Str }
	RegionImageState : { id : U64, name : Str, operation_tag : Str, region : Str }
	PreviousImageState : { id : U64, name : Str, operation_tag : Str }
	LegacyImageState : { id : U64, name : Str }
	MachineState : { id : U64, ip : Str, machine : Str, name : Str, operation_tag : Str, operator_ssh_access : Bool, project : Str, region : Str, size : Str, ssh_key_id : U64, ssh_user : Str }
	ProvenanceMachineState : { id : U64, ip : Str, machine : Str, name : Str, operation_tag : Str, operator_ssh_access : Bool, project : Str, region : Str, size : Str, ssh_key_id : U64 }
	ProviderMachineState : { id : U64, ip : Str, name : Str, operation_tag : Str, operator_ssh_access : Bool, region : Str, size : Str, ssh_key_id : U64 }
	PreviousMachineState : { id : U64, ip : Str, name : Str, operation_tag : Str, operator_ssh_access : Bool, ssh_key_id : U64 }
	EarlierMachineState : { id : U64, ip : Str, name : Str, operation_tag : Str, ssh_key_id : U64 }
	LegacyMachineState : { id : U64, ip : Str, name : Str, ssh_key_id : U64 }

	image_path = Path.utf8(".aion/image.json")

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

	begin_image_import! = |operation_tag, region, status| {
		Path.create_all!(Path.utf8(".aion"))?
		Path.create_dir!(image_import_path)?
		if Path.exists!(image_path)? {
			Path.delete_all!(image_import_path) ?? {}
			Err(ImageAlreadyExists)
		} else {
			write_import_file!("operation-tag", operation_tag)?
			write_import_file!("region", region)?
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

	has_pending_image_region! = || Path.is_file!(Path.join(image_import_path, "region"))

	read_pending_image_region! = || {
		path = Path.join(image_import_path, "region")
		if Path.is_file!(path)? {
			region = Path.read_utf8!(path)?.trim()
			if region.is_empty() Err(InvalidPendingImageState) else Ok(region)
		} else {
			Ok("nyc3")
		}
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

	begin_creation! = |name, operation_tag, project, provision_agent, provision_recipe, region, size| {
		Path.create_all!(Path.utf8(".aion/machines"))?
		# Directory creation is atomic, so concurrent local creates cannot POST.
		Path.create_dir!(creation_path)?
		if Path.exists!(machine_path(name))? {
			Path.delete_all!(creation_path) ?? {}
			Err(MachineAlreadyExists("saved machine state appeared while acquiring the create guard"))
		} else {
			write_creation_file!("name", name)?
			write_creation_file!("operation-tag", operation_tag)?
			match project {
				Some(selected) => {
					write_creation_file!("project", selected.path)?
					write_creation_file!("machine", selected.machine)?
					write_creation_file!("closure-path", selected.closure)?
					write_creation_file!("provision-agent", if provision_agent "true" else "false")?
					write_creation_file!("provision-recipe", if provision_recipe "true" else "false")?
				}
				None => {}
			}
			write_creation_file!("region", region)?
			write_creation_file!("size", size)?
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

	read_pending_creation_project! = || {
		project = Path.read_utf8!(Path.join(creation_path, "project"))?.trim()
		if project.starts_with("/") and !project.contains("\n") {
			Ok(project)
		} else {
			Err(InvalidPendingCreationState)
		}
	}

	read_pending_creation_machine! = || {
		machine = Path.read_utf8!(Path.join(creation_path, "machine"))?.trim()
		if machine.is_empty() Err(InvalidPendingCreationState) else Ok(machine)
	}

	read_pending_creation_closure! = || {
		closure = Path.read_utf8!(Path.join(creation_path, "closure-path"))?.trim()
		if closure.starts_with("/nix/store/") and !closure.contains("\n") {
			Ok(closure)
		} else {
			Err(InvalidPendingCreationState)
		}
	}

	read_pending_creation_provision_agent! = ||
		match Path.read_utf8!(Path.join(creation_path, "provision-agent"))?.trim() {
			"true" => Ok(Bool.True)
			"false" => Ok(Bool.False)
			_ => Err(InvalidPendingCreationState)
		}

	read_pending_creation_provision_recipe! = || {
		path = Path.join(creation_path, "provision-recipe")
		if Path.is_file!(path)? {
			match Path.read_utf8!(path)?.trim() {
				"true" => Ok(Bool.True)
				"false" => Ok(Bool.False)
				_ => Err(InvalidPendingCreationState)
			}
		} else {
			Ok(Bool.False)
		}
	}

	has_pending_creation_project! = || {
		has_project = Path.is_file!(Path.join(creation_path, "project"))?
		has_machine = Path.is_file!(Path.join(creation_path, "machine"))?
		has_provision = Path.is_file!(Path.join(creation_path, "provision-agent"))?
		if has_project == has_machine and has_machine == has_provision Ok(has_project) else Err(InvalidPendingCreationState)
	}

	has_pending_creation_closure! = ||
		Path.is_file!(Path.join(creation_path, "closure-path"))

	read_pending_creation_provider! = || {
		region = Path.read_utf8!(Path.join(creation_path, "region"))?.trim()
		size = Path.read_utf8!(Path.join(creation_path, "size"))?.trim()
		if region.is_empty() or size.is_empty() Err(InvalidPendingCreationState) else Ok({ region, size })
	}

	has_pending_creation_provider! = || {
		has_region = Path.is_file!(Path.join(creation_path, "region"))?
		has_size = Path.is_file!(Path.join(creation_path, "size"))?
		if has_region == has_size Ok(has_region) else Err(InvalidPendingCreationState)
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
				regional : Try(RegionImageState, _)
				regional = Json.parse(text)
				match regional {
					Ok(state) => Ok({ id: state.id, name: state.name, operation_tag: state.operation_tag, region: state.region, ssh_user: "root" })
					Err(_) => {
						previous : Try(PreviousImageState, _)
						previous = Json.parse(text)
						match previous {
							Ok(state) => Ok({ id: state.id, name: state.name, operation_tag: state.operation_tag, region: "nyc3", ssh_user: "aion" })
							Err(_) => {
								legacy : Try(LegacyImageState, _)
								legacy = Json.parse(text)
								match legacy {
									Ok(state) => Ok({ id: state.id, name: state.name, operation_tag: "legacy-unknown", region: "nyc3", ssh_user: "aion" })
									Err(_) => Err(InvalidImageState)
								}
							}
						}
					}
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
				provenance : Try(ProvenanceMachineState, _)
				provenance = Json.parse(text)
				match provenance {
					Ok(state) => Ok({ id: state.id, ip: state.ip, machine: state.machine, name: state.name, operation_tag: state.operation_tag, operator_ssh_access: state.operator_ssh_access, project: state.project, region: state.region, size: state.size, ssh_key_id: state.ssh_key_id, ssh_user: "root" })
					Err(_) => {
						provider : Try(ProviderMachineState, _)
						provider = Json.parse(text)
						match provider {
							Ok(state) => Ok({ id: state.id, ip: state.ip, machine: "", name: state.name, operation_tag: state.operation_tag, operator_ssh_access: state.operator_ssh_access, project: "", region: state.region, size: state.size, ssh_key_id: state.ssh_key_id, ssh_user: "root" })
							Err(_) => {
								previous : Try(PreviousMachineState, _)
								previous = Json.parse(text)
								match previous {
									Ok(state) => Ok({ id: state.id, ip: state.ip, machine: "", name: state.name, operation_tag: state.operation_tag, operator_ssh_access: state.operator_ssh_access, project: "", region: "nyc3", size: "s-2vcpu-4gb", ssh_key_id: state.ssh_key_id, ssh_user: "aion" })
									Err(_) => {
										earlier : Try(EarlierMachineState, _)
										earlier = Json.parse(text)
										match earlier {
											Ok(state) => Ok({ id: state.id, ip: state.ip, machine: "", name: state.name, operation_tag: state.operation_tag, operator_ssh_access: Bool.True, project: "", region: "nyc3", size: "s-2vcpu-4gb", ssh_key_id: state.ssh_key_id, ssh_user: "aion" })
											Err(_) => {
												legacy : Try(LegacyMachineState, _)
												legacy = Json.parse(text)
												match legacy {
													Ok(state) => Ok({ id: state.id, ip: state.ip, machine: "", name: state.name, operation_tag: "legacy-unknown", operator_ssh_access: Bool.True, project: "", region: "nyc3", size: "s-2vcpu-4gb", ssh_key_id: state.ssh_key_id, ssh_user: "aion" })
													Err(_) => Err(InvalidMachineState)
												}
											}
										}
									}
								}
							}
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
		path = machine_path(state.name)
		temporary = Path.join(machine_directory, ".${state.name}.json.new")
		Path.write_utf8!(temporary, Json.to_str(state))?
		Path.rename!(temporary, path)
	}

	delete_image! = || Path.delete!(image_path)

	read_payment_reservation! = ||
		if Path.is_file!(payment_reservation_path)? {
			Ok(Some(Path.read_utf8!(payment_reservation_path)?.trim()))
		} else {
			Ok(None)
		}

	delete_machine! = |name| Path.delete!(machine_path(name))
}
