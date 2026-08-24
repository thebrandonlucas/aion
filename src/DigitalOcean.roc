# Pure DigitalOcean API JSON models and helpers.
DigitalOcean := [].{
	Image : { id : U64, name : Str, status : Str }
	ImageResponse : { image : Image }
	ImagesResponse : { images : List(Image) }

	SshKey : { id : U64, public_key : Str }
	SshKeyResponse : { ssh_key : SshKey }
	SshKeysResponse : { ssh_keys : List(SshKey) }

	Network : { ip_address : Str, type : Str }
	Droplet : { id : U64, name : Str, networks : { v4 : List(Network) }, status : Str }
	DropletResponse : { droplet : Droplet }
	DropletsResponse : { droplets : List(Droplet) }

	image_import_body : Str, Str -> { distribution : Str, name : Str, region : Str, tags : List(Str), url : Str }
	image_import_body = |url, operation_tag|
		{ distribution: "NixOS", name: operation_tag, region: "nyc3", tags: ["aion", operation_tag], url }

	droplet_create_body : Str, U64, U64, Str -> { image : U64, name : Str, region : Str, size : Str, ssh_keys : List(U64), tags : List(Str) }
	droplet_create_body = |name, image_id, ssh_key_id, operation_tag|
		{ image: image_id, name, region: "nyc3", size: "s-2vcpu-4gb", ssh_keys: [ssh_key_id], tags: ["aion", operation_tag] }

	public_ipv4 : Droplet -> Try(Str, [NoPublicIpv4])
	public_ipv4 = |droplet|
		match droplet.networks.v4.keep_if(|network| network.type == "public") {
			[first, ..] => Ok(first.ip_address)
			[] => Err(NoPublicIpv4)
		}
}
