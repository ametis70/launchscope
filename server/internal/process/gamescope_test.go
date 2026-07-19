package process

import (
	"strings"
	"testing"

	"github.com/ametis70/launchscope/server/internal/apps"
)

// ── splitExec ────────────────────────────────────────────────────────────── //

func TestSplitExec_Simple(t *testing.T) {
	got, err := splitExec("love /path/to/ui")
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"love", "/path/to/ui"}
	assertStringSlice(t, got, want)
}

func TestSplitExec_SingleQuotes(t *testing.T) {
	got, err := splitExec("cmd 'arg with spaces'")
	if err != nil {
		t.Fatal(err)
	}
	assertStringSlice(t, got, []string{"cmd", "arg with spaces"})
}

func TestSplitExec_DoubleQuotes(t *testing.T) {
	got, err := splitExec(`cmd "arg with spaces"`)
	if err != nil {
		t.Fatal(err)
	}
	assertStringSlice(t, got, []string{"cmd", "arg with spaces"})
}

func TestSplitExec_Empty(t *testing.T) {
	got, err := splitExec("")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 0 {
		t.Errorf("expected empty slice, got %v", got)
	}
}

func TestSplitExec_UnclosedQuoteErrors(t *testing.T) {
	_, err := splitExec(`cmd "unclosed`)
	if err == nil {
		t.Error("expected error for unclosed quote, got nil")
	}
}

func TestSplitExec_MultipleSpaces(t *testing.T) {
	got, err := splitExec("a  b   c")
	if err != nil {
		t.Fatal(err)
	}
	assertStringSlice(t, got, []string{"a", "b", "c"})
}

// ── UIArgv ───────────────────────────────────────────────────────────────── //

func TestUIArgv_SingleToken(t *testing.T) {
	got, err := UIArgv("launchscope")
	if err != nil {
		t.Fatal(err)
	}
	assertStringSlice(t, got, []string{"launchscope"})
}

func TestUIArgv_TwoTokens(t *testing.T) {
	got, err := UIArgv("love /path/to/launchscope.love")
	if err != nil {
		t.Fatal(err)
	}
	assertStringSlice(t, got, []string{"love", "/path/to/launchscope.love"})
}

// ── AppArgv ──────────────────────────────────────────────────────────────── //

func TestAppArgv_GamescopeDisabled(t *testing.T) {
	app := &apps.App{
		ID:   "test",
		Exec: "kodi-standalone",
		Gamescope: apps.GamescopeConfig{
			Enabled: false,
		},
	}
	got, err := AppArgv(app)
	if err != nil {
		t.Fatal(err)
	}
	assertStringSlice(t, got, []string{"kodi-standalone"})
}

func TestAppArgv_GamescopeEnabled_Defaults(t *testing.T) {
	app := &apps.App{
		ID:   "test",
		Exec: "kodi-standalone",
		Gamescope: apps.GamescopeConfig{
			Enabled:    true,
			Fullscreen: true,
		},
	}
	got, err := AppArgv(app)
	if err != nil {
		t.Fatal(err)
	}
	// Must start with gamescope and -f.
	if got[0] != "gamescope" {
		t.Errorf("argv[0] = %q, want \"gamescope\"", got[0])
	}
	assertContains(t, got, "-f")
	// Defaults: 1920x1080@60.
	assertContains(t, got, "-W")
	assertNextEq(t, got, "-W", "1920")
	assertContains(t, got, "-H")
	assertNextEq(t, got, "-H", "1080")
	assertContains(t, got, "-r")
	assertNextEq(t, got, "-r", "60")
	// Separator present.
	assertContains(t, got, "--")
	// Exec at end.
	if got[len(got)-1] != "kodi-standalone" {
		t.Errorf("last arg = %q, want \"kodi-standalone\"", got[len(got)-1])
	}
}

func TestAppArgv_GamescopeEnabled_ExplicitResolution(t *testing.T) {
	app := &apps.App{
		ID:   "test",
		Exec: "app",
		Gamescope: apps.GamescopeConfig{
			Enabled: true,
			Output:  apps.Resolution{Width: 3840, Height: 2160, Refresh: 60},
		},
	}
	got, err := AppArgv(app)
	if err != nil {
		t.Fatal(err)
	}
	assertNextEq(t, got, "-W", "3840")
	assertNextEq(t, got, "-H", "2160")
	assertNextEq(t, got, "-r", "60")
}

