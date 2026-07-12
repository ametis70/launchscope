# Configuration

Config lives at `$XDG_CONFIG_HOME/launchscope/config.json` (defaults to `~/.config/launchscope/config.json`).

Settings saved by the UI are written to `config.override.json` in the same directory, deep-merged on top of `config.json` at startup. If `config.json` is read-only (e.g. a Nix store symlink), all saves go to the override file automatically.

## Modes

The UI is configured along three independent axes. See [Modes.md](Modes.md) for the full explanation.

| Field | Type | Default |
|---|---|---|
| `session_mode` | `"drm_gamescope"` \| `"nested_gamescope"` \| `"nested_direct"` | `"drm_gamescope"` |
| `process_mode` | `"daemon"` \| `"standalone"` | `"daemon"` |

## Display

Controls the launcher window and gamescope session parameters.

| Field | Type | Default | Description |
|---|---|---|---|
| `display.fullscreen` | bool | `true` | Fullscreen or windowed — ignored in `drm_gamescope` |
| `display.output.width` | int | `1920` | Output width (`-W`) |
| `display.output.height` | int | `1080` | Output height (`-H`) |
| `display.output.refresh` | int | `60` | Output refresh rate (`-r`) |
| `display.inner.width` | int | output width | Render width for upscaling (`-w`) |
| `display.inner.height` | int | output height | Render height for upscaling (`-h`) |
| `display.filter` | string | — | Upscaler: `linear`, `nearest`, `fsr`, `nis`, `pixel` (`-F`) |
| `display.scaler` | string | `fit` when inner ≠ output | Scaler mode (`-S`) |
| `display.sharpness` | int | — | Upscaler sharpness `0–20` (`--sharpness`) |
| `display.hdr` | bool | `false` | `--hdr-enabled` |
| `display.adaptive_sync` | bool | `false` | `--adaptive-sync` |
| `display.mangoapp` | bool | `false` | `--mangoapp` |
| `display.extra_flags` | string[] | `[]` | Verbatim extra gamescope flags |

## Appearance

| Field | Type | Default | Description |
|---|---|---|---|
| `font` | string | system default | Font name resolved via `fc-match`, or absolute path to a font file |
| `icons` | string | `"pixel"` | `"pixel"` (PNG assets), `"unicode"` (Nerd Font glyphs), or `"none"` |
| `scale` | number | `1.0` | UI scale factor (`0.5`–`3.0`) |
| `background.type` | string | `"shader"` | `"shader"` (animated GLSL) or `"solid"` |
| `background.animate` | bool | `true` | Animate the shader background |
| `background.color` | string | `"#0d1440"` | Background colour (hex) |

## Idle

| Field | Type | Default | Description |
|---|---|---|---|
| `idle.dim_timeout` | number | `60` | Seconds of inactivity before dimming. `0` = disabled |
| `idle.blank_timeout` | number | `0` | Seconds before blanking the display. `0` = disabled |
| `idle.blank_mode` | string | `"wlopm"` | `"wlopm"` or `"cec"`. `"cec"` sends CEC standby/activate via the daemon's API, physically powering the display off. Only valid in daemon process mode. |
| `idle.blank_off` | string | `wlopm --off '*'` | Shell command to turn the display off (`blank_mode = "wlopm"` only) |
| `idle.blank_on` | string | `wlopm --on '*'` | Shell command to turn the display back on (`blank_mode = "wlopm"` only) |

## Examples

### Minimal — DRM, daemon

```json
{
  "display": {
    "output": { "width": 1920, "height": 1080, "refresh": 60 }
  }
}
```

### 1440p/120Hz with custom font

```json
{
  "session_mode": "drm_gamescope",
  "process_mode": "daemon",
  "font": "Hack Nerd Font",
  "icons": "pixel",
  "scale": 1.0,
  "display": {
    "fullscreen": true,
    "output": { "width": 2560, "height": 1440, "refresh": 120 }
  },
  "background": {
    "type": "shader",
    "animate": true,
    "color": "#0d1440"
  },
  "idle": {
    "dim_timeout": 60,
    "blank_timeout": 300
  }
}
```

### Nested gamescope, standalone (no daemon)

```json
{
  "session_mode": "nested_gamescope",
  "process_mode": "standalone",
  "display": {
    "fullscreen": false,
    "output": { "width": 1280, "height": 720, "refresh": 60 }
  }
}
```

### Nested direct, windowed

```json
{
  "session_mode": "nested_direct",
  "process_mode": "daemon",
  "display": {
    "fullscreen": false
  }
}
```
