package events

import "sync"

// Type identifies the kind of event published on the Bus.
type Type int

const (
	StateChanged Type = iota // process.Manager state changed
	AudioChanged             // PipeWire audio state changed
)

// Event carries a typed payload between internal components.
type Event struct {
	Type    Type
	Payload any
}

// subBufSize is the capacity of each subscriber's event channel.
// Sized to absorb a burst of rapid state changes (e.g. launch → running)
// without dropping events on a normally-responsive subscriber.
const subBufSize = 16

// maxSubscribers is a safety cap on the number of concurrent subscribers.
// Each WebSocket connection creates one subscriber; this prevents unbounded
// growth if connections accumulate (e.g. a reconnect loop).
const maxSubscribers = 64

// Bus is a simple in-process publish/subscribe hub.
// Subscribers receive events on a buffered channel. Slow subscribers
// that fill their buffer have their event dropped rather than blocking
// the publisher.
type Bus struct {
	mu   sync.RWMutex
	subs []chan Event
}

// NewBus creates a ready-to-use Bus.
func NewBus() *Bus { return &Bus{} }

// Subscribe returns a new channel that will receive all future events.
// Returns nil if the subscriber cap (maxSubscribers) has been reached.
// The caller must call Unsubscribe when done to avoid a goroutine leak.
func (b *Bus) Subscribe() <-chan Event {
	b.mu.Lock()
	defer b.mu.Unlock()
	if len(b.subs) >= maxSubscribers {
		return nil
	}
	ch := make(chan Event, subBufSize)
	b.subs = append(b.subs, ch)
	return ch
}

// Unsubscribe removes a previously subscribed channel and closes it.
// The comparison works because a receive-only channel value is comparable to
// its bidirectional origin in Go — the identity check is well-defined.
func (b *Bus) Unsubscribe(ch <-chan Event) {
	if ch == nil {
		return
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	for i, s := range b.subs {
		if s == ch {
			b.subs = append(b.subs[:i], b.subs[i+1:]...)
			close(s)
			return
		}
	}
}

// Publish sends an event to all current subscribers.
// Delivery is non-blocking: a subscriber whose buffer is full is skipped.
func (b *Bus) Publish(t Type, payload any) {
	ev := Event{Type: t, Payload: payload}
	b.mu.RLock()
	defer b.mu.RUnlock()
	for _, ch := range b.subs {
		select {
		case ch <- ev:
		default:
		}
	}
}
