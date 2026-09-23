package user

import (
	_ "embed"
)

//go:embed assets/index.html
var IndexHTML []byte

//go:embed assets/style.css
var StyleCSS []byte

//go:embed assets/app.js
var AppJS []byte
