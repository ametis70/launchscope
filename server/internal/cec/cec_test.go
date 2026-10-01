package cec

import "testing"

func TestNewInitialStateActive(t *testing.T) {
	state := New(true).GetState()
	if !state.TVOn {
		t.Error("TV should be assumed on")
	}
	if state.AVROn == nil || !*state.AVROn {
		t.Error("AVR should be assumed on")
	}
	if state.ActiveSource == nil || *state.ActiveSource != 1 {
		t.Error("active source should be this device (logical address 1)")
	}
	if !state.IsActiveSource {
		t.Error("this device should be assumed to be the active source")
	}
}

func TestNewInitialStateInactive(t *testing.T) {
	state := New(false).GetState()
	if state.TVOn || state.AVROn != nil || state.ActiveSource != nil || state.IsActiveSource {
		t.Errorf("expected unknown/inactive zero state, got %+v", state)
	}
}
