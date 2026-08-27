app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.16.0/42jC1JT3auhHSmv2Ah8mW5F2MXiAakq1UQQ4NQceQjXw.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.OsStr
import pf.Path
import pf.Server
import pf.Stderr
import pf.UnixTime
import http.Response
import "aion.html" as page : List(U8)

import Everpaid

Context : {
	api_key : Str,
	digitalocean_token : Str,
	home : Str,
	model_api_key : Str,
	path : Str,
}

Order : {
	machine : Str,
	reference : Str,
	payment_id : Str,
	bolt11 : Str,
	amount_sats : U64,
}

program = { init!, respond!, shutdown! }

orders_root = Path.utf8(".aion/payments")

bitcoin_qr_root = Path.utf8("BITCOIN_QR_ASSETS")

reservation_path = Path.join(orders_root, "reservation")

require_env! = |name| {
	value = Env.var_str!(OsStr.utf8(name))?
	if value.trim().is_empty() Err(EmptyEnvironmentVariable(name)) else Ok(value)
}

init! : () => Try({ config : Server.Config, context : Context }, _)
init! = || {
	api_key = require_env!("EVERPAID_API_KEY")?
	digitalocean_token = require_env!("DIGITALOCEAN_TOKEN")?
	home = require_env!("HOME")?
	model_api_key = require_env!("AION_MODEL_API_KEY")?
	path = require_env!("PATH")?
	Path.create_all!(orders_root)?
	Ok({ config: Server.default_config, context: { api_key, digitalocean_token, home, model_api_key, path } })
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

javascript! = |name|
	Ok(response(200, "text/javascript; charset=utf-8", Str.to_utf8(Path.read_utf8!(Path.join(bitcoin_qr_root, name))?)))

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

aion_command = |context, arguments, timeout_ms|
	Cmd.new_str(".kai/artifacts/aion")
		.args_str(arguments)
		.clear_envs()
		.envs_str([
			{ name: "AION_MODEL_API_KEY", value: context.model_api_key },
			{ name: "DIGITALOCEAN_TOKEN", value: context.digitalocean_token },
			{ name: "EVERPAID_API_KEY", value: context.api_key },
			{ name: "HOME", value: context.home },
			{ name: "PATH", value: context.path },
		])
		.with_timeout_millis(timeout_ms)

payment_preflight! = |context, name|
	match aion_command(context, ["payment-preflight", name], 120_000).exec_exit_code!() {
		Ok(0) => Ok(Bool.True)
		_ => Ok(Bool.False)
	}

create_everpaid_invoice! = |order, context| {
	output = aion_command(context, ["everpaid-create-invoice", order.machine, order.reference], 120_000)
		.exec_output!() ? |_| EverpaidCommandFailed
	invoice : Try(Everpaid.Invoice, _)
	invoice = Json.parse(output.stdout_utf8)
	invoice
}

get_everpaid_payment! = |id, context| {
	output = aion_command(context, ["everpaid-get-payment", id], 120_000)
		.exec_output!() ? |_| EverpaidCommandFailed
	payment : Try(Everpaid.Payment, _)
	payment = Json.parse(output.stdout_utf8)
	payment
}

reserve_payment! = |name| {
	Path.create_dir!(reservation_path)?
	Path.write_utf8!(Path.join(reservation_path, "machine"), name)
}

complete_invoice! = |order, context| {
	if order.payment_id.is_empty() {
		invoice = create_everpaid_invoice!(order, context)?
		complete = { ..order, payment_id: invoice.id, bolt11: invoice.bolt11 }
		save_order!(complete)?
		Ok(complete)
	} else {
		Ok(order)
	}
}

create_invoice! = |request, context| {
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
					if !(payment_preflight!(context, name) ? |_| CreateInvoiceFailed) {
						return Ok(json(409, "{\"error\":\"Aion cannot safely accept another machine payment\"}"))
					}
					match reserve_payment!(name) {
						Err(_) => return Ok(json(409, "{\"error\":\"Another machine payment is already reserved\"}"))
						Ok({}) => {}
					}
					unique = UnixTime.now!().nanos_since_epoch()
					created = {
						machine: name,
						reference: "aion:${name}:${unique.to_str()}",
						payment_id: "",
						bolt11: "",
						amount_sats: Everpaid.machine_price_sats,
					}
					save_order!(created) ? |_| CreateInvoiceFailed
					created
				}
				invoice = complete_invoice!(order, context)?
				Ok(invoice_json(invoice))
			}
		}
	}
}

finish_provision! = |name, succeeded| {
	lock = marker_path(name, "provisioning")
	if !succeeded {
		Path.write_utf8!(marker_path(name, "failed"), "")?
	}
	_ = Path.delete_empty!(lock) ?? {}
	if succeeded {
		Ok(machine_json("active", "Machine is active"))
	} else {
		Ok(machine_json("failed", "Provisioning failed; inspect the Aion server output"))
	}
}

