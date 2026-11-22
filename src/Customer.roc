# A customer is a git repository of their own, <clients>/<slug>: a kai
# project copied from kai-box's client skeleton, with the aion/ files its
# Kaifile reads and a record of each machine aion created for it. After
# that it is an ordinary kai project; aion never writes Nix or Roc.
import pf.Path

Customer := [].{
	Inputs : { name : Str, root_keys : List(Str), operators : List(Str), tailnet : Str }

	lines = |values| Str.join_with(values, "\n").concat("\n")

	# The files the customer's Kaifile imports, and the tailnet aion checks
	# it is on before reaching a box, its MagicDNS suffix such as
	# tail1234.ts.net.
	input_files : Inputs -> List((Str, Str))
	input_files = |inputs| [
		("aion/name", "${inputs.name}\n"),
		("aion/root-keys", lines(inputs.root_keys)),
		("aion/operators", lines(inputs.operators)),
		("aion/tailnet", "${inputs.tailnet}\n"),
	]

	# What kai generates or records in a project, which a copy of the
	# skeleton must not inherit. Its .kai/lock.json, the pins the skeleton
	# was checked with, is kept.
	generated = [".kai/generated", ".kai/kaifile", ".kai/remembered", ".kai/machines", "machines", "secrets"]

	# Copies `skeleton` to `directory`, which must not exist, and writes the
	# aion/ files.
	create! : Path.Path, Path.Path, Inputs => Try({}, _)
	create! = |skeleton, directory, inputs| {
		Path.copy_dir!(skeleton, directory)?
		for relative in generated {
			Path.delete_all!(Path.join(directory, relative)) ?? {}
		}
		for (relative, content) in input_files(inputs) {
			Path.write_utf8!(Path.join(directory, relative), content)?
		}
		Ok({})
	}

	tailnet! : Path.Path => Try(Str, _)
	tailnet! = |directory| Ok(Path.read_utf8!(Path.join(directory, "aion/tailnet"))?.trim())

	# What aion knows of a machine it created, committed beside the
	# Kaifile. `status` is "creating" from just before the instance POST,
	# "created" once the instance is active, and "installed" once kai has
	# installed the box.
	Machine : { address : Str, id : Str, machine : Str, operation_tag : Str, plan : Str, region : Str, status : Str }

	machines_directory = |directory| Path.join(directory, "aion/machines")

	machine_path = |directory, machine| Path.join(machines_directory(directory), "${machine}.json")

	save_machine! : Path.Path, Machine => Try({}, _)
	save_machine! = |directory, state| {
		Path.create_all!(machines_directory(directory))?
		temporary = Path.join(machines_directory(directory), "${state.machine}.json.new")
		Path.write_utf8!(temporary, Json.to_str(state))?
		Path.rename!(temporary, machine_path(directory, state.machine))
	}

	read_machine! : Path.Path, Str => Try(Machine, _)
	read_machine! = |directory, machine| {
		decoded : Try(Machine, _)
		decoded = Json.parse(Path.read_utf8!(machine_path(directory, machine))?)
		match decoded {
			Ok(state) => Ok(state)
			Err(_) => Err(InvalidMachineState(machine))
		}
	}

	forget_machine! : Path.Path, Str => Try({}, _)
	forget_machine! = |directory, machine| Path.delete!(machine_path(directory, machine))

	# The file names in `directory`, none if it is missing.
	names_in! = |directory| {
		if !Path.exists!(directory)? {
			return Ok([])
		}
		paths = Path.list!(directory)?
		Ok(paths.keep_oks(|path| Path.filename(path).map_ok(Path.display)))
	}

	machine_names! : Path.Path => Try(List(Str), _)
	machine_names! = |directory|
		Ok(names_in!(machines_directory(directory))?.keep_if(|file| file.ends_with(".json")).map(|file| file.drop_suffix(".json")))

	names! : Path.Path => Try(List(Str), _)
	names! = |root| names_in!(root)
}
