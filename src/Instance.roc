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
		kaifile = Path.join(target, "Kaifile.roc")
		Path.write_utf8!(kaifile, Launch.instance_kaifile(Path.read_utf8!(kaifile)?))?
		profiles = Path.join(target, "profiles")
		Path.create_all!(profiles)?
		Path.copy!(profile, Path.join(profiles, profile_file))?
		for (relative, content) in Launch.input_files(inputs) {
			Path.write_utf8!(Path.join(target, relative), content)?
		}
		Ok({})
	}
}
