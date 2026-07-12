package process

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/ametis70/launchscope/server/internal/apps"
)

// UIArgv builds the argv for launching the launchscope UI.
// launchscopeBin may be a single binary name ("launchscope") or a
// space-separated command ("love /path/to/ui") — it is split like an exec string.
// Note: LAUNCHSCOPE_MODE=server is injected as an environment variable by
// launchUI(), not here.
func UIArgv(launchscopeBin string) ([]string, error) {
	return splitExec(launchscopeBin)
}

// AppArgv builds the argv slice for launching a configured app.
// When gamescope is disabled the exec string is split directly.
// The schema mirrors lib/gamescope.lua in the UI.
func AppArgv(app *apps.App) ([]string, error) {
	gs := app.Gamescope

	if !gs.Enabled {
		return splitExec(app.Exec)
	}

	// Resolve output and inner resolutions.
	ow := gs.Output.Width
	oh := gs.Output.Height
	orr := gs.Output.Refresh
	if ow == 0 {
		ow = 1920
	}
	if oh == 0 {
		oh = 1080
	}
	if orr == 0 {
		orr = 60
	}

	iw := gs.Inner.Width
	ih := gs.Inner.Height
	if iw == 0 {
		iw = ow
	}
	if ih == 0 {
		ih = oh
	}

	args := []string{"gamescope"}

	if gs.Fullscreen {
		args = append(args, "-f")
	}

	args = append(args,
		"-W", itoa(ow),
		"-H", itoa(oh),
		"-w", itoa(iw),
		"-h", itoa(ih),
		"-r", itoa(orr),
	)

	// Upscaler filter and scaler.
	if gs.Filter != "" {
		scaler := gs.Scaler
		// Only auto-select a scaler when resolutions actually differ.
		if scaler == "" && (iw != ow || ih != oh) {
			scaler = "fit"
		}
		// Only pass -S when a scaler is meaningful (filter set and either an
		// explicit scaler was requested or resolutions differ).
		if scaler != "" {
			args = append(args, "-S", scaler)
		}
		args = append(args, "-F", gs.Filter)
	}

	if gs.Sharpness != nil {
		args = append(args, "--sharpness", itoa(*gs.Sharpness))
	}

	if gs.HDR {
		args = append(args, "--hdr-enabled")
	}
	if gs.AdaptiveSync {
		args = append(args, "--adaptive-sync")
	}
	if gs.ForceGrab {
		args = append(args, "--force-grab-cursor")
	}
	if gs.ExposeWayland {
		args = append(args, "--expose-wayland")
	}
	if gs.CompositeDebug {
		args = append(args, "--composite-debug")
	}
	if gs.MangoApp {
		args = append(args, "--mangoapp")
	}

	// Validate and append extra flags. Reject any element equal to "--" to
	// prevent injection that would move the app exec to the gamescope flags
	// side of the separator.
	for _, f := range gs.ExtraFlags {
		if f == "--" {
			return nil, fmt.Errorf("ExtraFlags must not contain \"--\" (app id %q)", app.ID)
		}
		args = append(args, f)
	}

	args = append(args, "--")

	execArgs, err := splitExec(app.Exec)
	if err != nil {
		return nil, fmt.Errorf("parsing exec for app %q: %w", app.ID, err)
	}
	args = append(args, execArgs...)

	return args, nil
}

// splitExec splits a shell-style command string into argv.
// Handles single/double quoted tokens; no variable expansion.
// Returns an error if the input contains an unclosed quote.
func splitExec(s string) ([]string, error) {
	var args []string
	var cur strings.Builder
	inQ := false
	qChar := rune(0)

	for _, r := range s {
		switch {
		case inQ && r == qChar:
			inQ = false
		case !inQ && (r == '\'' || r == '"'):
			inQ = true
			qChar = r
		case !inQ && r == ' ':
			if cur.Len() > 0 {
				args = append(args, cur.String())
				cur.Reset()
			}
		default:
			cur.WriteRune(r)
		}
	}

	if inQ {
		return nil, fmt.Errorf("unclosed quote in command string: %q", s)
	}

	if cur.Len() > 0 {
		args = append(args, cur.String())
	}
	return args, nil
}

func itoa(n int) string { return strconv.Itoa(n) }
