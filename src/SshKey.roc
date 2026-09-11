SshKey := [].{
	canonical = |submitted| {
		key = submitted.trim()
		parts = key.split_on(" ").keep_if(|part| !part.is_empty())
		match parts {
			["ssh-ed25519", encoded, ..] if key.to_utf8().len() <= 1024
				and !key.contains("\n")
					and !key.contains("\r")
						and encoded.to_utf8().len() >= 16
							and encoded.to_utf8().all(is_base64_byte) => Ok("ssh-ed25519 ${encoded}")
			_ => Err(InvalidSshPublicKey("paste one ssh-ed25519 public key, not a private key"))
		}
	}

	is_base64_byte = |byte|
		(byte >= 'a' and byte <= 'z')
			or (byte >= 'A' and byte <= 'Z')
				or (byte >= '0' and byte <= '9')
					or byte == '+'
						or byte == '/'
							or byte == '='
}
