package apps

// App describes a launchable application.
type App struct {
	ID        string          `json:"id"`
	Name      string          `json:"name"`
	Exec      string          `json:"exec"`
	Gamescope GamescopeConfig `json:"gamescope"`
}

// GamescopeConfig controls whether and how an app is wrapped in gamescope.
// The schema matches the UI's lib/gamescope.lua exactly.
type GamescopeConfig struct {
	Enabled bool `json:"enabled"`

	// Fullscreen enables the -f flag (default true when enabled).
	Fullscreen bool `json:"fullscreen"`

	// Output is the display resolution (-W/-H/-r).
	Output Resolution `json:"output"`

	// Inner is the render resolution (-w/-h). When zero, defaults to Output.
	Inner InnerResolution `json:"inner"`

	// Filter selects the upscaler (-F): "linear", "nearest", "fsr", "nis", "pixel".
	// Empty string = no -F flag.
	Filter string `json:"filter"`

	// Scaler selects the scaler mode (-S): "auto", "integer", "fit", "fill", "stretch".
	// Empty string = use "fit" when Filter is set and inner != output.
	Scaler string `json:"scaler"`

	// Sharpness is the upscaler sharpness (--sharpness 0-20).
	// Nil = flag omitted.
	Sharpness *int `json:"sharpness"`

	HDR            bool     `json:"hdr"`
	AdaptiveSync   bool     `json:"adaptive_sync"`
	ForceGrab      bool     `json:"force_grab"`
	ExposeWayland  bool     `json:"expose_wayland"`
	CompositeDebug bool     `json:"composite_debug"`
	MangoApp       bool     `json:"mangoapp"`
	ExtraFlags     []string `json:"extra_flags"`
}

// Resolution is an output display resolution + refresh rate.
type Resolution struct {
	Width   int `json:"width"`
	Height  int `json:"height"`
	Refresh int `json:"refresh"`
}

// InnerResolution is a render resolution (no refresh — that comes from Output).
type InnerResolution struct {
	Width  int `json:"width"`
	Height int `json:"height"`
}

// ByID returns the first App with the given id, or nil.
func ByID(list []App, id string) *App {
	for i := range list {
		if list[i].ID == id {
			return &list[i]
		}
	}
	return nil
}
