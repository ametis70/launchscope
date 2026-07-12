# Configuration

Both files live in `$XDG_CONFIG_HOME/launchscoped/` (defaults to `~/.config/launchscoped/`).

## config.json

```json
{
  "api": {
    "port": 8765,
    "api_key": "your-key-here"
  },
  "cec": {
    "enabled": true,
    "switch_port": 1
  }
}
```

| Field | Type | Default | Description |
|---|---|---|---|
| `api.port` | int | `8765` | HTTP listen port |
| `api.api_key` | string | — | API key for remote authentication |
| `api.api_key_file` | string | — | Path to a file containing the API key (takes precedence over `api_key`) |
| `cec.enabled` | bool | `false` | Enable HDMI-CEC control via `cec-uinput` |
| `cec.switch_port` | int | `0` | HDMI port used by `POST /api/cec/switch-input` (1-based) |

### API key resolution

The key is resolved in this order — first match wins:

1. `api.api_key_file` field (path to a file containing the key)
2. `api.api_key` inline value
3. `~/.config/launchscoped/api_key` file (persisted from a previous auto-generation)
4. Auto-generated 256-bit key, persisted to `~/.config/launchscoped/api_key`

## apps.json

A JSON array of app definitions. Each entry may optionally wrap the app in gamescope.

### Without gamescope

```json
{
  "id": "desktop",
  "name": "Desktop",
  "exec": "startplasma-wayland"
}
```

### Kodi at 4K

```json
{
  "id": "kodi",
  "name": "Kodi",
  "exec": "/run/current-system/sw/bin/kodi-standalone",
  "gamescope": {
    "enabled": true,
    "fullscreen": true,
    "output": { "width": 3840, "height": 2160, "refresh": 60 }
  }
}
```

### Moonlight at 1440p/120Hz

```json
{
  "id": "moonlight",
  "name": "Moonlight",
  "exec": "/run/current-system/sw/bin/moonlight",
  "gamescope": {
    "enabled": true,
    "fullscreen": true,
    "output": { "width": 2560, "height": 1440, "refresh": 120 }
  }
}
```

### Pegasus with FSR upscaling

Renders at 1080p, upscales to 1440p with FSR and sharpness tuning.

```json
{
  "id": "pegasus",
  "name": "Pegasus",
  "exec": "pegasus-fe",
  "gamescope": {
    "enabled": true,
    "fullscreen": true,
    "output": { "width": 2560, "height": 1440, "refresh": 120 },
    "inner": { "width": 1920, "height": 1080 },
    "filter": "fsr",
    "sharpness": 5
  }
}
```

### Gamescope config reference

| Field | Type | Default | Description |
|---|---|---|---|
| `enabled` | bool | `false` | Wrap the app in gamescope |
| `fullscreen` | bool | `false` | Pass `-f` (fullscreen) |
| `output.width` | int | `1920` | Display width (`-W`) |
| `output.height` | int | `1080` | Display height (`-H`) |
| `output.refresh` | int | `60` | Display refresh rate (`-r`) |
| `inner.width` | int | output width | Render width (`-w`) |
| `inner.height` | int | output height | Render height (`-h`) |
| `filter` | string | — | Upscaler: `linear`, `nearest`, `fsr`, `nis`, `pixel` (`-F`) |
| `scaler` | string | `fit` when inner ≠ output | Scaler mode: `auto`, `integer`, `fit`, `fill`, `stretch` (`-S`) |
| `sharpness` | int | — | Upscaler sharpness `0–20` (`--sharpness`) |
| `hdr` | bool | `false` | `--hdr-enabled` |
| `adaptive_sync` | bool | `false` | `--adaptive-sync` |
| `force_grab` | bool | `false` | `--force-grab-cursor` |
| `expose_wayland` | bool | `false` | `--expose-wayland` |
| `mangoapp` | bool | `false` | `--mangoapp` |
| `composite_debug` | bool | `false` | `--composite-debug` |
| `extra_flags` | string[] | `[]` | Arbitrary extra flags appended verbatim. `"--"` is rejected. |
