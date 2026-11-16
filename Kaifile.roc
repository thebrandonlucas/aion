# aion's own tools, on the pinned kai (tools/kai-pin): the Roc compiler kai
# pins and what a launch runs beside kai. `kai run build` builds ./aion, and
# `kai run aion -- launch web demo --dry-run` builds and runs it.
app [kaifile] {
	pf: platform ".kai-pin/kai/platform/main.roc",
	std: ".kai-pin/kai/plugins/std/main.roc",
}

import std.Std

build = ["roc", "build", "src/aion.roc", "--opt=size", "--output=aion"]

kaifile = Std.kaifile([
	Name("aion"),
	Overlay("roc", "github:roc-lang/roc-overlay/0563d2a0ba55a751449c54058328832309b0f3a1"),
	Environment(
		"cli",
		[
			Overlays(["roc"]),
			Tools(["rocpkgs.nightly-2026-10-21-5349569", "llvmPackages.bintools", "nix", "openssh"]),
		],
	),
	Task("build", [Use("cli"), Run(build)]),
	Task("check", [Use("cli"), Run(["roc", "check", "src/aion.roc"])]),
	Task("format", [Use("cli"), Run(["roc", "fmt", "src/aion.roc", "src/Instance.roc", "src/Launch.roc", "src/DigitalOcean.roc"])]),
	Task("aion", [Use("cli"), Run(["./aion"])]),
	Workflow("aion", [RunTask("build", []), RunTask("aion", [])]),
])
