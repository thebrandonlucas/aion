# A stand-in for the parts of the DigitalOcean API aion uses, for testing
# launch, install, update and destroy without an account or a bill. It
# keeps keys and droplets in memory, answers one HTTP/1.1 request per
# connection on 127.0.0.1:PORT until a POST to /mock/stop, and prints each
# request's method, path and body (never its headers, which hold the
# token). A created droplet is "new" until its first GET, then "active" at
# MOCK_DROPLET_IP.
#
#   roc tools/mock-digitalocean/main.roc -- 8090
#   AION_DIGITALOCEAN_URL=http://127.0.0.1:8090 DIGITALOCEAN_TOKEN=mock aion ...
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
}

import pf.Duration
import pf.Env
import pf.OsStr
import pf.Stdout
import pf.Tcp

Key : { id : U64, name : Str, public_key : Str }

Network : { ip_address : Str, type : Str }

Droplet : { id : U64, name : Str, networks : { v4 : List(Network) }, region : { slug : Str }, size_slug : Str, status : Str, tags : List(Str) }

CreateBody : { image : Str, name : Str, region : Str, size : Str, ssh_keys : List(U64), tags : List(Str) }

KeyBody : { name : Str, public_key : Str }

State : { address : Str, droplets : List(Droplet), keys : List(Key), next_id : U64 }

Reply : { status : U16, body : Str }

reply = |status, body| { status, body }

droplet_json = |droplet| Json.to_str(
	{ droplet: droplet },
)

# The request's path without its query, and the query's tag_name.
split_target = |target|
	match target.split_on("?") {
		[path, query, ..] => {
			tags = query.split_on("&").keep_if(|pair| pair.starts_with("tag_name=")).map(|pair| pair.drop_prefix("tag_name="))
			(path, tags.first() ?? "")
		}
		_ => (target, "")
	}

handle : State, Str, Str, Str -> (State, Reply)
handle = |state, method, target, body| {
	(path, tag) = split_target(target)
	match (method, path.split_on("/").drop_first(1)) {
		("GET", ["v2", "account", "keys"]) => (state, reply(200, Json.to_str({ ssh_keys: state.keys })))
		("POST", ["v2", "account", "keys"]) => {
			parsed : Try(KeyBody, _)
			parsed = Json.parse(body)
			match parsed {
				Err(_) => (state, reply(400, "{}"))
				Ok(key) if state.keys.any(|k| k.public_key == key.public_key) => (state, reply(422, "{}"))
				Ok(key) => {
					ssh_key = { id: state.next_id, name: key.name, public_key: key.public_key }
					(
						{ ..state, keys: state.keys.append(ssh_key), next_id: state.next_id + 1 },
						reply(
							201,
							Json.to_str(
								{ ssh_key: ssh_key },
							),
						),
					)
				}
			}
		}
		("GET", ["v2", "droplets"]) => {
			droplets = state.droplets.keep_if(|d| tag.is_empty() or d.tags.contains(tag))
			(
				state,
				reply(
					200,
					Json.to_str(
						{ droplets: droplets },
					),
				),
			)
		}
		("POST", ["v2", "droplets"]) => {
			parsed : Try(CreateBody, _)
			parsed = Json.parse(body)
			match parsed {
				Err(_) => (state, reply(422, "{}"))
				Ok(create) => {
					droplet = { id: state.next_id, name: create.name, networks: { v4: [] }, region: { slug: create.region }, size_slug: create.size, status: "new", tags: create.tags }
					({ ..state, droplets: state.droplets.append(droplet), next_id: state.next_id + 1 }, reply(202, droplet_json(droplet)))
				}
			}
		}
		("GET", ["v2", "droplets", id]) =>
			match state.droplets.keep_if(|d| U64.to_str(d.id) == id) {
				[found, ..] => {
					active = { ..found, status: "active", networks: { v4: [{ ip_address: state.address, type: "public" }] } }
					others = state.droplets.keep_if(|d| d.id != found.id)
					({ ..state, droplets: others.append(active) }, reply(200, droplet_json(active)))
				}
				[] => (state, reply(404, "{}"))
			}
		("DELETE", ["v2", "droplets", id]) =>
			if state.droplets.any(|d| U64.to_str(d.id) == id) {
				({ ..state, droplets: state.droplets.keep_if(|d| U64.to_str(d.id) != id) }, reply(204, ""))
			} else {
				(state, reply(404, "{}"))
			}
		_ => (state, reply(404, "{}"))
	}
}

# Headers until the blank line, keeping Content-Length and whether the
# request carries a bearer token.
read_headers! = |conn, length, authorized| {
	line = conn.read_line!()?.trim()
	if line.is_empty() {
		Ok((length, authorized))
	} else {
		lower = Str.from_utf8_lossy(line.to_utf8().map(|b| if (b >= 'A' and b <= 'Z') b + 32 else b))
		next_length = if (lower.starts_with("content-length:")) U64.from_str(line.split_on(":").last().map_ok(Str.trim) ?? "") ?? 0 else length
		read_headers!(conn, next_length, authorized or lower.starts_with("authorization: bearer "))
	}
}

serve_one! = |listener, state| {
	conn = listener.accept!({ accept_timeout: NoTimeout, io_timeout: Duration.seconds(30) })?
	request_line = conn.read_line!()?.trim()
	(length, authorized) = read_headers!(conn, 0, Bool.False)?
	body = if (length == 0) "" else Str.from_utf8_lossy(conn.read_exactly!(length)?)
	(method, target) = match request_line.split_on(" ") {
		[m, t, ..] => (m, t)
		_ => ("", "")
	}
	Stdout.line!("${method} ${target} ${body}")?
	(next, answer) = if (authorized) handle(state, method, target, body) else (state, reply(401, "{}"))
	head = "HTTP/1.1 ${U16.to_str(answer.status)} Mock\r\nContent-Type: application/json\r\nContent-Length: ${U64.to_str(answer.body.to_utf8().len())}\r\nConnection: close\r\n\r\n"
	conn.write_utf8!(head.concat(answer.body))?
	Ok((next, target != "/mock/stop"))
}

# A loop, not recursion: on the nightly-2026-10-21-5349569 kai pins, roc
# check segfaults in lambda_solve on the recursive form, which
# nightly-2026-11-14-a87808d fixed. Recurse again once kai's Roc pin is at
# least that nightly; roc-issues archive/BUG-038
# (https://github.com/thebrandonlucas/roc-issues/tree/master/archive/BUG-038-recursive-effect-tuple-lambda-solve-segfault).
serve! = |listener, initial| {
	var $state = initial
	var $running = Bool.True
	while $running {
		match serve_one!(listener, $state) {
			Ok((next, running)) => {
				$state = next
				$running = running
			}
			Err(_) => {}
		}
	}
	Ok({})
}

main! = |args| {
	port = match args.map(OsStr.display) {
		[given, ..] => U16.from_str(given) ?? 8090
		[] => 8090
	}
	listener = Tcp.listen!("127.0.0.1", port, Duration.seconds(5))?
	address = Env.var_str!(OsStr.from_str("MOCK_DROPLET_IP")) ?? "203.0.113.7"
	Stdout.line!("mock DigitalOcean on 127.0.0.1:${U16.to_str(port)}, droplets at ${address}")?
	serve!(listener, { address, droplets: [], keys: [], next_id: 1000 })
}