func TestAppArgv_GamescopeEnabled_InnerResolutionDefaults(t *testing.T) {
	app := &apps.App{
		ID:   "test",
		Exec: "app",
		Gamescope: apps.GamescopeConfig{
			Enabled: true,
			Output:  apps.Resolution{Width: 1920, Height: 1080, Refresh: 60},
			// Inner zero — should default to Output.
		},
	}
	got, err := AppArgv(app)
	if err != nil {
		t.Fatal(err)
	}
	assertNextEq(t, got, "-w", "1920")
	assertNextEq(t, got, "-h", "1080")
}

func TestAppArgv_GamescopeEnabled_FilterWithScaling(t *testing.T) {
	iw, ih := 1280, 720
	ow, oh := 1920, 1080
	app := &apps.App{
		ID:   "test",
		Exec: "app",
		Gamescope: apps.GamescopeConfig{
			Enabled: true,
			Output:  apps.Resolution{Width: ow, Height: oh, Refresh: 60},
			Inner:   apps.InnerResolution{Width: iw, Height: ih},
			Filter:  "fsr",
		},
	}
	got, err := AppArgv(app)
	if err != nil {
		t.Fatal(err)
	}
	// Should auto-select "fit" scaler when inner != output and no explicit scaler.
	assertContains(t, got, "-S")
	assertNextEq(t, got, "-S", "fit")
	assertContains(t, got, "-F")
	assertNextEq(t, got, "-F", "fsr")
}

func TestAppArgv_GamescopeEnabled_FilterNoScalingOmitsS(t *testing.T) {
	app := &apps.App{
		ID:   "test",
		Exec: "app",
		Gamescope: apps.GamescopeConfig{
			Enabled: true,
			Output:  apps.Resolution{Width: 1920, Height: 1080, Refresh: 60},
			Filter:  "linear",
			// Inner same as output — no -S should be emitted.
		},
	}
	got, err := AppArgv(app)
	if err != nil {
		t.Fatal(err)
	}
	for _, a := range got {
		if a == "-S" {
			t.Error("expected no -S flag when inner == output and no explicit scaler")
		}
	}
	assertContains(t, got, "-F")
}

func TestAppArgv_GamescopeEnabled_ExplicitScaler(t *testing.T) {
	app := &apps.App{
		ID:   "test",
		Exec: "app",
		Gamescope: apps.GamescopeConfig{
			Enabled: true,
			Output:  apps.Resolution{Width: 1920, Height: 1080, Refresh: 60},
			Filter:  "nis",
			Scaler:  "fill",
		},
	}
	got, err := AppArgv(app)
	if err != nil {
		t.Fatal(err)
	}
	assertNextEq(t, got, "-S", "fill")
}

func TestAppArgv_GamescopeEnabled_BoolFlags(t *testing.T) {
	sharpness := 10
	app := &apps.App{
		ID:   "test",
		Exec: "app",
		Gamescope: apps.GamescopeConfig{
			Enabled:        true,
			HDR:            true,
			AdaptiveSync:   true,
			ForceGrab:      true,
			ExposeWayland:  true,
			CompositeDebug: true,
			MangoApp:       true,
			Sharpness:      &sharpness,
		},
	}
	got, err := AppArgv(app)
	if err != nil {
		t.Fatal(err)
	}
	for _, flag := range []string{"--hdr-enabled", "--adaptive-sync", "--force-grab-cursor", "--expose-wayland", "--composite-debug", "--mangoapp"} {
		assertContains(t, got, flag)
	}
	assertNextEq(t, got, "--sharpness", "10")
}

func TestAppArgv_ExtraFlagsDashDashRejected(t *testing.T) {
	app := &apps.App{
		ID:   "test",
		Exec: "app",
		Gamescope: apps.GamescopeConfig{
			Enabled:    true,
			ExtraFlags: []string{"--some-flag", "--"},
		},
	}
	_, err := AppArgv(app)
	if err == nil {
		t.Error("expected error when ExtraFlags contains \"--\"")
	}
}

func TestAppArgv_ExtraFlags(t *testing.T) {
	app := &apps.App{
		ID:   "test",
		Exec: "app",
		Gamescope: apps.GamescopeConfig{
			Enabled:    true,
			ExtraFlags: []string{"--some-flag", "--another=value"},
		},
	}
	got, err := AppArgv(app)
	if err != nil {
		t.Fatal(err)
	}
	assertContains(t, got, "--some-flag")
	assertContains(t, got, "--another=value")
}

