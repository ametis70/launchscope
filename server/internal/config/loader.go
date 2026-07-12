package config

import (
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"

	"github.com/ametis70/launchscope/server/internal/loader"
)

const configFile = "config.json"

// Loader reads daemon configuration from disk and exposes it for concurrent
// access. It is a thin wrapper around loader.Loader[Config] that adds
// config-specific post-processing (defaults, API key resolution, validation).
type Loader struct {
	inner *loader.Loader[Config]
}

// NewLoader creates a Loader rooted at dir.
func NewLoader(dir string) *Loader {
	return &Loader{inner: loader.New[Config](dir, configFile)}
}

// Load reads config.json, applies defaults, resolves the API key, validates,
// and stores the result atomically.
func (l *Loader) Load() (*Config, error) {
	cfg, err := l.inner.Load(func(cfg *Config) error {
		applyDefaults(cfg)
		return resolveAPIKey(cfg, l.inner.Dir())
	})
	if err != nil {
		return nil, err
	}
	if err := cfg.Validate(); err != nil {
		return nil, fmt.Errorf("invalid config: %w", err)
	}
	return cfg, nil
}

// Current returns the last successfully loaded Config.
func (l *Loader) Current() *Config {
	return l.inner.Current()
}

// ── helpers ──────────────────────────────────────────────────────────────── //

// Ensure atomic.Pointer is used in loader — suppress unused import lint.
var _ = (*atomic.Pointer[Config])(nil)

func applyDefaults(cfg *Config) {
	d := defaults()
	if cfg.API.Port == 0 {
		cfg.API.Port = d.API.Port
	}
}

const defaultKeyFile = "api_key"

// resolveAPIKey populates cfg.API.APIKey from the appropriate source and
// clears cfg.API.APIKeyFile so the resolved key is never re-serialised as a
// file path. Resolution order:
//
//  1. cfg.API.APIKeyFile (explicit file path in config) — always wins
//  2. cfg.API.APIKey     (inline value in config.json)
//  3. <cfgDir>/api_key   (persisted auto-generated key)
//  4. auto-generate and persist to <cfgDir>/api_key
func resolveAPIKey(cfg *Config, cfgDir string) error {
	filePath := cfg.API.APIKeyFile
	cfg.API.APIKeyFile = "" // always clear — never leak path into runtime struct

	// 1. Explicit key file path.
	if filePath != "" {
		data, err := os.ReadFile(filePath)
		if err != nil {
			return fmt.Errorf("reading api key file %q: %w", filePath, err)
		}
		cfg.API.APIKey = strings.TrimSpace(string(data))
		return nil
	}

	// 2. Inline key value (e.g. set via Nix option).
	if cfg.API.APIKey != "" {
		return nil
	}

	// 3. Default key file — persisted from a previous auto-generation.
	// Use ReadFile directly to avoid a TOCTOU race between Stat and ReadFile.
	defaultFile := filepath.Join(cfgDir, defaultKeyFile)
	data, err := os.ReadFile(defaultFile)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("reading api key file %q: %w", defaultFile, err)
	}
	if err == nil {
		cfg.API.APIKey = strings.TrimSpace(string(data))
		return nil
	}

	// 4. No key anywhere — generate one and persist it.
	key, err := generateAPIKey()
	if err != nil {
		return fmt.Errorf("generating api key: %w", err)
	}
	if err := os.WriteFile(defaultFile, []byte(key), fs.FileMode(0o600)); err != nil {
		return fmt.Errorf("writing generated api key to %q: %w", defaultFile, err)
	}
	cfg.API.APIKey = key
	return nil
}

// generateAPIKey returns a 256-bit URL-safe base64 key (no padding).
func generateAPIKey() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}
