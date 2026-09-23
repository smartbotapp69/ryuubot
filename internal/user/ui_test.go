package user

import (
	"strings"
	"testing"
)

// TestAssembledPageStructure guards the asset assembly in ui.go: the split
// CSS must live inside <head> and the script before </body>. A regression that
// concatenates files raw would leak the stylesheet as visible text in <body>
// and break the page design.
func TestAssembledPageStructure(t *testing.T) {
	page := string(userHTML)
	if !strings.HasPrefix(page, "<!doctype html>") {
		t.Fatalf("page must start with the doctype, got: %.80q", page)
	}
	head := strings.Index(page, "</head>")
	body := strings.Index(page, "<body>")
	style := strings.Index(page, "<style>")
	script := strings.Index(page, "<script>")
	bodyEnd := strings.LastIndex(page, "</body>")
	if head == -1 || body == -1 || style == -1 || script == -1 || bodyEnd == -1 {
		t.Fatalf("page is missing required tags: head=%d body=%d style=%d script=%d bodyEnd=%d", head, body, style, script, bodyEnd)
	}
	if !(style < head && head < body) {
		t.Fatalf("CSS must be inside <head>, got style=%d head=%d body=%d", style, head, body)
	}
	if !(body < script && script < bodyEnd) {
		t.Fatalf("JS must be inside <body>, got body=%d script=%d bodyEnd=%d", body, script, bodyEnd)
	}
	if leaked := strings.Index(page[body:bodyEnd], ":root{"); leaked >= 0 {
		t.Fatalf("raw CSS leaked into <body> at offset %d", leaked)
	}
}