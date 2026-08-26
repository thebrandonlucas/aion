app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.16.0/42jC1JT3auhHSmv2Ah8mW5F2MXiAakq1UQQ4NQceQjXw.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.OsStr
import pf.Path
import pf.Server
import pf.UnixTime
import http.Response
import "aion.html" as page : List(U8)

import Everpaid
import EverpaidApi

Context : { api_key : Str }

Order : {
	machine : Str,
	reference : Str,
	payment_id : Str,
	bolt11 : Str,
	amount_sats : U64,
}

program = { init!, respond!, shutdown! }

orders_root = Path.utf8(".aion/payments")

init! : () => Try({ config : Server.Config, context : Context }, _)
init! = || {
	api_key = Env.var_str!(OsStr.utf8("EVERPAID_API_KEY"))?
	if api_key.trim().is_empty() {
		Err(EmptyEverpaidApiKey)
	} else {
		Path.create_all!(orders_root)?
		Ok({ config: Server.default_config, context: { api_key } })
	}
}

response = |status, content_type, body|
	Server.respond(
		Response.from_status(status)
			.with_headers([
				{ name: "Content-Type", value: content_type },
				{ name: "Cache-Control", value: "no-store" },
			])
			.with_body(body),
	)

json = |status, body| response(status, "application/json; charset=utf-8", Str.to_utf8(body))

machine_json = |status, message| json(200, "{\"status\":\"${status}\",\"message\":\"${message}\"}")

order_path = |name| Path.join(orders_root, "${name}.json")

marker_path = |name, marker| Path.join(orders_root, "${name}.${marker}")

is_name_alphanumeric = |byte|
	(byte >= 'a' and byte <= 'z') or (byte >= '0' and byte <= '9')

valid_name = |name| {
	bytes = name.to_utf8()
	length = bytes.len()
	length > 0
		and length <= 63
			and is_name_alphanumeric(bytes.get(0) ?? 0)
				and is_name_alphanumeric(bytes.get(length - 1) ?? 0)
					and bytes.all(|byte| is_name_alphanumeric(byte) or byte == '-')
}

read_order! = |name| {
	decoded : Try(Order, _)
	decoded = Json.parse(Path.read_utf8!(order_path(name))?)
	decoded
}

save_order! : Order => Try({}, _)
save_order! = |order| {
	encoded = Json.to_str_try(order)?
	Path.write_utf8!(order_path(order.machine), encoded)
}

invoice_json = |invoice|
	json(
		201,
		"{\"name\":\"${invoice.machine}\",\"amountSats\":${invoice.amount_sats.to_str()},\"bolt11\":\"${invoice.bolt11}\"}",
	)

complete_invoice! = |order, api_key| {
	if order.payment_id.is_empty() {
		invoice = EverpaidApi.create_invoice!(order.amount_sats, order.machine, order.reference, api_key) ? |_| CompleteInvoiceFailed
		complete = { ..order, payment_id: invoice.id, bolt11: invoice.bolt11 }
		save_order!(complete) ? |_| CompleteInvoiceFailed
		Ok(complete)
	} else {
		Ok(order)
	}
}

create_invoice! = |request, { api_key }| {
	request_body : Server.Body
	request_body = request.body()
	body = request_body.with_limit(1024).read_all!() ? |_| CreateInvoiceFailed
	body_str = Str.from_utf8_lossy(body)
	parsed : Try({ name : Str }, _)
	parsed = Json.parse(body_str)
	match parsed {
		Err(_) => Ok(json(400, "{\"error\":\"Expected a JSON machine name\"}"))
		Ok({ name }) => {
			if !valid_name(name) {
				Ok(json(400, "{\"error\":\"Use 1-63 lowercase letters, digits, or internal hyphens\"}"))
			} else {
				path = order_path(name)
				order = if Path.exists!(path) ? |_| CreateInvoiceFailed {
					read_order!(name) ? |_| CreateInvoiceFailed
				} else {
					seconds = UnixTime.now!().seconds_since_epoch()
					created = {
						machine: name,
						reference: "aion:${name}:${seconds.to_str()}",
						payment_id: "",
						bolt11: "",
						amount_sats: Everpaid.machine_price_sats,
					}
					save_order!(created) ? |_| CreateInvoiceFailed
					created
				}
				invoice = complete_invoice!(order, api_key) ? |_| CreateInvoiceFailed
				Ok(invoice_json(invoice))
			}
		}
	}
}

