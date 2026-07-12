package events_test

import (
	"testing"
	"time"

	"github.com/ametis70/launchscope/server/internal/events"
)

func TestBus_PublishReceive(t *testing.T) {
	bus := events.NewBus()
	ch := bus.Subscribe()
	if ch == nil {
		t.Fatal("Subscribe returned nil")
	}
	defer bus.Unsubscribe(ch)

	bus.Publish(events.StateChanged, "payload")

	select {
	case ev := <-ch:
		if ev.Type != events.StateChanged {
			t.Errorf("got type %v, want %v", ev.Type, events.StateChanged)
		}
		if ev.Payload != "payload" {
			t.Errorf("got payload %v, want %q", ev.Payload, "payload")
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for event")
	}
}

func TestBus_MultipleSubscribers(t *testing.T) {
	bus := events.NewBus()
	ch1 := bus.Subscribe()
	ch2 := bus.Subscribe()
	defer bus.Unsubscribe(ch1)
	defer bus.Unsubscribe(ch2)

	bus.Publish(events.AudioChanged, 42)

	for _, ch := range []<-chan events.Event{ch1, ch2} {
		select {
		case ev := <-ch:
			if ev.Payload != 42 {
				t.Errorf("got payload %v, want 42", ev.Payload)
			}
		case <-time.After(time.Second):
			t.Fatal("timed out waiting for event on subscriber")
		}
	}
}

func TestBus_UnsubscribeStopsDelivery(t *testing.T) {
	bus := events.NewBus()
	ch := bus.Subscribe()

	bus.Unsubscribe(ch)

	// Channel should be closed after Unsubscribe.
	select {
	case _, ok := <-ch:
		if ok {
			t.Error("expected channel to be closed, got value")
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for channel close")
	}

	// Further publishes must not block or panic.
	bus.Publish(events.StateChanged, nil)
}

func TestBus_UnsubscribeNil(t *testing.T) {
	bus := events.NewBus()
	// Must not panic.
	bus.Unsubscribe(nil)
}

func TestBus_SlowSubscriberDropsEvents(t *testing.T) {
	bus := events.NewBus()
	ch := bus.Subscribe()
	defer bus.Unsubscribe(ch)

	// Fill the buffer completely then publish one more — should not block.
	done := make(chan struct{})
	go func() {
		defer close(done)
		for i := 0; i < 100; i++ {
			bus.Publish(events.StateChanged, i)
		}
	}()

	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("Publish blocked on slow subscriber")
	}
}

func TestBus_SubscriberCap(t *testing.T) {
	bus := events.NewBus()
	var chs []<-chan events.Event

	// Fill to cap.
	for i := 0; i < 64; i++ {
		ch := bus.Subscribe()
		if ch == nil {
			t.Fatalf("Subscribe returned nil at subscriber %d (before cap)", i)
		}
		chs = append(chs, ch)
	}
	defer func() {
		for _, ch := range chs {
			bus.Unsubscribe(ch)
		}
	}()

	// One over cap must return nil.
	if ch := bus.Subscribe(); ch != nil {
		bus.Unsubscribe(ch)
		t.Error("Subscribe should return nil when cap is reached")
	}
}

func TestBus_PublishNoSubscribers(t *testing.T) {
	bus := events.NewBus()
	// Must not panic with zero subscribers.
	bus.Publish(events.StateChanged, nil)
}
