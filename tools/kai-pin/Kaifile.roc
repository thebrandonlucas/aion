# Builds the kai aion uses: the machine PR stack (kai#489 and below) at the
# commit `pin` names, with patches/ applied, until it merges and is
# released. Run with the v0.0.11 release kai, whose platform kai's own
# Kaifile.roc names:
#
#   nix run github:thebrandonlucas/kai/261825dc5ec439071c7c3bd15c0b2a40e3236379 \
#     -- -f tools/kai-pin/Kaifile.roc workflow pin-kai
#
# from the repository root. It leaves the checkout in .kai-pin/kai, whose
# platform, std and machine plugin recipes name by relative path, and the
# binary at .kai-pin/kai-bin/kai.
app [kaifile] {
	pf: platform "https://github.com/thebrandonlucas/kai/releases/download/v0.0.11/65bk6qdahqxn1mm6LR6Hkyw8dSdoeRZGwjNSuiPfvguP.tar.zst",
	std: "https://github.com/thebrandonlucas/kai/releases/download/v0.0.11/std-6Jw5GxNCFkpnvBbnFmQg4KAVEn5bAfEveSZfDSzTDs42.tar.zst",
}

import std.Std

pin = "1a307ed120a92f088f5fc7ba5988d7987a213a30"

checkout = "../../.kai-pin/kai"

# The v0.0.11 release kai, which builds kai from its own Kaifile.roc.
release_kai = [
	"nix",
	"run",
	"github:thebrandonlucas/kai/261825dc5ec439071c7c3bd15c0b2a40e3236379",
	"--",
	"-f",
	"${checkout}/Kaifile.roc",
]

git = |arguments| ["git", "-C", checkout].concat(arguments)

kaifile = Std.kaifile([
	Name("aion-bootstrap"),
	Environment("pin", [Tools(["git", "nix"])]),
	Task("kai-init", [Use("pin"), Run(["git", "init", "-q", checkout])]),
	Task(
		"kai-fetch",
		[
			Use("pin"),
			Run(git(["fetch", "-q", "--depth", "1", "https://github.com/thebrandonlucas/kai.git", pin])),
		],
	),
	Task(
		"kai-checkout",
		[Use("pin"), Run(git(["-c", "advice.detachedHead=false", "checkout", "-q", "--force", "--detach", pin]))],
	),
	# kai#463 gaps aion needs fixed before the stack merges; see kai-issues/028.
	Task("kai-patch", [Use("pin"), Run(git(["apply", "../../tools/kai-pin/patches/remote-machines.patch"]))]),
	# The platform host the checkout's platform/main.roc links Kaifiles with.
	Task(
		"kai-platform",
		[
			Use("pin"),
			Run(
				release_kai.concat([
					"shell",
					"default",
					"--",
					"sh",
					"-c",
					"cd platform && zig build --release && cd targets && sha256sum --quiet -c x64musl.sha256",
				]),
			),
		],
	),
	Task(
		"kai-binary",
		[Use("pin"), Run(release_kai.concat(["--yes", "build", "kai-x64musl", "--out-link", "../../.kai-pin/kai-bin"]))],
	),
	Workflow(
		"pin-kai",
		[
			RunTask("kai-init", []),
			RunTask("kai-fetch", []),
			RunTask("kai-checkout", []),
			RunTask("kai-patch", []),
			RunTask("kai-platform", []),
			RunTask("kai-binary", []),
		],
	),
])
