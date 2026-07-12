package loader_test

import (
	"encoding/json"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"testing"

	"github.com/ametis70/launchscope/server/internal/loader"
)

type testVal struct {
	Name  string `json:"name"`
	Count int    `json:"count"`
}

// ── Load ─────────────────────────────────────────────────────────────────── //

func TestLoad_ReadsFile(t *testing.T) {
	dir := t.TempDir()
	writeJSON(t, filepath.Join(dir, "data.json"), testVal{Name: "hello", Count: 42})

	l := loader.New[testVal](dir, "data.json")
	got, err := l.Load(nil)
	if err != nil {
		t.Fatal(err)
	}
	if got.Name != "hello" || got.Count != 42 {
		t.Errorf("got %+v", got)
	}
}

func TestLoad_MissingFileZeroValue(t *testing.T) {
	dir := t.TempDir()
	l := loader.New[testVal](dir, "missing.json")

	got, err := l.Load(nil)
	if err != nil {
		t.Fatal(err)
	}
	if got.Name != "" || got.Count != 0 {
		t.Errorf("expected zero value, got %+v", got)
	}
}

func TestLoad_ProcessFnCalled(t *testing.T) {
	dir := t.TempDir()
	writeJSON(t, filepath.Join(dir, "data.json"), testVal{Name: "raw"})

	l := loader.New[testVal](dir, "data.json")
	called := false
	_, err := l.Load(func(v *testVal) error {
		called = true
		v.Name = "processed"
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if !called {
		t.Error("process function was not called")
	}
	if l.Current().Name != "processed" {
		t.Errorf("Current().Name = %q, want \"processed\"", l.Current().Name)
	}
}

func TestLoad_ProcessFnError(t *testing.T) {
	dir := t.TempDir()
	writeJSON(t, filepath.Join(dir, "data.json"), testVal{})

	l := loader.New[testVal](dir, "data.json")
	_, err := l.Load(func(v *testVal) error {
		return errors.New("validation failed")
	})
	if err == nil {
		t.Error("expected error from process function")
	}
}

func TestLoad_InvalidJSON(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "bad.json"), []byte("{not valid json"), 0o644)

	l := loader.New[testVal](dir, "bad.json")
	_, err := l.Load(nil)
	if err == nil {
		t.Error("expected error for invalid JSON")
	}
}

func TestLoad_CurrentNilBeforeLoad(t *testing.T) {
	l := loader.New[testVal](t.TempDir(), "data.json")
	if l.Current() != nil {
		t.Error("Current() should be nil before Load()")
	}
}

func TestLoad_CurrentUpdatedAfterLoad(t *testing.T) {
	dir := t.TempDir()
	writeJSON(t, filepath.Join(dir, "data.json"), testVal{Name: "v1"})

	l := loader.New[testVal](dir, "data.json")
	if _, err := l.Load(nil); err != nil {
		t.Fatal(err)
	}
	if l.Current() == nil || l.Current().Name != "v1" {
		t.Errorf("Current() = %v", l.Current())
	}

	// Overwrite file and reload.
	writeJSON(t, filepath.Join(dir, "data.json"), testVal{Name: "v2"})
	if _, err := l.Load(nil); err != nil {
		t.Fatal(err)
	}
	if l.Current().Name != "v2" {
		t.Errorf("Current().Name = %q after reload, want \"v2\"", l.Current().Name)
	}
}

func TestLoad_Dir(t *testing.T) {
	dir := t.TempDir()
	l := loader.New[testVal](dir, "x.json")
	if l.Dir() != dir {
		t.Errorf("Dir() = %q, want %q", l.Dir(), dir)
	}
}

// ── ReadJSON ─────────────────────────────────────────────────────────────── //

func TestReadJSON_ReadsFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "data.json")
	writeJSON(t, path, testVal{Name: "hi", Count: 7})

	got, err := loader.ReadJSON[testVal](path)
	if err != nil {
		t.Fatal(err)
	}
	if got.Name != "hi" || got.Count != 7 {
		t.Errorf("got %+v", got)
	}
}

func TestReadJSON_MissingFile(t *testing.T) {
	_, err := loader.ReadJSON[testVal](filepath.Join(t.TempDir(), "nope.json"))
	if err == nil {
		t.Error("expected error for missing file")
	}
}

// ── WriteJSONAtomic ──────────────────────────────────────────────────────── //

func TestWriteJSONAtomic_WritesCorrectly(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "out.json")

	v := testVal{Name: "written", Count: 99}
	if err := loader.WriteJSONAtomic(path, v, 0o644); err != nil {
		t.Fatal(err)
	}

	var got testVal
	data, _ := os.ReadFile(path)
	json.Unmarshal(data, &got)
	if got.Name != "written" || got.Count != 99 {
		t.Errorf("got %+v", got)
	}
}

func TestWriteJSONAtomic_AppliesPermission(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "secret.json")

	if err := loader.WriteJSONAtomic(path, testVal{}, 0o600); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != fs.FileMode(0o600) {
		t.Errorf("mode = %v, want 0600", info.Mode().Perm())
	}
}

func TestWriteJSONAtomic_Overwrites(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "out.json")

	loader.WriteJSONAtomic(path, testVal{Name: "first"}, 0o644)
	loader.WriteJSONAtomic(path, testVal{Name: "second"}, 0o644)

	got, _ := loader.ReadJSON[testVal](path)
	if got.Name != "second" {
		t.Errorf("got %q, want \"second\"", got.Name)
	}
}

func TestWriteJSONAtomic_NoTempFileLeft(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "out.json")

	loader.WriteJSONAtomic(path, testVal{}, 0o644)

	entries, _ := os.ReadDir(dir)
	for _, e := range entries {
		if e.Name() != "out.json" {
			t.Errorf("unexpected file in dir: %q", e.Name())
		}
	}
}

// ── helper ───────────────────────────────────────────────────────────────── //

func writeJSON(t *testing.T, path string, v any) {
	t.Helper()
	data, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, data, 0o644); err != nil {
		t.Fatal(err)
	}
}
