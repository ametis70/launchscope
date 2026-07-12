<div align="center">

# launchscoped

![license](https://img.shields.io/github/license/ametis70/launchscope?style=flat-square)
![go](https://img.shields.io/badge/go-1.26-00ADD8?style=flat-square&logo=go&logoColor=white)

Daemon that manages the launchscope UI and app lifecycles through a REST API.

<br>

</div>

## Overview

`launchscoped` owns a single process slot — either the launcher UI or one app. It drives a lifecycle state machine (`starting → ui_running → launching → app_running → stopping`) and exposes a REST + WebSocket API for control and real-time event streaming.

- **Process management** — launches and monitors the LÖVE2D UI and gamescope-wrapped apps; restarts the UI when an app exits
- **Audio** — polls PipeWire via `wpctl` and forwards volume/mute events over WebSocket
- **CEC** — sends HDMI-CEC commands to the TV via the `cec-uinput` Unix socket
- **Config** — reads `config.json` and `apps.json` from `$XDG_CONFIG_HOME/launchscoped/`; auto-generates an API key if none is set

[docs/API.md](docs/API.md) • [docs/Configuration.md](docs/Configuration.md)

## Debugging

```bash
# Follow daemon logs
journalctl --user -u launchscoped -f

# Check status and audio (localhost — no auth required)
curl http://127.0.0.1:8765/api/status
curl http://127.0.0.1:8765/api/apps

# From another machine
curl http://htpc:8765/api/status -H "X-Api-Key: your-key"

# Check font resolution
fc-match --format='%{file}' "DepartureMono Nerd Font"
```
