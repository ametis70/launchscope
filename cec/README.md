<div align="center">

# cec-uinput

![license](https://img.shields.io/github/license/ametis70/launchscope?style=flat-square)
![python](https://img.shields.io/badge/python-3.13-3776AB?style=flat-square&logo=python&logoColor=white)

HDMI-CEC to uinput bridge for [Pulse-Eight USB CEC adapters](https://www.pulse-eight.com/p/104/usb-hdmi-cec-adapter)

<br>

</div>

## Overview

`cec-uinput` maintains a persistent connection to a Pulse-Eight USB CEC adapter via [libcec](https://github.com/Pulse-Eight/libcec) and does two things:

- **Input** — forwards TV remote key presses as uinput keyboard events, making the remote appear as a standard keyboard to all applications
- **Output** — listens on a Unix socket at `/run/cec-uinput/cmd.sock` for commands from `launchscoped`

## Dependencies

- Python 3
- [`python-cec`](https://pypi.org/project/cec/) — libcec Python bindings
- [`evdev`](https://pypi.org/project/evdev/) — uinput kernel interface
- libcec

## Configuration

Two topologies are supported:

**PC → TV directly (no AVR):** set `CEC_AVR_DEVICE` to empty. `power-on` and `standby` go to the TV only.

**PC → AVR → TV:** set `CEC_AVR_DEVICE = 5`. `power-on` goes to both TV and AVR. `standby` goes to the AVR only — the TV powers off automatically when the signal drops.

All configuration is via environment variables:

| Variable | Default | Description |
|---|---|---|
| `CEC_TV_DEVICE` | `0` | Logical CEC address of the TV/projector. Always 0 per the CEC spec. |
| `CEC_AVR_DEVICE` | `5` | Logical CEC address of the AVR. Leave empty if there is no AVR. |
| `CEC_SOURCE_PORT` | `1` | HDMI port on the AVR (or TV if no AVR) the host PC is connected to. Used by libcec to resolve the adapter's physical address. |
| `CEC_SOURCE_ADDR` | `""` | Physical CEC address of the host PC, e.g. `1.6.0.0`. Run `echo 'scan' \| cec-client -s -d 1` to discover. |
| `CEC_VERBOSE` | `0` | Set to `1` to enable verbose libcec logging. |

## Socket commands

| Command | Description |
|---|---|
| `power-on` | Power on TV (and AVR if configured) |
| `set-source` | Broadcast `ActiveSource` with `CEC_SOURCE_ADDR` — switches input to the host PC |
| `standby` | Standby the AVR (or TV if no AVR) |
| `activate` | `ImageViewOn` to TV + broadcast `ActiveSource` |

```bash
echo "activate"   | socat - UNIX-CONNECT:/run/cec-uinput/cmd.sock
echo "standby"    | socat - UNIX-CONNECT:/run/cec-uinput/cmd.sock
echo "set-source" | socat - UNIX-CONNECT:/run/cec-uinput/cmd.sock
```

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
  tvDevice      = 0;
  avrDevice     = 5;
  sourcePort    = 6;   # HDMI port on the AVR the host PC is connected to
  sourceAddr    = "1.6.0.0";  # physical address of the host PC
};
```

### systemd (non-Nix)

Install the dependencies, then create `/etc/systemd/system/cec-uinput.service`:

```ini
[Unit]
Description=HDMI-CEC to uinput bridge (Pulse-Eight adapter)
After=network.target

[Service]
ExecStart=/usr/local/bin/cec-uinput.py
Restart=on-failure
RuntimeDirectory=cec-uinput
SupplementaryGroups=dialout input
Environment=CEC_TV_DEVICE=0
Environment=CEC_AVR_DEVICE=5
Environment=CEC_SOURCE_PORT=6
Environment=CEC_SOURCE_ADDR=1.6.0.0
Environment=CEC_VERBOSE=0

[Install]
WantedBy=multi-user.target
```

The user running the service needs to be in the `dialout` group (serial port access) and the `input` group (uinput access).

To give the virtual device a stable path at `/dev/input/cec-remote`, add a udev rule:

```
# /etc/udev/rules.d/99-cec-uinput.rules
KERNEL=="event*", ATTRS{name}=="cec-uinput", SYMLINK+="input/cec-remote", MODE="0664", GROUP="input"
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now cec-uinput
```

## Finding `baseDevice` and `hdmiPort`

Run a CEC bus scan to discover the logical and physical addresses of connected devices:

```bash
echo 'scan' | cec-client -s -d 1
```

The output lists all devices with their logical address (`device #N`) and physical address (`X.Y.0.0`):

- **Direct to TV** — `baseDevice = 0`, `hdmiPort` = the first non-zero digit in your device's physical address (e.g. `2.0.0.0` → port 2)
- **Through an AVR** — `baseDevice = 5` (Audio system logical address), `hdmiPort` = the second digit (e.g. `1.6.0.0` → port 6 on the AVR)

Set `standbyAddr` to the same value as `baseDevice` in most cases.

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
