package process

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/ametis70/launchscope/server/internal/apps"
	"github.com/ametis70/launchscope/server/internal/events"
)

func mustWriteFile(t *testing.T, path string, data []byte) {
	t.Helper()
	if err := os.WriteFile(path, data, 0o644); err != nil {
		t.Fatal(err)
	}
}

// newTestManager builds a Manager with a fake launchscope binary that exits
// immediately. Tests that need the UI to stay alive should override the bin.
func newTestManager(t *testing.T, bin string) (*Manager, *events.Bus, string) {
	t.Helper()
	dir := t.TempDir()

	// Write a minimal apps.json.
	appsData, _ := json.Marshal([]apps.App{
		{ID: "testapp", Name: "Test App", Exec: bin},
	})
	mustWriteFile(t, filepath.Join(dir, "apps.json"), appsData)

	al := apps.NewLoader(dir)
	if _, err := al.Load(); err != nil {
		t.Fatal(err)
	}

	bus := events.NewBus()
	log := newNopLogger()
	mgr := NewManager(al, bin, bus, log)
	return mgr, bus, dir
}

// stayAlive returns a shell command string that stays alive until SIGTERM.
const stayAlive = "/bin/sh -c 'trap exit TERM; sleep 60 & wait'"

// exitImmediately exits with code 0 right away.
const exitImmediately = "/bin/sh -c 'exit 0'"

// ── Start / initial state ─────────────────────────────────────────────────  //

func TestManager_InitialStateIsStarting(t *testing.T) {
	mgr, _, _ := newTestManager(t, exitImmediately)
	if mgr.CurrentState() != StateStarting {
		t.Errorf("state = %q, want %q", mgr.CurrentState(), StateStarting)
	}
}

func TestManager_StartTransitionsToUIRunning(t *testing.T) {
	mgr, _, _ := newTestManager(t, stayAlive)
	mgr.Start()
	waitState(t, mgr, StateUIRunning, 3*time.Second)
}

func TestManager_StatusConsistent(t *testing.T) {
	mgr, _, _ := newTestManager(t, stayAlive)
	mgr.Start()
	waitState(t, mgr, StateUIRunning, 3*time.Second)

	snap := mgr.Status()
	if snap.State != StateUIRunning {
		t.Errorf("snap.State = %q", snap.State)
	}
	if snap.CurrentApp != nil {
		t.Errorf("snap.CurrentApp should be nil in UI mode")
	}
}

// ── LaunchApp ─────────────────────────────────────────────────────────────  //

func TestManager_LaunchApp_NotFoundReturnsError(t *testing.T) {
	mgr, _, _ := newTestManager(t, stayAlive)
	mgr.Start()
	waitState(t, mgr, StateUIRunning, 3*time.Second)

	err := mgr.LaunchApp("nonexistent")
	if err == nil {
		t.Error("expected error for missing app id")
	}
}

func TestManager_LaunchApp_BusyReturnsErrBusy(t *testing.T) {
	mgr, _, _ := newTestManager(t, stayAlive)
	// Don't call Start — state is Starting, which is a busy state.
	err := mgr.LaunchApp("testapp")
	if !errors.Is(err, ErrBusy) {
		t.Errorf("expected ErrBusy, got %v", err)
	}
}

func TestManager_LaunchApp_Succeeds(t *testing.T) {
	dir := t.TempDir()

	appsData, _ := json.Marshal([]apps.App{
		{ID: "ui", Name: "UI", Exec: stayAlive},
		{ID: "testapp", Name: "Test App", Exec: stayAlive},
	})
	mustWriteFile(t, filepath.Join(dir, "apps.json"), appsData)
	al := apps.NewLoader(dir)
	if _, err := al.Load(); err != nil {
		t.Fatal(err)
	}

	bus := events.NewBus()
	mgr2 := NewManager(al, stayAlive, bus, newNopLogger())
	mgr2.Start()
	waitState(t, mgr2, StateUIRunning, 3*time.Second)

	if err := mgr2.LaunchApp("testapp"); err != nil {
		t.Fatal(err)
	}
	waitState(t, mgr2, StateAppRunning, 3*time.Second)

	snap := mgr2.Status()
	if snap.CurrentApp == nil || snap.CurrentApp.ID != "testapp" {
		t.Errorf("CurrentApp = %v, want testapp", snap.CurrentApp)
	}

	mgr2.Stop()
}

// ── Stop ─────────────────────────────────────────────────────────────────── //

func TestManager_Stop_ReturnsToUIRunning(t *testing.T) {
	dir := t.TempDir()

	appsData, _ := json.Marshal([]apps.App{
		{ID: "testapp", Name: "Test App", Exec: stayAlive},
	})
	mustWriteFile(t, filepath.Join(dir, "apps.json"), appsData)
	al := apps.NewLoader(dir)
	if _, err := al.Load(); err != nil {
		t.Fatal(err)
	}

	bus := events.NewBus()
	mgr2 := NewManager(al, stayAlive, bus, newNopLogger())
	mgr2.Start()
	waitState(t, mgr2, StateUIRunning, 3*time.Second)

	if err := mgr2.LaunchApp("testapp"); err != nil {
		t.Fatal(err)
	}
	waitState(t, mgr2, StateAppRunning, 3*time.Second)

	mgr2.Stop()
	waitState(t, mgr2, StateUIRunning, 5*time.Second)

	// Cleanup the background UI.
	mgr2.mu.Lock()
	if mgr2.current != nil {
		sess := mgr2.current
		mgr2.mu.Unlock()
		if err := sess.Stop(time.Second); err != nil {
			t.Fatal(err)
		}
	} else {
		mgr2.mu.Unlock()
	}
}

// ── Bus events ───────────────────────────────────────────────────────────── //

func TestManager_StateChangedPublishedOnStart(t *testing.T) {
	bus := events.NewBus()
	ch := bus.Subscribe()
	defer bus.Unsubscribe(ch)

	dir := t.TempDir()
	mustWriteFile(t, filepath.Join(dir, "apps.json"), []byte("[]"))
	al := apps.NewLoader(dir)
	if _, err := al.Load(); err != nil {
		t.Fatal(err)
	}

	mgr := NewManager(al, stayAlive, bus, newNopLogger())
	mgr.Start()

	// Should receive at least one StateChanged event.
	timeout := time.After(3 * time.Second)
	for {
		select {
		case ev := <-ch:
			if ev.Type == events.StateChanged {
				mgr.Stop()
				return
			}
		case <-timeout:
			t.Fatal("timed out waiting for StateChanged event")
		}
	}
}

// ── helpers ──────────────────────────────────────────────────────────────── //

func waitState(t *testing.T, mgr *Manager, want State, timeout time.Duration) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if mgr.CurrentState() == want {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for state %q, got %q", want, mgr.CurrentState())
}
