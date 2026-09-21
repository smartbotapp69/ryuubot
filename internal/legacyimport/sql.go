package legacyimport

// legacyColumnExpression quotes a column discovered from information_schema.
// The name never comes from user input; it is selected only from the legacy
// database metadata before this expression is built.
func legacyColumnExpression(column, cast string) string {
	return "p.\"" + column + "\"::" + cast
}
