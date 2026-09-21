package config

import (
	"bufio"
	"errors"
	"os"
	"strings"
)

// loadDotEnv loads local development configuration without overriding values
// already supplied by the operating system or production service manager.
func loadDotEnv(path string) error {
	file, err := os.Open(path)
	if errors.Is(err, os.ErrNotExist) { return nil }
	if err != nil { return err }
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") { continue }
		if strings.HasPrefix(line, "export ") { line = strings.TrimSpace(strings.TrimPrefix(line, "export ")) }
		key, value, ok := strings.Cut(line, "=")
		if !ok { return errors.New("baris .env harus berbentuk KEY=VALUE") }
		key = strings.TrimSpace(key)
		value = strings.TrimSpace(value)
		if key == "" { return errors.New("nama variabel .env kosong") }
		if len(value) >= 2 && ((value[0] == '"' && value[len(value)-1] == '"') || (value[0] == '\'' && value[len(value)-1] == '\'')) {
			value = value[1:len(value)-1]
		}
		if _, exists := os.LookupEnv(key); !exists {
			if err := os.Setenv(key, value); err != nil { return err }
		}
	}
	return scanner.Err()
}