func TestAppArgv_UnclosedExecQuote(t *testing.T) {
	app := &apps.App{
		ID:        "test",
		Exec:      `cmd "unclosed`,
		Gamescope: apps.GamescopeConfig{Enabled: true},
	}
	_, err := AppArgv(app)
	if err == nil {
		t.Error("expected error for unclosed quote in Exec")
	}
}

// ── helpers ──────────────────────────────────────────────────────────────── //

func assertStringSlice(t *testing.T, got, want []string) {
	t.Helper()
	if len(got) != len(want) {
		t.Errorf("len=%d want %d: got %v", len(got), len(want), got)
		return
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("[%d] got %q, want %q", i, got[i], want[i])
		}
	}
}

func assertContains(t *testing.T, slice []string, elem string) {
	t.Helper()
	for _, s := range slice {
		if s == elem {
			return
		}
	}
	t.Errorf("expected %q in %v", elem, slice)
}

func assertNextEq(t *testing.T, slice []string, after, want string) {
	t.Helper()
	for i, s := range slice {
		if s == after && i+1 < len(slice) {
			if slice[i+1] != want {
				t.Errorf("after %q: got %q, want %q", after, slice[i+1], want)
			}
			return
		}
	}
	t.Errorf("%q not found in %v", after, slice)
}

func assertNotContains(t *testing.T, slice []string, elem string) {
	t.Helper()
	for _, s := range slice {
		if s == elem {
			t.Errorf("expected %q NOT in %v", elem, slice)
			return
		}
	}
}

// Suppress unused warning.
var _ = assertNotContains

func TestSplitExec_TrailingSpace(t *testing.T) {
	got, err := splitExec("cmd arg ")
	if err != nil {
		t.Fatal(err)
	}
	assertStringSlice(t, got, []string{"cmd", "arg"})
}

func TestSplitExec_QuotedEmpty(t *testing.T) {
	// Empty quoted string: splitExec does not produce empty tokens — it
	// discards them via the `if cur.Len() > 0` flush. This matches the
	// practical use case where empty args are never meaningful.
	got, err := splitExec(`cmd ""`)
	if err != nil {
		t.Fatal(err)
	}
	// Only the first non-empty token is produced.
	assertStringSlice(t, got, []string{"cmd"})
}

func TestAppArgv_SeparatorBeforeExec(t *testing.T) {
	app := &apps.App{
		ID:   "test",
		Exec: "myapp --flag",
		Gamescope: apps.GamescopeConfig{
			Enabled: true,
		},
	}
	got, err := AppArgv(app)
	if err != nil {
		t.Fatal(err)
	}
	// Find "--" and verify exec args follow it.
	sepIdx := -1
	for i, a := range got {
		if a == "--" {
			sepIdx = i
			break
		}
	}
	if sepIdx < 0 {
		t.Fatal("no -- separator found")
	}
	tail := got[sepIdx+1:]
	assertStringSlice(t, tail, []string{"myapp", "--flag"})
}

func TestAppArgv_NoFullscreen(t *testing.T) {
	app := &apps.App{
		ID:   "test",
		Exec: "app",
		Gamescope: apps.GamescopeConfig{
			Enabled:    true,
			Fullscreen: false,
		},
	}
	got, err := AppArgv(app)
	if err != nil {
		t.Fatal(err)
	}
	for _, a := range got {
		if a == "-f" {
			t.Error("expected no -f flag when Fullscreen=false")
		}
	}
}

func TestSplitExec_OnlySpaces(t *testing.T) {
	got, err := splitExec("   ")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 0 {
		t.Errorf("expected empty result for whitespace-only input, got %v", got)
	}
}

func TestAppArgv_ExecWithQuotedSpaces(t *testing.T) {
	app := &apps.App{
		ID:        "test",
		Exec:      `"my app" --arg`,
		Gamescope: apps.GamescopeConfig{Enabled: false},
	}
	got, err := AppArgv(app)
	if err != nil {
		t.Fatal(err)
	}
	assertStringSlice(t, got, []string{"my app", "--arg"})
}

func TestSplitExec_ReturnsStringSlice(t *testing.T) {
	// Verify return type is []string (compile-time, but also check it's usable).
	got, err := splitExec("a b c")
	if err != nil {
		t.Fatal(err)
	}
	var _ = got
	_ = strings.Join(got, " ")
}
