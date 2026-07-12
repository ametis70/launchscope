package apps

import (
	"errors"
	"fmt"
	"os"

	"github.com/ametis70/launchscope/server/internal/loader"
)

const appsFile = "apps.json"

// Loader reads the app list from disk and exposes it for concurrent access.
// It is a thin wrapper around loader.Loader[[]App] that adds app-specific
// post-processing (missing-file tolerance, validation).
type Loader struct {
	inner *loader.Loader[[]App]
}

// NewLoader creates a Loader rooted at dir.
func NewLoader(dir string) *Loader {
	return &Loader{inner: loader.New[[]App](dir, appsFile)}
}

// Load reads apps.json, validates it, and stores the result atomically.
// A missing apps.json is treated as an empty list rather than an error.
func (l *Loader) Load() ([]App, error) {
	result, err := l.inner.Load(func(list *[]App) error {
		// The generic loader leaves *list as nil when the file is absent
		// (os.ErrNotExist). Treat that as an empty list.
		if *list == nil {
			*list = []App{}
		}
		return validate(*list)
	})
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return []App{}, nil
		}
		return nil, fmt.Errorf("loading apps: %w", err)
	}
	return *result, nil
}

// Current returns the last successfully loaded app list.
func (l *Loader) Current() []App {
	p := l.inner.Current()
	if p == nil {
		return nil
	}
	return *p
}

// ── helpers ──────────────────────────────────────────────────────────────── //

// validate ensures all entries have non-empty, unique IDs and non-empty Exec.
func validate(list []App) error {
	seen := make(map[string]struct{}, len(list))
	for i, a := range list {
		if a.ID == "" {
			return fmt.Errorf("apps[%d].id must not be empty", i)
		}
		if _, dup := seen[a.ID]; dup {
			return fmt.Errorf("apps[%d].id %q is duplicated", i, a.ID)
		}
		seen[a.ID] = struct{}{}
		if a.Exec == "" {
			return fmt.Errorf("apps[%d].exec must not be empty", i)
		}
	}
	return nil
}
