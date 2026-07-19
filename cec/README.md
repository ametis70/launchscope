<div align="center">

# launchscope-cec

![license](https://img.shields.io/github/license/ametis70/launchscope?style=flat-square)
![python](https://img.shields.io/badge/python-3.13-3776AB?style=flat-square&logo=python&logoColor=white)

HDMI-CEC bridge for [Pulse-Eight USB CEC adapters](https://www.pulse-eight.com/p/104/usb-hdmi-cec-adapter)

<br>

</div>

## Overview

`launchscope-cec` maintains a persistent connection to a Pulse-Eight USB CEC adapter via [libcec](https://github.com/Pulse-Eight/libcec) and provides bidirectional HDMI-CEC integration with Launchscope:

- **Remote input** — forwards TV remote key presses as uinput keyboard events, making the remote appear as a standard keyboard to all applications
- **CEC commands** — listens on a Unix socket at `/run/launchscope-cec/cmd.sock` for outgoing commands from `launchscoped` (power on, standby, set active source)
- **State reporting** — monitors the CEC bus for device power status and active source changes, pushing live state to `launchscoped` via HTTP so the UI can react (stop rendering when TV is off or input is switched away)

### State tracking

`launchscope-cec` watches incoming CEC bus traffic to maintain the following state, pushed to `launchscoped` on every change:

| Field | Source |
|---|---|
| `tv_on` | `ReportPowerStatus` (0x90) from TV / `Standby` (0x36) from TV |
| `avr_on` | `SetSystemAudioMode` (0x72) from AVR (`0x01` = on, `0x00` = off) / TV standby implicitly powers off AVR |
| `active_source` | `ActiveSource` (0x82) broadcast / `RoutingChange` (0x80) from AVR |
| `is_active_source` | whether `active_source` is the host PC (logical address 1) |

## Dependencies

- Python 3
- [`python-cec`](https://pypi.org/project/cec/) — libcec Python bindings
- [`evdev`](https://pypi.org/project/evdev/) — uinput kernel interface
- libcec

## Configuration

Two topologies are supported:

**PC → TV directly (no AVR):** set `CEC_HAS_AVR=0`. `standby` goes to the TV directly.

**PC → AVR → TV:** set `CEC_HAS_AVR=1` (default). `standby` goes to the AVR only — the TV powers off automatically when the signal drops.

All configuration is via environment variables:

| Variable | Default | Description |
|---|---|---|
| `CEC_HAS_AVR` | `1` | Set to `1` if an AVR is present. Standby goes to AVR only (TV powers off via signal loss). Set to `0` for direct PC→TV with no AVR. The AVR logical address is always 5 per the CEC spec. |
| `CEC_SOURCE_ADDR` | _(required)_ | Physical CEC address of the host PC, e.g. `1.6.0.0`. Run `echo 'scan' \| cec-client -s -d 1` to discover. |
| `CEC_VERBOSE` | `0` | Set to `1` to enable verbose libcec logging. |
| `LAUNCHSCOPE_SERVER_URL` | `http://127.0.0.1:8765` | URL of `launchscoped` for pushing CEC state. |

## Socket commands

Send commands to the Unix socket to control the display:

```bash
echo "activate"   | socat - UNIX-CONNECT:/run/launchscope-cec/cmd.sock
echo "standby"    | socat - UNIX-CONNECT:/run/launchscope-cec/cmd.sock
echo "set-source" | socat - UNIX-CONNECT:/run/launchscope-cec/cmd.sock
echo "power-on"   | socat - UNIX-CONNECT:/run/launchscope-cec/cmd.sock
```

| Command | Description |
|---|---|
| `activate` | `ReportPhysicalAddress` + `DeviceVendorID` + `TextViewOn` + `ActiveSource` — full wake + input switch |
| `power-on` | `TextViewOn` to TV only — wake without switching input |
| `set-source` | Broadcast `ActiveSource` — switch input without waking |
| `standby` | Standby the AVR (or TV if no AVR). Skipped if host PC is not the active source. |

## Key mapping

| CEC code | Linux key |
|---|---|
| Select | `KEY_ENTER` |
| Up / Down / Left / Right | `KEY_UP` / `KEY_DOWN` / `KEY_LEFT` / `KEY_RIGHT` |
| Home | `KEY_HOME` |
| Exit | `KEY_ESC` |
| 0–9 | `KEY_0`–`KEY_9` |
| Channel Up / Down | `KEY_CHANNELUP` / `KEY_CHANNELDOWN` |
| Play/Pause | `KEY_PLAYPAUSE` |
| Rewind / Fast Forward | `KEY_REWIND` / `KEY_FASTFORWARD` |
| Previous / Next | `KEY_PREVIOUSSONG` / `KEY_NEXTSONG` |
| Blue / Red / Green / Yellow | `KEY_BLUE` / `KEY_RED` / `KEY_GREEN` / `KEY_YELLOW` |
| Power | `KEY_POWER` |

## Running

### NixOS

Enable via the launchscope NixOS module:

```nix
services.launchscope.cec = {
  enable        = true;
  adapterDevice = "ttyACM0";
  hasAvr        = true;    # set to false for direct PC→TV with no AVR
  sourceAddr    = "1.6.0.0";
};
```

### systemd (non-Nix)

Install the dependencies, then create `/etc/systemd/system/launchscope-cec.service`:

```ini
[Unit]
Description=HDMI-CEC bridge (Pulse-Eight adapter)
After=network.target

[Service]
ExecStart=/usr/local/bin/launchscope-cec.py
Restart=on-failure
RuntimeDirectory=launchscope-cec
SupplementaryGroups=dialout input
Environment=CEC_HAS_AVR=1
Environment=CEC_SOURCE_ADDR=1.6.0.0
Environment=CEC_VERBOSE=0
Environment=LAUNCHSCOPE_SERVER_URL=http://127.0.0.1:8765

[Install]
WantedBy=multi-user.target
```

The user running the service needs to be in the `dialout` group (serial port access) and the `input` group (uinput access).

To give the virtual device a stable path at `/dev/input/cec-remote`, add a udev rule:

```
# /etc/udev/rules.d/99-launchscope-cec.rules
KERNEL=="event*", ATTRS{name}=="launchscope-cec", SYMLINK+="input/cec-remote", MODE="0664", GROUP="input"
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now launchscope-cec
```

## Finding your physical address

Run a CEC bus scan to discover the logical and physical addresses of all connected devices:

```bash
echo 'scan' | cec-client -s -d 1
```

The output lists each device with its logical address (`device #N`) and physical address (`X.Y.0.0`). Your host PC's physical address depends on the topology:

- **Direct to TV** — `sourceAddr` = `X.0.0.0` where X is the HDMI port number on the TV
- **Through AVR** — `sourceAddr` = `1.X.0.0` where X is the HDMI port number on the AVR (the AVR is always at port 1 on the TV)

## Polkit — power actions

On non-NixOS systems, grant the service user permission to shut down and suspend without a password:

```javascript
// /etc/polkit-1/rules.d/10-htpc-power.rules
polkit.addRule(function(action, subject) {
    if ((action.id == "org.freedesktop.login1.power-off" ||
         action.id == "org.freedesktop.login1.reboot"   ||
         action.id == "org.freedesktop.login1.suspend")  &&
        subject.user == "htpc") {
        return polkit.Result.YES;
    }
});
```
