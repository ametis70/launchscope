package config_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/ametis70/launchscope/server/internal/config"
)

// ── Validate ─────────────────────────────────────────────────────────────── //

func TestValidate_Valid(t *testing.T) {
	c := &config.Config{
		API: config.APIConfig{Port: 8765, APIKey: "somekey"},
	}
	if err := c.Validate(); err != nil {
		t.Errorf("expected no error, got %v", err)
	}
}

func TestValidate_MissingKey(t *testing.T) {
	c := &config.Config{
		API: config.APIConfig{Port: 8765},
	}
	if err := c.Validate(); err == nil {
		t.Error("expected error for missing API key")
	}
}

func TestValidate_PortZero(t *testing.T) {
	c := &config.Config{
		API: config.APIConfig{Port: 0, APIKey: "k"},
	}
	if err := c.Validate(); err == nil {
		t.Error("expected error for port 0")
	}
}

func TestValidate_PortTooHigh(t *testing.T) {
	c := &config.Config{
		API: config.APIConfig{Port: 65536, APIKey: "k"},
	}
	if err := c.Validate(); err == nil {
		t.Error("expected error for port > 65535")
	}
}

func TestValidate_PortBoundary(t *testing.T) {
	for _, port := range []int{1, 8765, 65535} {
		c := &config.Config{API: config.APIConfig{Port: port, APIKey: "k"}}
		if err := c.Validate(); err != nil {
			t.Errorf("port %d: unexpected error %v", port, err)
		}
	}
}

// ── ConfigDirPath ────────────────────────────────────────────────────────── //

func TestConfigDirPath_UsesXDGConfigHome(t *testing.T) {
	tmp := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", tmp)

	got, err := config.ConfigDirPath()
	if err != nil {
		t.Fatal(err)
	}
	want := filepath.Join(tmp, "launchscoped")
	if got != want {
		t.Errorf("got %q, want %q", got, want)
	}
	// Must NOT create the directory.
	if _, err := os.Stat(got); !os.IsNotExist(err) {
		t.Error("ConfigDirPath should not create the directory")
	}
}

func TestConfigDirPath_FallsBackToHome(t *testing.T) {
	t.Setenv("XDG_CONFIG_HOME", "")

	got, err := config.ConfigDirPath()
	if err != nil {
		t.Fatal(err)
	}
	if got == "" {
		t.Error("expected non-empty path")
	}
}

// ── EnsureConfigDir ──────────────────────────────────────────────────────── //

func TestEnsureConfigDir_CreatesDir(t *testing.T) {
	tmp := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", tmp)

	got, err := config.EnsureConfigDir()
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(got); err != nil {
		t.Errorf("directory was not created: %v", err)
	}
}

func TestEnsureConfigDir_IdempotentIfExists(t *testing.T) {
	tmp := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", tmp)

	// Call twice — second call must not fail.
	for i := 0; i < 2; i++ {
		if _, err := config.EnsureConfigDir(); err != nil {
			t.Fatalf("call %d: unexpected error %v", i+1, err)
		}
	}
}
