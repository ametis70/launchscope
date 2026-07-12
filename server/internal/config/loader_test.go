package config_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/ametis70/launchscope/server/internal/config"
)

// ── full Load cascade ─────────────────────────────────────────────────────  //

func TestLoader_LoadInlineKey(t *testing.T) {
	dir := setup(t, `{"api":{"port":9000,"api_key":"mykey"}}`)

	l := config.NewLoader(dir)
	cfg, err := l.Load()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.API.Port != 9000 {
		t.Errorf("Port = %d, want 9000", cfg.API.Port)
	}
	if cfg.API.APIKey != "mykey" {
		t.Errorf("APIKey = %q, want \"mykey\"", cfg.API.APIKey)
	}
}

func TestLoader_LoadDefaultPort(t *testing.T) {
	dir := setup(t, `{"api":{"api_key":"k"}}`)

	l := config.NewLoader(dir)
	cfg, err := l.Load()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.API.Port != 8765 {
		t.Errorf("Port = %d, want 8765 (default)", cfg.API.Port)
	}
}

func TestLoader_GeneratesKeyWhenMissing(t *testing.T) {
	// config.json with no key — loader should auto-generate and persist.
	dir := setup(t, `{"api":{"port":8765}}`)

	l := config.NewLoader(dir)
	cfg, err := l.Load()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.API.APIKey == "" {
		t.Error("expected auto-generated API key, got empty string")
	}
	// Key file must exist.
	if _, err := os.Stat(filepath.Join(dir, "api_key")); err != nil {
		t.Errorf("api_key file not created: %v", err)
	}
}

func TestLoader_ReusesPersistedKey(t *testing.T) {
	dir := setup(t, `{"api":{"port":8765}}`)
	// Write a key file first.
	os.WriteFile(filepath.Join(dir, "api_key"), []byte("persistedkey\n"), 0o600)

	l := config.NewLoader(dir)
	cfg, err := l.Load()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.API.APIKey != "persistedkey" {
		t.Errorf("APIKey = %q, want \"persistedkey\"", cfg.API.APIKey)
	}
}

func TestLoader_APIKeyFileField(t *testing.T) {
	dir := t.TempDir()
	keyFile := filepath.Join(dir, "my.key")
	os.WriteFile(keyFile, []byte("filekey"), 0o600)

	cfgJSON := `{"api":{"port":8765,"api_key_file":"` + keyFile + `"}}`
	os.WriteFile(filepath.Join(dir, "config.json"), []byte(cfgJSON), 0o644)

	l := config.NewLoader(dir)
	cfg, err := l.Load()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.API.APIKey != "filekey" {
		t.Errorf("APIKey = %q, want \"filekey\"", cfg.API.APIKey)
	}
	// api_key_file must be cleared from the in-memory struct.
	if cfg.API.APIKeyFile != "" {
		t.Error("APIKeyFile should be cleared after resolution")
	}
}

func TestLoader_InvalidJSON(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "config.json"), []byte("bad json"), 0o644)

	l := config.NewLoader(dir)
	_, err := l.Load()
	if err == nil {
		t.Error("expected error for invalid JSON")
	}
}

func TestLoader_ValidationFails(t *testing.T) {
	// Port out of range.
	dir := setup(t, `{"api":{"port":99999,"api_key":"k"}}`)

	l := config.NewLoader(dir)
	_, err := l.Load()
	if err == nil {
		t.Error("expected error for invalid port")
	}
}

func TestLoader_Current(t *testing.T) {
	dir := setup(t, `{"api":{"port":8765,"api_key":"k"}}`)

	l := config.NewLoader(dir)
	if l.Current() != nil {
		t.Error("Current() should be nil before Load()")
	}
	l.Load()
	if l.Current() == nil {
		t.Error("Current() should be non-nil after Load()")
	}
}

func TestLoader_CECConfig(t *testing.T) {
	dir := setup(t, `{"api":{"port":8765,"api_key":"k"},"cec":{"enabled":true,"switch_port":3}}`)

	l := config.NewLoader(dir)
	cfg, err := l.Load()
	if err != nil {
		t.Fatal(err)
	}
	if !cfg.CEC.Enabled {
		t.Error("CEC.Enabled = false, want true")
	}
	if cfg.CEC.SwitchPort != 3 {
		t.Errorf("CEC.SwitchPort = %d, want 3", cfg.CEC.SwitchPort)
	}
}

func TestLoader_InlineKeyOverridesPersistedFile(t *testing.T) {
	dir := setup(t, `{"api":{"port":8765,"api_key":"inlinekey"}}`)
	// Write a persisted key — inline key in config.json should take precedence.
	os.WriteFile(filepath.Join(dir, "api_key"), []byte("persistedkey"), 0o600)

	l := config.NewLoader(dir)
	cfg, err := l.Load()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.API.APIKey != "inlinekey" {
		t.Errorf("APIKey = %q, want \"inlinekey\"", cfg.API.APIKey)
	}
}

// ── helper ───────────────────────────────────────────────────────────────── //

func setup(t *testing.T, jsonContent string) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "config.json"), []byte(jsonContent), 0o644); err != nil {
		t.Fatal(err)
	}
	return dir
}
