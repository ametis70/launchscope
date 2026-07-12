# API Reference

All endpoints require an `X-Api-Key` header (or `?apikey=` query param) for requests from non-localhost addresses. Localhost connections are unauthenticated.

Error responses always have the shape `{"error": "message"}`.

---

### `GET /api/status`

Returns the current process state, running app, and audio state.

**Response `200`**
```json
{
  "state": "app_running",
  "current_app": { "id": "kodi", "name": "Kodi" },
  "audio": { "volume": 0.72, "muted": false, "sink_name": "Built-in Audio HDMI" }
}
```

`state` is one of `starting`, `ui_running`, `launching`, `app_running`, `stopping`. `current_app` is `null` when the UI is in the foreground. `audio` is `null` when PipeWire is unavailable.

---

### `GET /api/apps`

Returns the list of registered apps.

**Response `200`**
```json
[
  { "id": "kodi",      "name": "Kodi"      },
  { "id": "moonlight", "name": "Moonlight" }
]
```

---

### `POST /api/launch/{id}`

Stops the current process and launches the app with the given id.

**Response `202`** — launch accepted (process start is asynchronous).

**Errors**
- `404` — no app with that id
- `409` — server is busy (transitioning between states), retry shortly

---

### `POST /api/stop`

Stops the current app and returns to the launcher UI.

**Response `200`**
```json
{ "state": "stopping" }
```

---

### `GET /api/audio`

Returns the current PipeWire default sink state.

**Response `200`**
```json
{ "volume": 0.72, "muted": false, "sink_name": "Built-in Audio HDMI" }
```

`volume` is `0.0–1.5` where `1.0` = 100%.

---

### `POST /api/audio/volume`

Sets or adjusts the default sink volume. Exactly one of `value` or `delta` must be provided.

**Request**
```json
{ "value": 0.80 }
```
```json
{ "delta": 0.05 }
```

`value` sets an absolute level (`0.0–1.5`). `delta` adds to the current level (negative to decrease), clamped to `0.0–1.5`.

**Response `200`** — updated audio state (same shape as `GET /api/audio`).

---

### `POST /api/audio/mute`

Sets or toggles the default sink mute state. Exactly one of `muted` or `toggle` must be provided.

**Request**
```json
{ "muted": true }
```
```json
{ "toggle": true }
```

**Response `200`** — updated audio state.

---

### `POST /api/cec/activate`

Powers on the TV and switches its input to this device. Requires `cec.enabled = true` in config.

**Response `200`**
```json
{ "status": "ok" }
```

**Errors**
- `503` — CEC is not enabled in config

---

### `POST /api/cec/standby`

Sends the TV to standby. Requires `cec.enabled = true`.

**Response `200`**
```json
{ "status": "ok" }
```

---

### `POST /api/cec/switch-input`

Switches the TV to the HDMI port configured in `cec.switch_port`. Requires `cec.enabled = true` and `cec.switch_port` to be set.

**Response `200`**
```json
{ "status": "ok" }
```

**Errors**
- `503` — CEC is not enabled or `switch_port` is not configured

---

### `POST /api/system/power`

Runs a system power action via `systemctl`.

**Request**
```json
{ "action": "shutdown" }
```

`action` is one of `shutdown`, `restart`, `suspend`. Note: `shutdown` and `restart` will terminate the daemon mid-response — the connection will be dropped.

**Response `202`** — command accepted.

---

### `GET /api/config`

Returns the current daemon config. The API key is always redacted.

**Response `200`**
```json
{
  "api": { "port": 8765, "api_key": "" },
  "cec": { "enabled": true, "switch_port": 1 }
}
```

---

### `GET /ws`

WebSocket event stream. Connects immediately and receives all state and audio changes in real time.

**Events**
```json
{ "type": "state_changed", "payload": { "state": "app_running", "current_app": { "id": "kodi", "name": "Kodi" } } }
{ "type": "audio_changed",  "payload": { "volume": 0.72, "muted": false, "sink_name": "Built-in Audio HDMI" } }
```

The server accepts up to 64 concurrent WebSocket connections. Excess connections receive `503`.
