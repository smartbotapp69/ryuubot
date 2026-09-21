package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadDotEnvDoesNotOverwriteProcessEnvironment(t *testing.T) {
	directory := t.TempDir()
	path := filepath.Join(directory, ".env")
	if err := os.WriteFile(path, []byte("RYUBOT_DOTENV_TEST=from-file\n"), 0600); err != nil { t.Fatal(err) }
	t.Setenv("RYUBOT_DOTENV_TEST", "from-process")
	if err := loadDotEnv(path); err != nil { t.Fatal(err) }
	if got := os.Getenv("RYUBOT_DOTENV_TEST"); got != "from-process" { t.Fatalf("got %q", got) }
}
