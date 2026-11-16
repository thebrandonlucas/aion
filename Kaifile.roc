# aion's own tools, on the pinned kai (tools/kai-pin): the Roc compiler kai
# pins and what a launch runs beside kai. `kai run build` builds ./aion.
#
# Testing without DigitalOcean: `kai run mock-digitalocean` serves a mock
# API on 127.0.0.1:8090; see tools/mock-digitalocean.
app [kaifile] {
	pf: platform ".kai-pin/kai/platform/main.roc",
	std: ".kai-pin/kai/plugins/std/main.roc",
}

import std.Std

build = ["roc", "build", "src/aion.roc", "--opt=size", "--output=aion"]

roc = |tool| ["roc", "tools/${tool}/main.roc", "--"]

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
	Task(
		"format",
		[
			Use("cli"),
			Run(["roc", "fmt", "src/aion.roc", "src/Instance.roc", "src/Launch.roc", "src/DigitalOcean.roc", "src/DigitalOceanApi.roc", "tools/mock-digitalocean/main.roc"]),
		],
	),
	Task("mock-digitalocean", [Use("cli"), Run(roc("mock-digitalocean"))]),
])
