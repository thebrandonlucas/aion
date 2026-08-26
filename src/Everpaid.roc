Everpaid := [].{
	Invoice : {
		id : Str,
		status : Str,
		amountSats : U64,
		bolt11 : Str,
	}

	Payment : {
		id : Str,
		status : Str,
		amountSats : U64,
	}

	invoice_body : U64, Str, Str -> { amountSats : U64, description : Str, reference : Str }
	invoice_body = |amount_sats, machine, reference| {
		amountSats: amount_sats,
		description: "Aion machine '${machine}'",
		reference,
	}
}
