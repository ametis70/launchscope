package process

import (
	"errors"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"github.com/ametis70/launchscope/server/internal/apps"
	"github.com/ametis70/launchscope/server/internal/events"
)

// ErrBusy is returned by LaunchApp when the manager is in a transitional state
// and cannot accept a new launch request. Callers can use errors.Is to
// distinguish this from other errors and return HTTP 409 Conflict.
var ErrBusy = errors.New("server is busy, retry shortly")

// State represents the current lifecycle state of the managed slot.
type State string

const (
	StateStarting   State = "starting"
	StateUIRunning  State = "ui_running"
	StateLaunching  State = "launching"
	StateAppRunning State = "app_running"
	StateStopping   State = "stopping"
)

const (
	stopTimeout = 5 * time.Second

	// seatRetryWindow: processes that exit faster than this are assumed to
	// have failed at DRM/seat acquisition (libseat_open_seat returns before
	// any rendering starts). Real app crashes take longer.
	// Seat acquisition failures exit in < 100ms; use 500ms as a safe margin.
	seatRetryWindow = 500 * time.Millisecond

	// seatRetryMax is the maximum number of seat-acquisition retries.
	seatRetryMax = 10

	// seatRetryBase is the initial backoff before the first retry.
	// It doubles each attempt up to seatRetryMax.
	seatRetryBase = 200 * time.Millisecond
)

// StatePayload is published on the event bus when state changes.
type StatePayload struct {
	State      State
	CurrentApp *apps.App
}

// Manager owns the single managed process slot and drives the lifecycle
// state machine.
type Manager struct {
	mu sync.Mutex

	state   State
	current *Session
	app     *apps.App

	appsLoader     *apps.Loader
	launchscopeBin string
	bus            *events.Bus
	log            *slog.Logger
}

// StatusSnapshot is an atomic view of the manager's state and current app,
// captured under a single lock acquisition to prevent inconsistency between
// the two fields.
type StatusSnapshot struct {
	State      State
	CurrentApp *apps.App
}

// NewManager creates a Manager. Call Start() to launch the initial UI session.
func NewManager(appsLoader *apps.Loader, launchscopeBin string, bus *events.Bus, log *slog.Logger) *Manager {
	return &Manager{
		state:          StateStarting,
		appsLoader:     appsLoader,
		launchscopeBin: launchscopeBin,
		bus:            bus,
		log:            log,
	}
}

func (m *Manager) Start() {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.launchUI()
}

func (m *Manager) CurrentState() State {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.state
}

func (m *Manager) CurrentApp() *apps.App {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.app
}

// Status returns state and current app under a single lock so the two fields
// are always consistent with each other.
func (m *Manager) Status() StatusSnapshot {
	m.mu.Lock()
	defer m.mu.Unlock()
	return StatusSnapshot{State: m.state, CurrentApp: m.app}
}

// LaunchApp stops the current process and launches the app with the given id.
func (m *Manager) LaunchApp(id string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	// Reject busy states and StateStarting (UI not yet running — killing it
	// mid-start would leave the manager with no process and no recovery path).
	if m.state == StateLaunching || m.state == StateStopping || m.state == StateStarting {
		return fmt.Errorf("%w (state=%s)", ErrBusy, m.state)
	}

	app := apps.ByID(m.appsLoader.Current(), id)
	if app == nil {
		return fmt.Errorf("no app with id %q", id)
	}

	argv, err := AppArgv(app)
	if err != nil {
		return fmt.Errorf("building argv for %q: %w", id, err)
	}

	m.setState(StateLaunching, nil)
	m.stopCurrent()

	sess, err := m.startWithRetry(argv)
	if err != nil {
		m.log.Error("failed to launch app after retries", "id", id, "err", err)
		m.setState(StateStarting, nil)
		m.log.Info("falling back to UI after failed app launch", "id", id)
		m.launchUI()
		return fmt.Errorf("launching %q: %w", id, err)
	}

	m.current = sess
	m.app = app
	m.setState(StateAppRunning, app)
	m.log.Info("app launched", "id", id, "pid", sess.Pid())

	go m.watch(sess)
	return nil
}

// Stop terminates the current app and relaunches the launcher UI.
func (m *Manager) Stop() {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.current == nil {
		return
	}
	m.setState(StateStopping, nil)
	m.stopCurrent()
	m.launchUI()
}

// ── internal (called with mu held) ────────────────────────────────────────── //

