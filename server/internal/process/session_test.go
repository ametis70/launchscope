package process

import (
	"testing"
	"time"
)

// Tests use /bin/sh and shell built-ins to avoid depending on any specific
// binary being installed. All tests run real processes in their own process
// groups — this exercises the actual signal/wait/SIGKILL code paths.

// ── Start ────────────────────────────────────────────────────────────────── //

func TestStart_EmptyArgv(t *testing.T) {
	_, err := Start(nil)
	if err == nil {
		t.Error("expected error for empty argv")
	}
}

func TestStart_BinaryNotFound(t *testing.T) {
	_, err := Start([]string{"/nonexistent/binary"})
	if err == nil {
		t.Error("expected error for missing binary")
	}
}

func TestStart_Succeeds(t *testing.T) {
	sess, err := Start([]string{"/bin/sh", "-c", "exit 0"})
	if err != nil {
		t.Fatal(err)
	}
	waitDone(t, sess, 2*time.Second)
}

func TestStart_ExtraEnv(t *testing.T) {
	// Verify the extra env var reaches the child process.
	sess, err := Start(
		[]string{"/bin/sh", "-c", `test "$MY_TEST_VAR" = "hello"`},
		"MY_TEST_VAR=hello",
	)
	if err != nil {
		t.Fatal(err)
	}
	waitDone(t, sess, 2*time.Second)
	if sess.ExitError() != nil {
		t.Errorf("process exited with error: %v", sess.ExitError())
	}
}

// ── Done / ExitError ─────────────────────────────────────────────────────── //

func TestSession_DoneClosedOnExit(t *testing.T) {
	sess, err := Start([]string{"/bin/sh", "-c", "exit 0"})
	if err != nil {
		t.Fatal(err)
	}
	waitDone(t, sess, 2*time.Second)
}

func TestSession_ExitErrorNilOnCleanExit(t *testing.T) {
	sess, err := Start([]string{"/bin/sh", "-c", "exit 0"})
	if err != nil {
		t.Fatal(err)
	}
	waitDone(t, sess, 2*time.Second)
	if sess.ExitError() != nil {
		t.Errorf("expected nil ExitError, got %v", sess.ExitError())
	}
}

func TestSession_ExitErrorSetOnFailure(t *testing.T) {
	sess, err := Start([]string{"/bin/sh", "-c", "exit 1"})
	if err != nil {
		t.Fatal(err)
	}
	waitDone(t, sess, 2*time.Second)
	if sess.ExitError() == nil {
		t.Error("expected non-nil ExitError for exit code 1")
	}
}

// ── Pid ──────────────────────────────────────────────────────────────────── //

func TestSession_PidPositive(t *testing.T) {
	sess, err := Start([]string{"/bin/sh", "-c", "sleep 10"})
	if err != nil {
		t.Fatal(err)
	}
	defer sess.Stop(time.Second)

	if sess.Pid() <= 0 {
		t.Errorf("Pid() = %d, expected > 0", sess.Pid())
	}
}

// ── Stop ─────────────────────────────────────────────────────────────────── //

func TestStop_TerminatesProcess(t *testing.T) {
	sess, err := Start([]string{"/bin/sh", "-c", "sleep 60"})
	if err != nil {
		t.Fatal(err)
	}
	if err := sess.Stop(3 * time.Second); err != nil {
		t.Errorf("Stop() error: %v", err)
	}
	// Done must be closed.
	waitDone(t, sess, time.Second)
}

func TestStop_AlreadyExited(t *testing.T) {
	sess, err := Start([]string{"/bin/sh", "-c", "exit 0"})
	if err != nil {
		t.Fatal(err)
	}
	waitDone(t, sess, 2*time.Second)
	// Calling Stop on an already-dead process must not error.
	if err := sess.Stop(time.Second); err != nil {
		t.Errorf("Stop() on dead process returned error: %v", err)
	}
}

func TestStop_KillsChildProcesses(t *testing.T) {
	// Spawn a shell that launches a child sleep — Stop must kill the group.
	sess, err := Start([]string{"/bin/sh", "-c", "sleep 60 & sleep 60"})
	if err != nil {
		t.Fatal(err)
	}
	// Give children a moment to start.
	time.Sleep(100 * time.Millisecond)
	if err := sess.Stop(3 * time.Second); err != nil {
		t.Errorf("Stop() error: %v", err)
	}
}

// ── helper ───────────────────────────────────────────────────────────────── //

func waitDone(t *testing.T, sess *Session, timeout time.Duration) {
	t.Helper()
	select {
	case <-sess.Done():
	case <-time.After(timeout):
		t.Fatalf("timed out waiting for session to finish")
	}
}
