app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.16.0/42jC1JT3auhHSmv2Ah8mW5F2MXiAakq1UQQ4NQceQjXw.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import http.Response
import "aion.html" as page : List(U8)

Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || Ok({ config: Server.default_config, context: {} })

response = |status, content_type, body|
	Server.respond(
		Response.from_status(status)
			.with_headers([{ name: "Content-Type", value: content_type }])
			.with_body(body),
	)

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |request, _context|
	match (request.method(), request.target()) {
		(GET, Resource({ raw_path: "/", .. })) => Ok(response(200, "text/html; charset=utf-8", page))
		_ => Ok(response(404, "application/json; charset=utf-8", Str.to_utf8("{\"error\":\"Not found\"}")))
	}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})
