package audio

import (
	"context"
	"log/slog"
	"time"

	"github.com/ametis70/launchscope/server/internal/events"
)

// StartMonitor polls PipeWire every interval and publishes an AudioChanged
// event on bus whenever the volume or mute state changes.
//
// The goroutine runs until ctx is cancelled, allowing clean shutdown.
// SinkName is included in the comparison so a device rename also triggers
// an event even if volume and mute are unchanged — this keeps connected
// clients up to date when the user switches audio output.
func StartMonitor(ctx context.Context, interval time.Duration, bus *events.Bus, log *slog.Logger) {
	go func() {
		var last State
		first := true

		ticker := time.NewTicker(interval)
		defer ticker.Stop()

		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				cur, err := GetVolume()
				if err != nil {
					// Log at Debug — transient failures (PipeWire not ready,
					// no default sink) are expected at startup and during
					// app transitions.
					log.Debug("audio monitor: GetVolume failed", "err", err)
					continue
				}
				if first || cur != last {
					last = cur
					first = false
					bus.Publish(events.AudioChanged, cur)
				}
			}
		}
	}()
}
