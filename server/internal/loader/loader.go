// Package loader provides a generic file-backed loader for JSON-serialisable
// types. It handles reading, atomic in-memory storage, and atomic disk writes.
//
// Usage:
//
//	l := loader.New[MyType](dir, "file.json")
//	value, err := l.Load(func(v *MyType) error {
//	    // post-read: apply defaults, validate, etc.
//	    return nil
//	})
//	current := l.Current() // safe to call from any goroutine
package loader

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sync/atomic"
)

// Loader holds the last successfully loaded value of type T in an atomic
// pointer so Current() is safe to call concurrently from request handlers.
type Loader[T any] struct {
	dir      string
	filename string
	ptr      atomic.Pointer[T]
}

// New creates a Loader that reads from dir/filename.
func New[T any](dir, filename string) *Loader[T] {
	return &Loader[T]{dir: dir, filename: filename}
}

// Dir returns the directory this loader is rooted at.
func (l *Loader[T]) Dir() string { return l.dir }

// Load reads the file, unmarshals it into T, calls process (for
// caller-specific post-processing such as defaults and validation), then
// stores the result atomically. Returns a pointer to the stored value.
//
// If the file does not exist, Load calls process with the zero value of T so
// the caller can decide whether that is an error or a valid empty state.
func (l *Loader[T]) Load(process func(*T) error) (*T, error) {
	path := filepath.Join(l.dir, l.filename)

	var value T
	data, err := os.ReadFile(path)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return nil, fmt.Errorf("reading %s: %w", l.filename, err)
	}
	if err == nil {
		if err := json.Unmarshal(data, &value); err != nil {
			return nil, fmt.Errorf("parsing %s: %w", l.filename, err)
		}
	}
	// err is os.ErrNotExist: value stays as zero value of T; process decides.

	if process != nil {
		if err := process(&value); err != nil {
			return nil, err
		}
	}

	l.ptr.Store(&value)
	return &value, nil
}

// Current returns the last successfully loaded value, or nil if Load has not
// been called yet.
func (l *Loader[T]) Current() *T {
	return l.ptr.Load()
}

// ReadJSON reads path and unmarshals it into T. It is a stateless helper for
// callers that need a one-shot read without a Loader instance.
func ReadJSON[T any](path string) (T, error) {
	var zero T
	data, err := os.ReadFile(path)
	if err != nil {
		return zero, err
	}
	var v T
	if err := json.Unmarshal(data, &v); err != nil {
		return zero, err
	}
	return v, nil
}

// WriteJSONAtomic marshals v to JSON and writes it to path via a uniquely
// named temp file + rename so a crash mid-write never leaves a corrupt file
// and concurrent writes to the same path do not race on the temp file.
// perm is applied to the temp file before rename so the target inherits the
// intended mode.
func WriteJSONAtomic(path string, v any, perm fs.FileMode) error {
	data, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	dir := filepath.Dir(path)
	base := filepath.Base(path)
	tmp, err := os.CreateTemp(dir, base+"*.tmp")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	// Best-effort cleanup on any error path.
	defer func() {
		if tmpName != "" {
			_ = os.Remove(tmpName) // best-effort cleanup
		}
	}()
	if err := tmp.Chmod(perm); err != nil {
		_ = tmp.Close()
		return err
	}
	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Rename(tmpName, path); err != nil {
		return err
	}
	tmpName = "" // rename succeeded; suppress deferred Remove
	return nil
}
