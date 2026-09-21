package migrations

import "embed"

// Files contains ordered SQL migrations compiled into the Ryubot binary.
//
//go:embed *.sql
var Files embed.FS
