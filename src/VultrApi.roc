# HTTPS effects against the Vultr API. Error values carry the failed
# operation and status code only; response bodies are never printed. `auth`
# is `{ url, token }`: the API's base URL, https://api.vultr.com unless a
# test points it at a mock, and the bearer token.
import pf.Http
import http.Request
import http.Response

import SshKey
import Vultr

VultrApi := [].{
	default_url = "https://api.vultr.com"

	request = |method, path, auth|
		Request.from_method(method)
			.with_uri("${auth.url}${path}")
			.with_timeout(TimeoutMilliseconds(30000))
			.add_header("Authorization", "Bearer ${auth.token}")
			.add_header("User-Agent", "aion")

	unexpected = |operation, response|
		Err(UnexpectedStatus({ operation, status: Response.status(response) }))

	decode_instance! = |response| {
		decoded : Try(Vultr.InstanceResponse, _)
		decoded = Http.decode_json_response(response)
		match decoded {
			Ok(wrapper) => Ok(wrapper.instance)
			Err(error) => Err(error)
		}
	}

	# Every SSH key on the account. Lists are one page of up to 500: aion's
	# account holds far fewer, and more is refused rather than half-read.
	list_ssh_keys! = |auth| {
		response = Http.send!(request(GET, "/v2/ssh-keys?per_page=500", auth), {})?
		if Response.status(response) != 200 {
			return unexpected("list ssh keys", response)
		}
		decoded : Try(Vultr.SshKeysResponse, _)
		decoded = Http.decode_json_response(response)
		page = decoded?
		if (page.meta.links.next.is_empty()) Ok(page.ssh_keys) else Err(ProviderInventoryTooLarge)
	}

	same_ssh_key = |left, right|
		match (SshKey.canonical(left), SshKey.canonical(right)) {
			(Ok(a), Ok(b)) => a == b
			_ => Bool.False
		}

	# The account's key holding `public_key`, registered as `name` if it has
	# none, since Vultr accepts the same key twice.
	ensure_ssh_key! = |name, public_key, auth| {
		match list_ssh_keys!(auth)?.keep_if(|key| same_ssh_key(key.ssh_key, public_key)) {
			[found, ..] => return Ok(found)
			[] => {}
		}
		body : { name : Str, ssh_key : Str }
		body = { name, ssh_key: public_key }
		response = Http.send_json!(request(POST, "/v2/ssh-keys", auth), body, {})?
		if Response.status(response) != 201 {
			return unexpected("register ssh key", response)
		}
		decoded : Try(Vultr.SshKeyResponse, _)
		decoded = Http.decode_json_response(response)
		match decoded {
			Ok(wrapper) => Ok(wrapper.ssh_key)
			Err(error) => Err(error)
		}
	}

	# Billable POSTs are deliberately single-attempt. Only 4xx responses are
	# definitive rejections; transport failures, other statuses, and accepted-
	# response decode failures are uncertain.
	create_instance_once! = |body, auth| {
		match Http.send_json!(request(POST, "/v2/instances", auth), body, {}) {
			Err(error) => PostUncertain(error)
			Ok(response) => {
				status = Response.status(response)
				if status >= 200 and status <= 299 {
					match decode_instance!(response) {
						Ok(instance) => PostAccepted(instance)
						Err(error) => PostUncertain(error)
					}
				} else if status >= 400 and status <= 499 {
					PostRejected(UnexpectedStatus({ operation: "create instance", status }))
				} else {
					PostUncertain(UnexpectedStatus({ operation: "create instance", status }))
				}
			}
		}
	}

	list_instances_by_tag! = |tag, auth| {
		response = Http.send!(request(GET, "/v2/instances?tag=${tag}&per_page=500", auth), {})?
		if Response.status(response) != 200 {
			return unexpected("list instances by tag", response)
		}
		decoded : Try(Vultr.InstancesResponse, _)
		decoded = Http.decode_json_response(response)
		page = decoded?
		if (page.meta.links.next.is_empty()) Ok(page.instances) else Err(ProviderInventoryTooLarge)
	}

	get_instance! = |id, auth| {
		response = Http.send!(request(GET, "/v2/instances/${id}", auth), {})?
		if Response.status(response) == 200 {
			decode_instance!(response)
		} else {
			unexpected("get instance", response)
		}
	}

	# Only this account confirming deletion can release local state. A 404
	# may mean a token for the wrong account.
	delete_instance! = |id, auth| {
		response = Http.send!(request(DELETE, "/v2/instances/${id}", auth), {})?
		if Response.status(response) == 204 {
			Ok({})
		} else {
			unexpected("delete instance ${id}", response)
		}
	}
}
