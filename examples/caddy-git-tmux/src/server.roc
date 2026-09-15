app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.16.0/42jC1JT3auhHSmv2Ah8mW5F2MXiAakq1UQQ4NQceQjXw.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import http.Response

Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, _)
init! = || Ok({ config: Server.default_config, context: {} })

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_request, _context|
	Ok(
		Server.respond(
			Response.from_status(200)
				.with_headers([{ name: "Content-Type", value: "text/plain; charset=utf-8" }])
				.with_body(Str.to_utf8("Aion homelab is running\n")),
		),
	)

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})