finish_provision! = |name, succeeded| {
	lock = marker_path(name, "provisioning")
	if succeeded {
		Path.write_utf8!(marker_path(name, "active"), "")?
	} else {
		Path.write_utf8!(marker_path(name, "failed"), "")?
	}
	_ = Path.delete_empty!(lock) ?? {}
	if succeeded {
		Ok(machine_json("active", "Machine is active"))
	} else {
		Ok(machine_json("failed", "Provisioning failed; inspect the Aion server output"))
	}
}

provision! = |order| {
	lock = marker_path(order.machine, "provisioning")
	if Path.is_dir!(lock)? {
		Ok(machine_json("provisioning", "Payment received; machine is provisioning"))
	} else {
		match Path.create_dir!(lock) {
			Err(_) => Ok(machine_json("provisioning", "Payment received; machine is provisioning"))
			Ok({}) => {
				result = Cmd.new_str(".kai/artifacts/aion")
					.args_str(["create-paid", order.machine])
					.env_str("AION_EVERPAID_PAYMENT_ID", order.payment_id)
					.with_timeout_millis(1_200_000)
					.exec_exit_code!()
				match result {
					Ok(0) => finish_provision!(order.machine, Bool.True)
					_ => finish_provision!(order.machine, Bool.False)
				}
			}
		}
	}
}

machine_status! = |name, { api_key }| {
	if !valid_name(name) or !Path.exists!(order_path(name))? {
		Ok(json(404, "{\"error\":\"Machine payment not found\"}"))
	} else if Path.exists!(Path.utf8(".aion/machines/${name}.json"))? or Path.exists!(marker_path(name, "active"))? {
		Ok(machine_json("active", "Machine is active"))
	} else if Path.exists!(marker_path(name, "failed"))? {
		Ok(machine_json("failed", "Provisioning failed; inspect the Aion server output"))
	} else if Path.is_dir!(marker_path(name, "provisioning"))? {
		Ok(machine_json("provisioning", "Payment received; machine is provisioning"))
	} else {
		order = read_order!(name)?
		if order.payment_id.is_empty() {
			Ok(machine_json("pending", "Invoice creation is incomplete; submit the form again"))
		} else {
			payment = EverpaidApi.get_payment!(order.payment_id, api_key)?
			if payment.amountSats != order.amount_sats or !Everpaid.reference_matches_machine(payment.reference, name) {
				return Err(PaymentDoesNotMatchOrder)
			}
			match payment.status {
				"settled" => provision!(order)
				"expired" => Ok(machine_json("expired", "Invoice expired; remove its local payment state to retry"))
				"failed" => Ok(machine_json("failed", "Payment failed"))
				_ => Ok(machine_json("pending", "Waiting for payment…"))
			}
		}
	}
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |request, context| {
	result = match (request.method(), request.target()) {
		(GET, Resource({ raw_path: "/", .. })) => Ok(response(200, "text/html; charset=utf-8", page))
		(POST, Resource({ raw_path: "/api/machines", .. })) => create_invoice!(request, context)
		(GET, Resource({ raw_path, .. })) =>
			match raw_path.split_on("/") {
				["", "api", "machines", name] => machine_status!(name, context)
				_ => Ok(json(404, "{\"error\":\"Not found\"}"))
			}
		_ => Ok(json(404, "{\"error\":\"Not found\"}"))
	}
	result.map_err(|error| ServerErr("Request failed: ${Str.inspect(error)}"))
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})
