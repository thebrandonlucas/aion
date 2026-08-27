import pf.Http
import http.Request
import http.Response

import Everpaid

EverpaidApi := [].{
	request = |method, path, api_key|
		Request.from_method(method)
			.with_uri("https://everpaid.app${path}")
			.with_timeout(TimeoutMilliseconds(30000))
			.add_header("Authorization", "Bearer ${api_key}")
			.add_header("User-Agent", "aion")

	create_invoice! = |amount_sats, machine, reference, api_key| {
		body = Everpaid.invoice_body(amount_sats, machine, reference)
		response = Http.send_json!(request(POST, "/api/v1/invoices", api_key), body)?
		status = Response.status(response)
		if status == 200 or status == 201 {
			invoice : Everpaid.Invoice
			invoice = Http.decode_json_response(response)?
			Ok(invoice)
		} else {
			Err(UnexpectedEverpaidStatus({ operation: "create invoice", status }))
		}
	}

	get_payment! = |id, api_key| {
		response = Http.send!(request(GET, "/api/v1/payments/${id}", api_key))?
		if Response.status(response) == 200 {
			payment : Everpaid.Payment
			payment = Http.decode_json_response(response)?
			Ok(payment)
		} else {
			Err(UnexpectedEverpaidStatus({ operation: "get payment", status: Response.status(response) }))
		}
	}
}
