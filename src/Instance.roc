# A launch's project: a copy of its recipe with the provider's profile and
# the aion/ inputs, in .aion/instances/<name>/ (or .aion/plans/<name>/ for a
# dry run). kai runs there, and records the machine's hardware facts and
# host key there, so each launch keeps its own.
import pf.Path

import Launch

Instance := [].{
	directory = |name| Path.join(Path.utf8(".aion/instances"), name)

	plan_directory = |name| Path.join(Path.utf8(".aion/plans"), name)

	# What kai generates or records in a project, which a copy of the recipe
	# must not inherit.
	generated = [".kai/generated", ".kai/kaifile", ".kai/remembered", "machines", "secrets"]

	# Copies `recipe` to `target`, which must not exist, with `profile` at
	# profiles/<file> and `inputs` as the aion/ files.
	stage! : Path.Path, Path.Path, Str, Path.Path, Launch.Inputs => Try({}, _)
	stage! = |recipe, profile, profile_file, target, inputs| {
		Path.copy_dir!(recipe, target)?
		for relative in generated {
			Path.delete_all!(Path.join(target, relative)) ?? {}
		}
		profiles = Path.join(target, "profiles")
		Path.create_all!(profiles)?
		Path.copy!(profile, Path.join(profiles, profile_file))?
		for (relative, content) in Launch.input_files(inputs) {
			Path.write_utf8!(Path.join(target, relative), content)?
		}
		Ok({})
	}

	# What aion knows of a launch, beside its project. `status` is
	# "creating" from just before the droplet POST, "created" once the
	# droplet is active, and "installed" once kai has installed the recipe.
	State : { address : Str, droplet_id : U64, name : Str, operation_tag : Str, recipe : Str, region : Str, size : Str, ssh_key_id : U64, status : Str }

	state_path = |name| Path.join(directory(name), "instance.json")

	save! : State => Try({}, _)
	save! = |state| {
		temporary = Path.join(directory(state.name), "instance.json.new")
		Path.write_utf8!(temporary, Json.to_str(state))?
		Path.rename!(temporary, state_path(state.name))
	}

	read! : Str => Try(State, _)
	read! = |name| {
		decoded : Try(State, _)
		decoded = Json.parse(Path.read_utf8!(state_path(name))?)
		match decoded {
			Ok(state) => Ok(state)
			Err(_) => Err(InvalidInstanceState(name))
		}
	}

	# The names of the launches under .aion/instances.
	names! : () => Try(List(Str), _)
	names! = || {
		root = Path.utf8(".aion/instances")
		if !Path.exists!(root)? {
			return Ok([])
		}
		paths = Path.list!(root)?
		Ok(paths.keep_oks(|path| Path.filename(path).map_ok(Path.display)))
	}
}
