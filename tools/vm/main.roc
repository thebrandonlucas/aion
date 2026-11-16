# A local stand-in for a fresh droplet: DigitalOcean's base image, Ubuntu
# 24.04, under QEMU with KVM, its disk at /dev/vda and root logging in with
# the operator's key over SSH on 127.0.0.1:2222. With an ~/.ssh/config
# alias for that port (kai's --to takes none), `AION_SSH_HOST=aion-vm`
# points a mock launch's install and update at it.
#
#   roc tools/vm/main.roc -- start IMAGE    boot a new VM over IMAGE
#   roc tools/vm/main.roc -- stop           stop it and delete its disk
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.OsStr
import pf.Path
import pf.Stdout

directory = Path.utf8(".aion/vm")

file = |name| Path.display(Path.join(directory, name))

run! = |program, arguments| {
	ran = Cmd.new(OsStr.from_str(program)).args(arguments.map(OsStr.from_str)).inherit_stdio().call!()
	match ran {
		Ok(_) => Ok({})
		Err(_) => Err(CommandFailed(program))
	}
}

user_data = |key|
	Str.join_with(
		[
			"#cloud-config",
			"disable_root: false",
			"ssh_pwauth: false",
			"users:",
			"  - name: root",
			"    ssh_authorized_keys:",
			"      - ${key}",
			"",
		],
		"\n",
	)

start! = |image| {
	home = Env.var_str!(OsStr.from_str("HOME"))?
	key = Path.read_utf8!(Path.join(Path.utf8(home), ".ssh/id_ed25519.pub"))?.trim()
	if Path.exists!(Path.join(directory, "pid"))? {
		return Err(AlreadyRunning("stop the VM first"))
	}
	Path.create_all!(directory)?
	Path.write_utf8!(Path.join(directory, "user-data"), user_data(key))?
	Path.write_utf8!(Path.join(directory, "meta-data"), "instance-id: aion-vm\nlocal-hostname: aion-vm\n")?
	run!("cloud-localds", [file("seed.img"), file("user-data"), file("meta-data")])?
	backing = Path.display(Path.absolute!(Path.utf8(image))?)
	run!("qemu-img", ["create", "-q", "-f", "qcow2", "-F", "qcow2", "-b", backing, file("disk.qcow2"), "20G"])?
	run!(
		"qemu-system-x86_64",
		[
			"-enable-kvm",
			"-cpu",
			"host",
			"-m",
			"2560",
			"-smp",
			"2",
			"-drive",
			"file=${file("disk.qcow2")},if=virtio,format=qcow2",
			"-drive",
			"file=${file("seed.img")},if=virtio,format=raw",
			"-netdev",
			"user,id=net0,hostfwd=tcp:127.0.0.1:2222-:22",
			"-device",
			"virtio-net-pci,netdev=net0",
			"-display",
			"none",
			"-serial",
			"file:${file("console.log")}",
			"-daemonize",
			"-pidfile",
			file("pid"),
		],
	)?
	Stdout.line!("VM booting; console in ${file("console.log")}, SSH on 127.0.0.1:2222")
}

stop! = || {
	pid = Path.read_utf8!(Path.join(directory, "pid"))?.trim()
	run!("kill", [pid])?
	Path.delete_all!(directory)?
	Stdout.line!("stopped VM ${pid} and removed ${Path.display(directory)}")
}

main! = |args|
	match args.map(OsStr.display) {
		["start", image] => start!(image)
		["stop"] => stop!()
		_ => Stdout.line!("Usage: vm start IMAGE | vm stop")
	}
