package system_test

import (
	"testing"

	"github.com/ametis70/launchscope/server/internal/system"
)

func TestRun_UnknownAction(t *testing.T) {
	err := system.Run("bogus")
	if err == nil {
		t.Error("expected error for unknown action")
	}
}

func TestRun_EmptyAction(t *testing.T) {
	err := system.Run("")
	if err == nil {
		t.Error("expected error for empty action")
	}
}

func TestRun_KnownActionsExist(t *testing.T) {
	// Verify the constants are defined and distinct.
	actions := []system.Action{
		system.ActionShutdown,
		system.ActionRestart,
		system.ActionSuspend,
	}
	seen := map[system.Action]bool{}
	for _, a := range actions {
		if seen[a] {
			t.Errorf("duplicate action value %q", a)
		}
		seen[a] = true
		if a == "" {
			t.Errorf("action constant is empty string")
		}
	}
}
