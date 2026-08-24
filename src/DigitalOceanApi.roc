# HTTPS effects against the DigitalOcean API. Error values carry the failed
# operation and status code only; response bodies are never printed.
import pf.Http
import http.Request
import http.Response

import DigitalOcean

DigitalOceanApi := [].{
	SshKeyResult : [RegisteredKey(DigitalOcean.SshKey), ReusedKey(DigitalOcean.SshKey)]

	request = |method, path, token|
		Request.from_method(method)
			.with_uri("https://api.digitalocean.com${path}")
			.with_timeout(TimeoutMilliseconds(30000))
			.add_header("Authorization", "Bearer ${token}")
			.add_header("Content-Type", "application/json")
			.add_header("User-Agent", "aion")

	unexpected = |operation, response|
		Err(UnexpectedStatus({ operation, status: Response.status(response) }))

	decode_image! = |response| {
		decoded : Try(DigitalOcean.ImageResponse, _)
		decoded = Http.decode_json_response(response)
		match decoded {
			Ok(wrapper) => Ok(wrapper.image)
			Err(error) => Err(error)
		}
	}

	decode_images! = |response| {
		decoded : Try(DigitalOcean.ImagesResponse, _)
		decoded = Http.decode_json_response(response)
		match decoded {
			Ok(wrapper) => Ok(wrapper.images)
			Err(error) => Err(error)
		}
	}

	decode_droplet! = |response| {
		decoded : Try(DigitalOcean.DropletResponse, _)
		decoded = Http.decode_json_response(response)
		match decoded {
			Ok(wrapper) => Ok(wrapper.droplet)
			Err(error) => Err(error)
		}
	}

	decode_droplets! = |response| {
		decoded : Try(DigitalOcean.DropletsResponse, _)
		decoded = Http.decode_json_response(response)
		match decoded {
			Ok(wrapper) => Ok(wrapper.droplets)
			Err(error) => Err(error)
		}
	}

	decode_ssh_keys! = |response| {
		decoded : Try(DigitalOcean.SshKeysResponse, _)
		decoded = Http.decode_json_response(response)
		match decoded {
			Ok(wrapper) => Ok(wrapper.ssh_keys)
			Err(error) => Err(error)
		}
	}

	# Billable POSTs are deliberately single-attempt. Only 4xx responses are
	# definitive rejections; transport failures, other statuses, and accepted-
	# response decode failures are uncertain.
	import_image_once! = |url, operation_tag, token| {
		match Http.send_json!(request(POST, "/v2/images", token), DigitalOcean.image_import_body(url, operation_tag)) {
			Err(error) => PostUncertain(error)
			Ok(response) => {
				status = Response.status(response)
				if status == 202 {
					match decode_image!(response) {
						Ok(image) => PostAccepted(image)
						Err(error) => PostUncertain(error)
					}
				} else if status >= 400 and status <= 499 {
					PostRejected(UnexpectedStatus({ operation: "import image", status }))
				} else {
					PostUncertain(UnexpectedStatus({ operation: "import image", status }))
				}
			}
		}
	}

	list_private_images_by_tag! = |tag, token| {
		response = Http.send!(request(GET, "/v2/images?tag_name=${tag}&private=true&per_page=200", token))?
		if Response.status(response) == 200 {
			decode_images!(response)
		} else {
			unexpected("list private images by operation tag", response)
		}
	}

	get_image! = |id, token| {
		response = Http.send!(request(GET, "/v2/images/${U64.to_str(id)}", token))?
		if Response.status(response) == 200 {
			decode_image!(response)
		} else {
			unexpected("get image", response)
		}
	}

	delete_image! = |id, token| {
		response = Http.send!(request(DELETE, "/v2/images/${U64.to_str(id)}", token))?
		# Only this account confirming deletion can release local state. A 404 may
		# mean that the operator supplied a token for the wrong account.
		if Response.status(response) == 204 {
			Ok({})
		} else {
			unexpected("delete image ${U64.to_str(id)}", response)
		}
	}

	register_ssh_key! = |name, public_key, token| {
		body : { name : Str, public_key : Str }
		body = { name, public_key }
		response = Http.send_json!(request(POST, "/v2/ssh_keys", token), body)?
		match Response.status(response) {
			201 => {
				decoded : Try(DigitalOcean.SshKeyResponse, _)
				decoded = Http.decode_json_response(response)
				match decoded {
					Ok(wrapper) => Ok(RegisteredKey(wrapper.ssh_key))
					Err(error) => Err(error)
				}
			}
			422 => {
				list = Http.send!(request(GET, "/v2/ssh_keys", token))?
				if Response.status(list) != 200 {
					return unexpected("list ssh keys", list)
				}
				keys = decode_ssh_keys!(list)?
				match keys.keep_if(|key| key.public_key.trim() == public_key.trim()) {
					[found, ..] => Ok(ReusedKey(found))
					[] => Err(NoMatchingSshKey)
				}
			}
			_ => unexpected("register ssh key", response)
		}
	}

	create_droplet_once! = |name, image_id, ssh_key_id, operation_tag, token| {
		body = DigitalOcean.droplet_create_body(name, image_id, ssh_key_id, operation_tag)
		match Http.send_json!(request(POST, "/v2/droplets", token), body) {
			Err(error) => PostUncertain(error)
			Ok(response) => {
				status = Response.status(response)
				if status == 202 {
					match decode_droplet!(response) {
						Ok(droplet) => PostAccepted(droplet)
						Err(error) => PostUncertain(error)
					}
				} else if status >= 400 and status <= 499 {
					PostRejected(UnexpectedStatus({ operation: "create droplet", status }))
				} else {
					PostUncertain(UnexpectedStatus({ operation: "create droplet", status }))
				}
			}
		}
	}

	list_droplets_by_tag! = |tag, token| {
		response = Http.send!(request(GET, "/v2/droplets?tag_name=${tag}&per_page=200", token))?
		if Response.status(response) == 200 {
			decode_droplets!(response)
		} else {
			unexpected("list droplets by tag", response)
		}
	}

	get_droplet! = |id, token| {
		response = Http.send!(request(GET, "/v2/droplets/${U64.to_str(id)}", token))?
		if Response.status(response) == 200 {
			decode_droplet!(response)
		} else {
			unexpected("get droplet", response)
		}
	}

	delete_droplet! = |id, token| {
		response = Http.send!(request(DELETE, "/v2/droplets/${U64.to_str(id)}", token))?
		if Response.status(response) == 204 {
			Ok({})
		} else {
			unexpected("delete droplet ${U64.to_str(id)}", response)
		}
	}
}
