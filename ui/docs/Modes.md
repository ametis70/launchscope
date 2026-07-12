# Modes

The UI is configured along three independent axes.

## Session mode (`session_mode`)

Controls how the launcher session itself is run — which software stack sits between the UI and the display.

| Value | Description |
|---|---|
| `drm_gamescope` | gamescope owns the display directly via KMS/DRM. No compositor above it. `display.fullscreen` is ignored — always fullscreen. |
| `nested_gamescope` | gamescope runs as a window inside an existing Wayland/X11 compositor. `display.fullscreen` controls whether gamescope fills the compositor output. |
| `nested_direct` | love runs directly inside an existing compositor with no gamescope wrapper. `display.fullscreen` controls the LÖVE window. |

Default: `drm_gamescope`.

## Process mode (`process_mode`)

Controls who manages app processes.

| Value | Description |
|---|---|
| `daemon` | Delegates to `launchscoped` over HTTP. The daemon owns the process slot, launches the UI as a subprocess, and relaunches it when an app exits. **The UI should not be started manually in this mode** — start `launchscoped` instead and it will launch the UI automatically. |
| `standalone` | The UI manages processes directly. No daemon required. |

Default: `daemon`.

## Display fullscreen (`display.fullscreen`)

Whether the launcher window is fullscreen or windowed. Only meaningful in `nested_gamescope` and `nested_direct` — ignored in `drm_gamescope`.

Default: `true`.

## Combinations

All combinations are valid:

| `session_mode` | `process_mode` | `display.fullscreen` | Result |
|---|---|---|---|
| `drm_gamescope` | `daemon` | — | gamescope on bare metal, daemon manages apps |
| `drm_gamescope` | `standalone` | — | gamescope on bare metal, UI manages apps |
| `nested_gamescope` | `daemon` | `true` | gamescope fullscreen inside compositor, daemon manages apps |
| `nested_gamescope` | `standalone` | `true` | gamescope fullscreen inside compositor, UI manages apps |
| `nested_gamescope` | `daemon` | `false` | gamescope windowed inside compositor, daemon manages apps |
| `nested_direct` | `daemon` | `true` | LÖVE fullscreen in compositor, daemon manages apps |
| `nested_direct` | `standalone` | `false` | LÖVE windowed in compositor, UI manages apps |
