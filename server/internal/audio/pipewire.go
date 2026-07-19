package audio

import (
	"fmt"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"time"
)

// sinkCache caches the default sink name to avoid calling wpctl inspect on
// every volume poll. The name is refreshed at most once per sinkCacheTTL.
var sinkCache = struct {
	mu        sync.Mutex
	value     string
	fetchedAt time.Time
}{}

const sinkCacheTTL = 30 * time.Second

// State holds the last known PipeWire audio state.
type State struct {
	Volume   float64 // 0.0–1.5; 1.0 = 100%
	Muted    bool
	SinkName string
}

// GetVolume queries the current default sink volume and mute state via wpctl.
func GetVolume() (State, error) {
	out, err := wpctl("get-volume", "@DEFAULT_SINK@")
	if err != nil {
		return State{}, fmt.Errorf("wpctl get-volume: %w", err)
	}
	// Resolve the sink name outside parseVolume to keep parsing pure and avoid
	// acquiring the sink cache lock from within a future locked call path.
	sinkName, _ := GetSinkName()
	return parseVolume(out, sinkName)
}

// SetVolume sets the default sink to an absolute volume level (0.0–1.5).
func SetVolume(v float64) error {
	v = clamp(v, 0.0, 1.5)
	_, err := wpctl("set-volume", "@DEFAULT_SINK@", strconv.FormatFloat(v, 'f', 4, 64))
	return err
}

// AdjustVolume increases or decreases volume by delta, clamped to 0.0–1.5.
func AdjustVolume(delta float64) error {
	cur, err := GetVolume()
	if err != nil {
		return err
	}
	return SetVolume(cur.Volume + delta)
}

// SetMute sets the mute state of the default sink.
func SetMute(muted bool) error {
	arg := "0"
	if muted {
		arg = "1"
	}
	_, err := wpctl("set-mute", "@DEFAULT_SINK@", arg)
	return err
}

// ToggleMute toggles the mute state of the default sink.
func ToggleMute() error {
	_, err := wpctl("set-mute", "@DEFAULT_SINK@", "toggle")
	return err
}

// GetSinkName returns the display name of the current default audio sink.
// The result is cached for sinkCacheTTL to avoid a subprocess call on every
// volume poll. An empty result from wpctl is not cached so the next call
// retries immediately.
func GetSinkName() (string, error) {
	sinkCache.mu.Lock()
	defer sinkCache.mu.Unlock()

	if sinkCache.value != "" && time.Since(sinkCache.fetchedAt) < sinkCacheTTL {
		return sinkCache.value, nil
	}

	name, err := fetchSinkName()
	if err != nil {
		return "", err
	}
	if name != "" {
		sinkCache.value = name
		sinkCache.fetchedAt = time.Now()
	}
	return name, nil
}

// fetchSinkName queries wpctl inspect @DEFAULT_SINK@ and extracts the
// node.description field, which is the human-readable sink display name.
func fetchSinkName() (string, error) {
	out, err := wpctl("inspect", "@DEFAULT_SINK@")
	if err != nil {
		return "", fmt.Errorf("wpctl inspect: %w", err)
	}
	return parseInspectDescription(out), nil
}

// ── helpers ──────────────────────────────────────────────────────────────── //

func wpctl(args ...string) (string, error) {
	out, err := exec.Command("wpctl", args...).Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

// parseVolume parses output like:
//
//	"Volume: 0.72"
//	"Volume: 0.72 [MUTED]"
func parseVolume(s, sinkName string) (State, error) {
	if s == "" {
		return State{}, fmt.Errorf("no output from wpctl")
	}
	s = strings.TrimPrefix(s, "Volume: ")
	muted := strings.Contains(s, "[MUTED]")
	s = strings.TrimSpace(strings.ReplaceAll(s, "[MUTED]", ""))

	if s == "" {
		return State{}, fmt.Errorf("empty volume value")
	}

	v, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return State{}, fmt.Errorf("cannot parse volume %q: %w", s, err)
	}

	return State{Volume: v, Muted: muted, SinkName: sinkName}, nil
}

// parseInspectDescription extracts the node.description value from
// `wpctl inspect` output. Lines look like:
//
//   - node.description = "Built-in Audio Digital Surround 5.1 (HDMI)"
//     node.description = "Some Sink"
//
// The asterisk prefix marks the active/default property; both forms are handled.
func parseInspectDescription(s string) string {
	for _, line := range strings.Split(s, "\n") {
		trimmed := strings.TrimSpace(line)
		trimmed = strings.TrimPrefix(trimmed, "* ")
		if !strings.HasPrefix(trimmed, "node.description") {
			continue
		}
		if idx := strings.Index(trimmed, "\""); idx != -1 {
			val := trimmed[idx+1:]
			if end := strings.LastIndex(val, "\""); end != -1 {
				return val[:end]
			}
		}
	}
	return ""
}

func clamp(v, lo, hi float64) float64 {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}
