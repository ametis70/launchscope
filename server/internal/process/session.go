package process

import (
	"fmt"
	"os"
	"os/exec"
	"sync"
	"syscall"
	"time"
)

// pollInterval is how often Stop() checks whether the process group is gone
// after sending SIGTERM or SIGKILL.
const pollInterval = 50 * time.Millisecond

// killTimeout is the maximum time to wait for the process group to disappear
// after SIGKILL before giving up and returning an error.
const killTimeout = 5 * time.Second

// Session wraps a running os/exec.Cmd with process-group management and a
// graceful stop sequence: SIGTERM → wait → SIGKILL.
type Session struct {
	cmd  *exec.Cmd
	done chan struct{} // closed when cmd.Wait() returns
	err  error         // exit error from cmd.Wait(), guarded by mu
	mu   sync.Mutex
}

// Start launches the command described by argv[0] (the executable) and
// argv[1:] (arguments). The process is placed in its own process group so
// that a kill signal reaches gamescope and all of its children.
// extraEnv is a list of "KEY=VALUE" strings merged on top of the current env.
func Start(argv []string, extraEnv ...string) (*Session, error) {
	if len(argv) == 0 {
		return nil, fmt.Errorf("argv must not be empty")
	}
	cmd := exec.Command(argv[0], argv[1:]...)
	cmd.SysProcAttr = &syscall.SysProcAttr{
		Setpgid: true,
	}
	if len(extraEnv) > 0 {
		cmd.Env = append(os.Environ(), extraEnv...)
	}

	s := &Session{
		cmd:  cmd,
		done: make(chan struct{}),
	}

	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("starting %q: %w", argv[0], err)
	}

	go func() {
		// Hold the lock while waiting so that ExitError() cannot observe a
		// partially-written s.err. close(done) is inside the lock so that
		// Done() closing and s.err being readable are atomic from the
		// caller's perspective.
		s.mu.Lock()
		s.err = cmd.Wait()
		close(s.done)
		s.mu.Unlock()
	}()

	return s, nil
}

// Done returns a channel that is closed when the process exits.
func (s *Session) Done() <-chan struct{} { return s.done }

// ExitError returns the error from cmd.Wait() after Done() is closed.
func (s *Session) ExitError() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.err
}

// Pid returns the PID of the launched process, or 0 if unavailable.
func (s *Session) Pid() int {
	if s.cmd.Process == nil {
		return 0
	}
	return s.cmd.Process.Pid
}

// Stop gracefully terminates the process group.
//
//  1. Send SIGTERM to the entire process group.
//  2. Poll until the process group is gone or timeout elapses.
//  3. If still running, send SIGKILL to the process group and poll until gone
//     (up to killTimeout). Returns an error if the group survives SIGKILL.
//
// Polling the process group (kill -0) rather than waiting on s.done is
// intentional: s.done closes when the directly-tracked process (gamescope)
// exits, but child processes spawned by it (e.g. retroarch launched by
// pegasus-fe) may still be alive in the same group. Polling ensures we wait
// for the entire group, not just the top-level process.
func (s *Session) Stop(timeout time.Duration) error {
	pgid := s.cmd.Process.Pid // Setpgid=true means pgid == pid

	// SIGTERM to the whole process group (negative pgid).
	if err := syscall.Kill(-pgid, syscall.SIGTERM); err != nil {
		// ESRCH means no process in the group exists — already gone.
		if err != syscall.ESRCH {
			return fmt.Errorf("SIGTERM to pgid %d: %w", pgid, err)
		}
		return nil
	}

	// Poll until the process group is gone or the timeout expires.
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if err := syscall.Kill(-pgid, 0); err == syscall.ESRCH {
			return nil // entire group is gone
		}
		time.Sleep(pollInterval)
	}

	// Group still alive after timeout — escalate to SIGKILL.
	_ = syscall.Kill(-pgid, syscall.SIGKILL)

	// Poll until the group disappears, up to killTimeout.
	// An unbounded loop is unsafe: zombie grandchildren not reaped by
	// cmd.Wait() (which only reaps the direct child) could keep the group
	// alive indefinitely.
	killDeadline := time.Now().Add(killTimeout)
	for time.Now().Before(killDeadline) {
		if err := syscall.Kill(-pgid, 0); err == syscall.ESRCH {
			return nil
		}
		time.Sleep(pollInterval)
	}
	return fmt.Errorf("process group %d still alive after SIGKILL", pgid)
}
