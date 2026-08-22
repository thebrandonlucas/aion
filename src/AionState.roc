# Local non-secret machine state under .aion/ (git-ignored).
import pf.Path

AionState := [].{
	ImageState : { id : U64, name : Str }
	MachineState : { id : U64, ip : Str, name : Str, ssh_key_id : U64 }

	image_path = Path.utf8(".aion/image.json")

	machine_path = |name| Path.utf8(".aion/machines/${name}.json")

	has_image! = || Path.exists!(image_path)

	read_image! = || {
		decoded : Try(ImageState, _)
		decoded = Json.parse(Path.read_utf8!(image_path)?)
		match decoded {
			Ok(state) => Ok(state)
			Err(_) => Err(InvalidImageState)
		}
	}

	save_image! = |state| {
		Path.create_all!(Path.utf8(".aion"))?
		Path.write_utf8!(image_path, Json.to_str(state))
	}

	read_machine! = |name| {
		decoded : Try(MachineState, _)
		decoded = Json.parse(Path.read_utf8!(machine_path(name))?)
		match decoded {
			Ok(state) => Ok(state)
			Err(_) => Err(InvalidMachineState)
		}
	}

	save_machine! = |state| {
		Path.create_all!(Path.utf8(".aion/machines"))?
		Path.write_utf8!(machine_path(state.name), Json.to_str(state))
	}

	delete_machine! = |name| Path.delete!(machine_path(name))
}
