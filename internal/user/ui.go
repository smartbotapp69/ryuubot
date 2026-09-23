package user

import (
	"net/http"
	"strings"
)

// assembleUserHTML merges the split assets back into a single document.
// index.html carries no <style>/<script> tags after extraction; the stylesheet
// is inserted into the head and the script right before the closing body tag,
// so the page renders with its intended design instead of leaking CSS as text.
func assembleUserHTML() []byte {
	html := strings.Replace(string(IndexHTML), "</head>", "<style>"+string(StyleCSS)+"</style></head>", 1)
	html = strings.Replace(html, "</body>", string(AppJS)+"</body>", 1)
	return []byte(html)
}

var userHTML = assembleUserHTML()

func (h *HTTP) userPage(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-cache, no-store, must-revalidate")
	w.Header().Set("X-Accel-Buffering", "no")
	_, _ = w.Write(userHTML)
}