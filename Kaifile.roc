# aion's own tools, on kai 0.0.13: the Roc compiler and what a launch runs
# beside kai. `kai run build` builds ./aion.
#
# Testing without DigitalOcean: `kai run mock-digitalocean` serves a mock
# API on 127.0.0.1:8090, and `kai build ubuntu-image --out-link
# .aion/ubuntu-image` then `kai run vm-start` boot a local VM from the
# droplet base image; see tools/mock-digitalocean and tools/vm.
app [kaifile] {
	pf: platform "https://github.com/thebrandonlucas/kai/releases/download/v0.0.13/6T3kaftw9oSnAgw4KkodsGVhroQvVb2LZnxRZCqsWKek.tar.zst",
	std: "https://github.com/thebrandonlucas/kai/releases/download/v0.0.13/std-H7SpbnSTMkdUqJjSYVqXiKRqQUmefutvMTC81Rv2ZYjo.tar.zst",
}

import std.Std

build = ["roc", "build", "src/aion.roc", "--opt=size", "--output=aion"]

roc = |tool| ["roc", "tools/${tool}/main.roc", "--"]

# The base image aion creates droplets from, Ubuntu 24.04, for the test VM.
ubuntu = "https://cloud-images.ubuntu.com/noble/20261017/noble-server-cloudimg-amd64.img"

kaifile = Std.kaifile([
	Name("aion"),
	Overlay("roc", "github:roc-lang/roc-overlay/0563d2a0ba55a751449c54058328832309b0f3a1"),
	FetchAll("ubuntu-noble", { url: ubuntu, sha256: "04e8f2461a16a44e78a370284471f29616cdd9baf1893df25807b71f985b6c94" }),
	Environment(
		"cli",
		[
			Overlays(["roc"]),
			Tools(["rocpkgs.nightly-2026-10-21-5349569", "llvmPackages.bintools", "nix", "openssh"]),
		],
	),
	Environment("vm", [Overlays(["roc"]), Tools(["rocpkgs.nightly-2026-10-21-5349569", "qemu_kvm", "cloud-utils", "coreutils"])]),
	Task("build", [Use("cli"), Run(build)]),
	Task("check", [Use("cli"), Run(["roc", "check", "src/aion.roc"])]),
	# An unoptimized aion, for trying a change: `kai run dev customer list`.
	Task("dev", [Use("cli"), Run(["roc", "src/aion.roc", "--"])]),
	Task(
		"format",
		[
			Use("cli"),
			Run(["roc", "fmt", "src/aion.roc", "src/Instance.roc", "src/Launch.roc", "src/DigitalOcean.roc", "src/DigitalOceanApi.roc", "tools/mock-digitalocean/main.roc", "tools/vm/main.roc"]),
		],
	),
	Task("mock-digitalocean", [Use("cli"), Run(roc("mock-digitalocean"))]),
	# The image, copied out of the store so qemu can use it as a backing file.
	Build("ubuntu-image", [Use("vm"), Inputs(["ubuntu-noble"]), Run(["sh", "-c", "cp --no-preserve=mode \"$KAI_INPUTS/ubuntu-noble\" image.img"]), Output("image.img")]),
	Task("vm-start", [Use("vm"), Run(roc("vm").concat(["start", ".aion/ubuntu-image"]))]),
	Task("vm-stop", [Use("vm"), Run(roc("vm").concat(["stop"]))]),
])
