Ansi := [].{
	escape = Str.from_utf8_lossy([27])
	reset = "${Ansi.escape}[0m"

	paint = |code, text| "${Ansi.escape}[${code}m${text}${Ansi.reset}"

	bold = |text| Ansi.paint("1", text)
	dim = |text| Ansi.paint("2", text)
	red = |text| Ansi.paint("31", text)
	green = |text| Ansi.paint("32", text)
	yellow = |text| Ansi.paint("33", text)
	cyan = |text| Ansi.paint("36", text)

	heading = |text| Ansi.paint("1;36", text)
}