func (m *Manager) launchUI() {
	argv, err := UIArgv(m.launchscopeBin)
	if err != nil {
		m.log.Error("invalid launchscope binary path", "err", err)
		// Not recoverable without operator intervention — stay in StateStarting.
		m.setState(StateStarting, nil)
		return
	}

	sess, err := m.startWithRetry(argv, "LAUNCHSCOPE_MODE=server")
	if err != nil {
		m.log.Error("failed to launch UI after retries", "err", err)
		m.setState(StateStarting, nil)
		go func() {
			time.Sleep(2 * time.Second)
			m.mu.Lock()
			defer m.mu.Unlock()
			// Re-check state: another goroutine may have successfully
			// launched the UI during our sleep (e.g. a concurrent Start call).
			if m.state != StateStarting {
				return
			}
			m.launchUI()
		}()
		return
	}

	m.current = sess
	m.app = nil
	m.setState(StateUIRunning, nil)
	m.log.Info("UI launched", "pid", sess.Pid())

	go m.watch(sess)
}

// startWithRetry launches argv, retrying if the process exits within
// seatRetryWindow — which indicates the DRM/KMS seat was not yet free.
// The mutex is released during each retry delay so the server stays responsive.
// Called with mu held; returns with mu held.
func (m *Manager) startWithRetry(argv []string, extraEnv ...string) (*Session, error) {
	backoff := seatRetryBase

	for attempt := 0; attempt <= seatRetryMax; attempt++ {
		sess, err := Start(argv, extraEnv...)
		if err != nil {
			// Hard exec error (binary not found, etc.) — no point retrying.
			return nil, err
		}

		// Wait briefly to see if the process exits immediately (seat failure)
		// or stays alive (successful start).
		select {
		case <-sess.Done():
			// Process exited within seatRetryWindow.
			exitErr := sess.ExitError()
			if attempt == seatRetryMax {
				return nil, fmt.Errorf("process exited immediately after %d retries: %w", attempt, exitErr)
			}
			m.log.Warn("process exited during seat acquisition, retrying",
				"attempt", attempt+1, "max", seatRetryMax,
				"backoff", backoff, "err", exitErr)

			// Release mu during sleep so other API calls aren't blocked.
			m.mu.Unlock()
			time.Sleep(backoff)
			m.mu.Lock()

			// Another goroutine may have mutated state while we slept (e.g.
			// Stop() was called). Abort the retry loop in that case so we
			// don't launch a stale process on top of whatever took over.
			if m.state != StateLaunching && m.state != StateStarting {
				return nil, fmt.Errorf("%w: state changed to %q during seat retry", ErrBusy, m.state)
			}

			if backoff < 2*time.Second {
				backoff *= 2
			}

		case <-time.After(seatRetryWindow):
			// Still running after the window — seat acquired successfully.
			return sess, nil
		}
	}

	return nil, fmt.Errorf("seat acquisition failed after %d retries", seatRetryMax)
}

func (m *Manager) stopCurrent() {
	if m.current == nil {
		return
	}
	sess := m.current
	m.current = nil
	m.app = nil

	m.mu.Unlock()
	if err := sess.Stop(stopTimeout); err != nil {
		m.log.Warn("error stopping process", "err", err)
	}
	m.mu.Lock()
}

func (m *Manager) watch(sess *Session) {
	<-sess.Done()

	m.mu.Lock()
	defer m.mu.Unlock()

	if m.current != sess {
		return
	}

	exitErr := sess.ExitError()
	if exitErr != nil {
		m.log.Warn("managed process exited with error", "err", exitErr)
	} else {
		m.log.Info("managed process exited cleanly")
	}

	m.current = nil
	m.app = nil

	// Attempt to kill any remaining members of the process group (e.g.
	// children spawned by gamescope such as retroarch). This is best-effort:
	// the group leader has already exited, so SIGTERM goes to surviving
	// members only. Grandchildren that were adopted by init (pid 1) or
	// another subreaper will not be in this group and will not be reached.
	m.mu.Unlock()
	if err := sess.Stop(stopTimeout); err != nil {
		m.log.Warn("error stopping orphaned children", "err", err)
	}
	m.mu.Lock()

	m.launchUI()
}

func (m *Manager) setState(s State, app *apps.App) {
	m.state = s
	m.bus.Publish(events.StateChanged, StatePayload{State: s, CurrentApp: app})
}
