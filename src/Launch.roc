# The kai commands that install a customer's machine. Nothing here touches
# the network.
Launch := [].{
	# The address a dry run plans against, from TEST-NET-3 (RFC 5737).
	example_address = "203.0.113.7"

	install_argv : Str, Str -> List(Str)
	install_argv = |machine, address| ["--yes", "machine", "install", machine, "--to", "root@${address}"]

	dry_install_argv : Str, Str -> List(Str)
	dry_install_argv = |machine, address| ["--dry-run", "machine", "install", machine, "--to", "root@${address}"]
}
