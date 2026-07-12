package system

import (
	"fmt"
	"os/exec"
	"strings"
)

// Action represents a system power action.
type Action string

const (
	ActionShutdown Action = "shutdown"
	ActionRestart  Action = "restart"
	ActionSuspend  Action = "suspend"
)

// Run executes the appropriate systemctl command for the given action.
//
// Note: for ActionShutdown and ActionRestart the system is terminated before
// systemctl returns, so CombinedOutput() will not return on success — the
// calling HTTP handler's connection will be dropped by the kernel. This is
// expected behaviour, not a hang.
func Run(action Action) error {
	var arg string
	switch action {
	case ActionShutdown:
		arg = "poweroff"
	case ActionRestart:
		arg = "reboot"
	case ActionSuspend:
		arg = "suspend"
	default:
		return fmt.Errorf("unknown power action %q", action)
	}

	cmd := exec.Command("systemctl", arg)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("systemctl %s: %w — %s", arg, err, strings.TrimSpace(string(out)))
	}
	return nil
}
