package apps_test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/ametis70/launchscope/server/internal/apps"
)

// ── ByID ─────────────────────────────────────────────────────────────────── //

func TestByID_Found(t *testing.T) {
	list := []apps.App{
		{ID: "kodi", Name: "Kodi", Exec: "kodi"},
		{ID: "steam", Name: "Steam", Exec: "steam"},
	}
	got := apps.ByID(list, "steam")
	if got == nil {
		t.Fatal("expected non-nil result")
	}
	if got.Name != "Steam" {
		t.Errorf("Name = %q, want %q", got.Name, "Steam")
	}
}

func TestByID_NotFound(t *testing.T) {
	list := []apps.App{{ID: "kodi", Name: "Kodi", Exec: "kodi"}}
	if got := apps.ByID(list, "missing"); got != nil {
		t.Errorf("expected nil, got %+v", got)
	}
}

func TestByID_EmptyList(t *testing.T) {
	if got := apps.ByID(nil, "any"); got != nil {
		t.Errorf("expected nil for empty list, got %+v", got)
	}
}

func TestByID_FirstMatch(t *testing.T) {
	// Linear scan — first matching ID wins.
	list := []apps.App{
		{ID: "a", Name: "First", Exec: "a"},
		{ID: "a", Name: "Second", Exec: "a"}, // duplicate, shouldn't happen but test behaviour
	}
	got := apps.ByID(list, "a")
	if got.Name != "First" {
		t.Errorf("Name = %q, want \"First\"", got.Name)
	}
}

// ── Loader ───────────────────────────────────────────────────────────────── //

func TestAppsLoader_MissingFile(t *testing.T) {
	l := apps.NewLoader(t.TempDir())
	list, err := l.Load()
	if err != nil {
		t.Fatalf("expected no error for missing apps.json, got %v", err)
	}
	if len(list) != 0 {
		t.Errorf("expected empty list, got %v", list)
	}
}

func TestAppsLoader_ValidFile(t *testing.T) {
	dir := t.TempDir()
	writeApps(t, dir, []apps.App{
		{ID: "kodi", Name: "Kodi", Exec: "kodi-standalone"},
	})

	l := apps.NewLoader(dir)
	list, err := l.Load()
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 1 || list[0].ID != "kodi" {
		t.Errorf("unexpected list: %v", list)
	}
}

func TestAppsLoader_Current(t *testing.T) {
	dir := t.TempDir()
	writeApps(t, dir, []apps.App{{ID: "x", Name: "X", Exec: "x"}})

	l := apps.NewLoader(dir)
	if l.Current() != nil {
		t.Error("Current() should be nil before Load()")
	}
	l.Load()
	if l.Current() == nil {
		t.Error("Current() should be non-nil after Load()")
	}
}

func TestAppsLoader_InvalidJSON(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "apps.json"), []byte("not json"), 0o644)

	l := apps.NewLoader(dir)
	_, err := l.Load()
	if err == nil {
		t.Error("expected error for invalid JSON")
	}
}

func TestAppsLoader_DuplicateID(t *testing.T) {
	dir := t.TempDir()
	writeApps(t, dir, []apps.App{
		{ID: "x", Name: "A", Exec: "a"},
		{ID: "x", Name: "B", Exec: "b"},
	})

	l := apps.NewLoader(dir)
	_, err := l.Load()
	if err == nil {
		t.Error("expected error for duplicate ID")
	}
}

func TestAppsLoader_EmptyID(t *testing.T) {
	dir := t.TempDir()
	writeApps(t, dir, []apps.App{
		{ID: "", Name: "NoID", Exec: "something"},
	})

	l := apps.NewLoader(dir)
	_, err := l.Load()
	if err == nil {
		t.Error("expected error for empty ID")
	}
}

func TestAppsLoader_EmptyExec(t *testing.T) {
	dir := t.TempDir()
	writeApps(t, dir, []apps.App{
		{ID: "x", Name: "X", Exec: ""},
	})

	l := apps.NewLoader(dir)
	_, err := l.Load()
	if err == nil {
		t.Error("expected error for empty Exec")
	}
}

func TestAppsLoader_MultipleApps(t *testing.T) {
	dir := t.TempDir()
	writeApps(t, dir, []apps.App{
		{ID: "a", Name: "A", Exec: "a"},
		{ID: "b", Name: "B", Exec: "b"},
		{ID: "c", Name: "C", Exec: "c"},
	})

	l := apps.NewLoader(dir)
	list, err := l.Load()
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 3 {
		t.Errorf("expected 3 apps, got %d", len(list))
	}
}

func TestAppsLoader_GamescopeConfig(t *testing.T) {
	dir := t.TempDir()
	sharpness := 5
	writeApps(t, dir, []apps.App{
		{
			ID:   "kodi",
			Name: "Kodi",
			Exec: "kodi-standalone",
			Gamescope: apps.GamescopeConfig{
				Enabled:    true,
				Fullscreen: true,
				Output:     apps.Resolution{Width: 3840, Height: 2160, Refresh: 60},
				Filter:     "fsr",
				Sharpness:  &sharpness,
				HDR:        true,
			},
		},
	})

	l := apps.NewLoader(dir)
	list, err := l.Load()
	if err != nil {
		t.Fatal(err)
	}
	gs := list[0].Gamescope
	if !gs.Enabled || !gs.Fullscreen || !gs.HDR {
		t.Errorf("gamescope config not loaded correctly: %+v", gs)
	}
	if gs.Output.Width != 3840 {
		t.Errorf("Output.Width = %d, want 3840", gs.Output.Width)
	}
	if gs.Filter != "fsr" {
		t.Errorf("Filter = %q, want \"fsr\"", gs.Filter)
	}
	if gs.Sharpness == nil || *gs.Sharpness != 5 {
		t.Errorf("Sharpness = %v, want 5", gs.Sharpness)
	}
}

// ── helper ───────────────────────────────────────────────────────────────── //

func writeApps(t *testing.T, dir string, list []apps.App) {
	t.Helper()
	data, err := json.Marshal(list)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "apps.json"), data, 0o644); err != nil {
		t.Fatal(err)
	}
}
