package config

import (
	"fmt"
	"os"
	"path/filepath"
)

// Config is the launchscoped daemon configuration.
// It lives at $XDG_CONFIG_HOME/launchscoped/config.json.
// App definitions live separately in apps.json (see internal/apps).
type Config struct {
	API APIConfig `json:"api"`
	CEC CECConfig `json:"cec"`
}

type APIConfig struct {
	Port       int    `json:"port"`
	APIKey     string `json:"api_key"`
	APIKeyFile string `json:"api_key_file"` // path to a file containing the API key
}

// CECConfig controls the optional HDMI-CEC integration.
// When Enabled is true, the /api/cec/* endpoints are active and send
// commands to the launchscope-cec Unix socket at /run/launchscope-cec/cmd.sock.
type CECConfig struct {
	Enabled bool `json:"enabled"`
}

// defaults returns a Config with sane defaults applied.
func defaults() Config {
	return Config{
		API: APIConfig{
			Port: 8765,
		},
		CEC: CECConfig{
			Enabled: false,
		},
	}
}

// Validate returns an error if the Config contains invalid values.
func (c *Config) Validate() error {
	if c.API.Port < 1 || c.API.Port > 65535 {
		return fmt.Errorf("api.port must be 1–65535, got %d", c.API.Port)
	}
	if c.API.APIKey == "" {
		return fmt.Errorf("no API key could be resolved (set api.api_key or api.api_key_file in config)")
	}
	return nil
}

// ConfigDirPath returns the path to the launchscoped config directory
// ($XDG_CONFIG_HOME/launchscoped or ~/.config/launchscoped) without
// creating it.
func ConfigDirPath() (string, error) {
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", fmt.Errorf("cannot determine home directory: %w", err)
		}
		base = filepath.Join(home, ".config")
	}
	return filepath.Join(base, "launchscoped"), nil
}

// EnsureConfigDir returns the launchscoped config directory path and creates
// it if it does not already exist.
func EnsureConfigDir() (string, error) {
	dir, err := ConfigDirPath()
	if err != nil {
		return "", err
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", fmt.Errorf("cannot create config dir %s: %w", dir, err)
	}
	return dir, nil
}
