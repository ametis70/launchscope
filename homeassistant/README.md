<div align="center">

# launchscope — Home Assistant integration

![license](https://img.shields.io/github/license/ametis70/launchscope?style=flat-square)
![hacs](https://img.shields.io/badge/HACS-custom-orange?style=flat-square)

Custom Home Assistant integration for controlling and monitoring [launchscoped](../server/)

<br>

</div>

## Installation

### HACS

1. Add this repository as a custom repository in HACS (**Settings → Custom repositories**)
2. Search for **Launchscope** and install it
3. Restart Home Assistant
4. Go to **Settings → Devices & Services → Add Integration**, search for **Launchscope** and follow the config flow

### Manual

1. Copy `custom_components/launchscope/` into your HA `config/custom_components/` directory
2. Restart Home Assistant
3. Go to **Settings → Devices & Services → Add Integration**, search for **Launchscope** and follow the config flow

## Entities

| Entity | Type | Description |
|---|---|---|
| Launchscope | `media_player` | Current app state, source selection, volume and mute control |
| Current App | `sensor` | ID of the running app, or `idle` |
| Stop App | `button` | Stop the running app and return to the launcher (only available when an app is running) |
| Turn On TV | `button` | Power on TV + AVR and set active source (`POST /api/cec/activate`) |
| Power On | `button` | Power on TV + AVR without switching input (`POST /api/cec/power-on`) |
| Set Active Source | `button` | Broadcast ActiveSource to switch AVR input to the host PC (`POST /api/cec/set-source`) |
| Turn Off TV | `button` | Send the AVR to standby (`POST /api/cec/standby`) |

The media player's source list reflects the app list from `GET /api/apps`. Selecting a source launches the corresponding app.

## Examples

### Dashboard card

```yaml
type: media-control
entity: media_player.launchscope
```

Gives you volume slider, mute toggle, and source selector (app launcher) in one card.

### Automation

```yaml
# Turn on the TV and open Kodi when triggered
automation:
  trigger:
    platform: state
    entity_id: input_button.watch_kodi
  action:
    - service: media_player.select_source
      target:
        entity_id: media_player.launchscope
      data:
        source: Kodi
```

## Development

```bash
python3 -m venv homeassistant/.venv
homeassistant/.venv/bin/pip install -r requirements-test.txt
homeassistant/.venv/bin/pytest tests/
```