provision! = |order, context| {
	lock = marker_path(order.machine, "provisioning")
	if Path.is_dir!(lock)? {
		Ok(machine_json("provisioning", "Payment received; machine is provisioning"))
	} else {
		match Path.create_dir!(lock) {
			Err(_) =>
				if Path.is_dir!(lock) ?? Bool.False {
					Ok(machine_json("provisioning", "Payment received; machine is provisioning"))
				} else {
					Err(ProvisionLockFailed)
				}
			Ok({}) => {
				result = aion_command(context, ["create-paid", order.machine], 5_400_000)
					.env_str("AION_EVERPAID_PAYMENT_ID", order.payment_id)
					.exec_exit_code!()
				match result {
					Ok(0) => finish_provision!(order.machine, Bool.True)
					_ => finish_provision!(order.machine, Bool.False)
				}
			}
		}
	}
}

machine_status! = |name, context, allow_provision| {
	if !valid_name(name) or !Path.exists!(order_path(name))? {
		Ok(json(404, "{\"error\":\"Machine payment not found\"}"))
	} else if Path.exists!(Path.utf8(".aion/machines/${name}.json"))? {
		Ok(machine_json("active", "Machine is active"))
	} else if Path.exists!(marker_path(name, "failed"))? {
		Ok(machine_json("failed", "Provisioning failed; inspect the Aion server output"))
	} else if Path.is_dir!(marker_path(name, "provisioning"))? {
		Ok(machine_json("provisioning", "Payment received; machine is provisioning"))
	} else if Path.is_dir!(marker_path(name, "consumed"))? {
		Ok(machine_json("consumed", "This payment has already been used"))
	} else {
		order = read_order!(name)?
		if order.payment_id.is_empty() {
			Ok(machine_json("pending", "Invoice creation is incomplete; submit the form again"))
		} else {
			payment = get_everpaid_payment!(order.payment_id, context)?
			if payment.amountSats != order.amount_sats or !Everpaid.reference_matches_machine(payment.reference, name) {
				return Err(PaymentDoesNotMatchOrder)
			}
			match payment.status {
				"settled" =>
					if allow_provision {
						provision!(order, context)
					} else {
						Ok(machine_json("settled", "Payment received; starting provisioning"))
					}
				"expired" => Ok(machine_json("expired", "Invoice expired; remove its local payment state to retry"))
				"failed" => Ok(machine_json("failed", "Payment failed"))
				_ => Ok(machine_json("pending", "Waiting for payment…"))
			}
		}
	}
}

same_origin = |request|
	request.headers().any(
		|header|
			(header.name == "origin" or header.name == "Origin")
				and (header.value == "http://127.0.0.1:8000" or header.value == "http://localhost:8000"),
	)

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |request, context| {
	if request.method() == POST and !same_origin(request) {
		return Ok(json(403, "{\"error\":\"Same-origin request required\"}"))
	}
	result = match (request.method(), request.target()) {
		(GET, Resource({ raw_path: "/", .. })) => Ok(response(200, "text/html; charset=utf-8", page))
		(GET, Resource({ raw_path: "/bitcoin-qr/bitcoin-qr.esm.js", .. })) => javascript!("bitcoin-qr.esm.js")
		(GET, Resource({ raw_path: "/bitcoin-qr/p-74bae39c.js", .. })) => javascript!("p-74bae39c.js")
		(GET, Resource({ raw_path: "/bitcoin-qr/p-a1ecfd5f.js", .. })) => javascript!("p-a1ecfd5f.js")
		(GET, Resource({ raw_path: "/bitcoin-qr/p-dd3d3ad0.entry.js", .. })) => javascript!("p-dd3d3ad0.entry.js")
		(GET, Resource({ raw_path: "/bitcoin-qr/index.esm.js", .. })) => javascript!("index.esm.js")
		(POST, Resource({ raw_path: "/api/machines", .. })) => create_invoice!(request, context)
		(POST, Resource({ raw_path, .. })) =>
			match raw_path.split_on("/") {
				["", "api", "machines", name, "provision"] => machine_status!(name, context, Bool.True)
				_ => Ok(json(404, "{\"error\":\"Not found\"}"))
			}
		(GET, Resource({ raw_path, .. })) =>
			match raw_path.split_on("/") {
				["", "api", "machines", name] => machine_status!(name, context, Bool.False)
				_ => Ok(json(404, "{\"error\":\"Not found\"}"))
			}
		_ => Ok(json(404, "{\"error\":\"Not found\"}"))
	}
	match result {
		Ok(outcome) => Ok(outcome)
		Err(error) => {
			_ = Stderr.line!("request failed: ${Str.inspect(error)}") ?? {}
			Ok(json(500, "{\"error\":\"Server request failed; inspect the Aion server output\"}"))
		}
	}
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})
