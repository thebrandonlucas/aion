# HTTPS effects against the DigitalOcean API. Error values carry the failed
# operation and status code only; response bodies are never printed. `auth`
# is `{ url, token }`: the API's base URL, https://api.digitalocean.com
# unless a test points it at a mock, and the bearer token.
import pf.Http
import http.Request
import http.Response

import DigitalOcean
import SshKey

DigitalOceanApi := [].{
	default_url = "https://api.digitalocean.com"

	request = |method, path, auth|
		Request.from_method(method)
			.with_uri("${auth.url}${path}")
			.with_timeout(TimeoutMilliseconds(30000))
			.add_header("Authorization", "Bearer ${auth.token}")
			.add_header("User-Agent", "aion")

	unexpected = |operation, response|
		Err(UnexpectedStatus({ operation, status: Response.status(response) }))

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

	list_ssh_key_pages! = |auth, page| {
		response = Http.send!(request(GET, "/v2/account/keys?per_page=200&page=${U64.to_str(page)}", auth), {})?
		if Response.status(response) != 200 {
			unexpected("list ssh keys", response)
		} else {
			keys = decode_ssh_keys!(response)?
			if keys.len() < 200 {
				Ok(keys)
			} else if page >= 100 {
				Err(ProviderInventoryTooLarge)
			} else {
				Ok(keys.concat(list_ssh_key_pages!(auth, page + 1)?))
			}
		}
	}

	list_ssh_keys! = |auth| list_ssh_key_pages!(auth, 1)

	same_ssh_key = |left, right|
		match (SshKey.canonical(left), SshKey.canonical(right)) {
			(Ok(a), Ok(b)) => a == b
			_ => Bool.False
		}

	# Registers `public_key`, or finds it when the account already has it.
	register_ssh_key! = |name, public_key, auth| {
		body : { name : Str, public_key : Str }
		body = { name, public_key }
		response = Http.send_json!(request(POST, "/v2/account/keys", auth), body, {})?
		match Response.status(response) {
			201 => {
				decoded : Try(DigitalOcean.SshKeyResponse, _)
				decoded = Http.decode_json_response(response)
				match decoded {
					Ok(wrapper) => Ok(wrapper.ssh_key)
					Err(error) => Err(error)
				}
			}
			422 => {
				keys = list_ssh_keys!(auth)?
				match keys.keep_if(|key| same_ssh_key(key.public_key, public_key)) {
					[found, ..] => Ok(found)
					[] => Err(NoMatchingSshKey)
				}
			}
			_ => unexpected("register ssh key", response)
		}
	}

	# Billable POSTs are deliberately single-attempt. Only 4xx responses are
	# definitive rejections; transport failures, other statuses, and accepted-
	# response decode failures are uncertain.
	create_droplet_once! = |body, auth| {
		match Http.send_json!(request(POST, "/v2/droplets", auth), body, {}) {
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

	list_droplet_pages! = |tag, auth, page| {
		response = Http.send!(request(GET, "/v2/droplets?tag_name=${tag}&per_page=200&page=${U64.to_str(page)}", auth), {})?
		if Response.status(response) != 200 {
			unexpected("list droplets by tag", response)
		} else {
			droplets = decode_droplets!(response)?
			if droplets.len() < 200 {
				Ok(droplets)
			} else if page >= 100 {
				Err(ProviderInventoryTooLarge)
			} else {
				Ok(droplets.concat(list_droplet_pages!(tag, auth, page + 1)?))
			}
		}
	}

	list_droplets_by_tag! = |tag, auth| list_droplet_pages!(tag, auth, 1)

	get_droplet! = |id, auth| {
		response = Http.send!(request(GET, "/v2/droplets/${U64.to_str(id)}", auth), {})?
		if Response.status(response) == 200 {
			decode_droplet!(response)
		} else {
			unexpected("get droplet", response)
		}
	}

	# Only this account confirming deletion can release local state. A 404
	# may mean a token for the wrong account.
	delete_droplet! = |id, auth| {
		response = Http.send!(request(DELETE, "/v2/droplets/${U64.to_str(id)}", auth), {})?
		if Response.status(response) == 204 {
			Ok({})
		} else {
			unexpected("delete droplet ${U64.to_str(id)}", response)
		}
	}
}
