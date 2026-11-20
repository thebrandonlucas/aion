# Pure Vultr API JSON models and request bodies. Only the fields aion reads
# are decoded; a create's `default_password` is never among them.
Vultr := [].{
	default_region = "atl"

	default_plan = "vc2-4c-8gb"

	# Ubuntu 24.04 LTS x64, from GET /v2/os. Any Linux would do: kai's
	# install replaces it.
	ubuntu_os_id : U64
	ubuntu_os_id = 2284

	# A list's cursor to its next page, empty on the last.
	Meta : { links : { next : Str } }

	SshKey : { id : Str, name : Str, ssh_key : Str }
	SshKeyResponse : { ssh_key : SshKey }
	SshKeysResponse : { ssh_keys : List(SshKey), meta : Meta }

	Instance : { id : Str, label : Str, main_ip : Str, plan : Str, region : Str, server_status : Str, status : Str, tags : List(Str) }
	InstanceResponse : { instance : Instance }
	InstancesResponse : { instances : List(Instance), meta : Meta }

	InstanceBody : { activation_email : Bool, backups : Str, enable_ipv6 : Bool, hostname : Str, label : Str, os_id : U64, plan : Str, region : Str, sshkey_id : List(Str), tags : List(Str) }

	# A stock Ubuntu instance that kai then installs the box over, reached
	# as root with `ssh_key_ids`.
	instance_body : Str, Str, Str, List(Str), List(Str) -> InstanceBody
	instance_body = |label, region, plan, ssh_key_ids, tags| {
		activation_email: Bool.False,
		backups: "disabled",
		enable_ipv6: Bool.True,
		hostname: label,
		label,
		os_id: ubuntu_os_id,
		plan,
		region,
		sshkey_id: ssh_key_ids,
		tags,
	}

	# The instance's public IPv4 once Vultr has installed and booted it;
	# until then main_ip is "0.0.0.0".
	ready_address : Instance -> Try(Str, [NotReady])
	ready_address = |instance|
		if instance.status == "active" and instance.server_status == "ok" and instance.main_ip != "0.0.0.0" and !instance.main_ip.is_empty() {
			Ok(instance.main_ip)
		} else {
			Err(NotReady)
		}
}
