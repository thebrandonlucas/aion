# Pure planning for `aion launch`: a launch's aion/ inputs, the kai commands
# it runs and the names it derives. Nothing here touches the network.
Launch := [].{
	default_region = "nyc3"

	# nixos-anywhere boots its installer into memory, which needs about 1 GB.
	default_size = "s-1vcpu-2gb"

	# Any Linux works; kai replaces it with the recipe's NixOS.
	base_image = "ubuntu-24-04-x64"

	# The address a dry run plans against, from TEST-NET-3 (RFC 5737).
	example_address = "203.0.113.7"

	# Recipes check on their own with this domain until the address is known.
	placeholder_domain = "aion.invalid"

	Inputs : { name : Str, root_keys : List(Str), operators : List(Str), domain : Str }

	# A name sslip.io resolves to `address`, so Caddy can get a certificate
	# for a fresh droplet with no DNS API: 203.0.113.7 -> 203-0-113-7.sslip.io.
	sslip_domain : Str -> Str
	sslip_domain = |address| "${Str.join_with(address.split_on("."), "-")}.sslip.io"

	lines = |values| Str.join_with(values, "\n").concat("\n")

	# The files a recipe's Kaifile imports, relative to the instance.
	input_files : Inputs -> List((Str, Str))
	input_files = |inputs| [
		("aion/name", "${inputs.name}\n"),
		("aion/root-keys", lines(inputs.root_keys)),
		("aion/operators", lines(inputs.operators)),
		("aion/domain", "${inputs.domain}\n"),
	]

	# The customer's key and the operator's, once each: the operator keeps
	# root access so `aion update` can switch the machine.
	root_keys : Str, Str -> List(Str)
	root_keys = |customer, operator| if (customer == operator) [operator] else [customer, operator]

	install_argv : Str, Str -> List(Str)
	install_argv = |machine, address| ["--yes", "machine", "install", machine, "--to", "root@${address}"]

	dry_install_argv : Str, Str -> List(Str)
	dry_install_argv = |machine, address| ["--dry-run", "machine", "install", machine, "--to", "root@${address}"]

	switch_argv : Str, Str -> List(Str)
	switch_argv = |machine, address| ["--yes", "machine", "switch", machine, "--to", "root@${address}"]
}
