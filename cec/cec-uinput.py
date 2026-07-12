#!/usr/bin/env python3
"""
CEC → uinput bridge for Pulse-Eight USB CEC adapter.

Uses the python-cec library (libcec bindings) for a single connection that
handles both incoming remote key presses and outgoing CEC commands.

Remote key presses are forwarded as uinput keyboard events.
Commands are received via a Unix socket at /run/cec-uinput/cmd.sock:
  activate   — set as active source (wakes display, switches AVR input)
  standby    — send standby to the configured device
  switch:N   — same as activate (port is fixed at init via CEC_HDMI_PORT)

Configuration via environment variables:
  CEC_BASE_DEVICE   logical address the adapter is connected to (default: 0 = TV)
  CEC_HDMI_PORT     HDMI port on the base device (default: 1)
  CEC_STANDBY_ADDR  logical address to send standby to (default: CEC_BASE_DEVICE)
"""

import cec
import os
import socket
import sys
import threading

from evdev import UInput, ecodes as e

SOCKET_PATH = "/run/cec-uinput/cmd.sock"

CEC_BASE         = int(os.environ.get("CEC_BASE_DEVICE", "0"))
CEC_PORT         = int(os.environ.get("CEC_HDMI_PORT",   "1"))
CEC_STANDBY_ADDR = int(os.environ.get("CEC_STANDBY_ADDR", str(CEC_BASE)))
CEC_VERBOSE      = os.environ.get("CEC_VERBOSE", "0") == "1"

# CEC UI Command codes → Linux key codes
CEC_KEYMAP = {
    0x00: e.KEY_ENTER,
    0x01: e.KEY_UP,
    0x02: e.KEY_DOWN,
    0x03: e.KEY_LEFT,
    0x04: e.KEY_RIGHT,
    0x09: e.KEY_HOME,
    0x0d: e.KEY_ESC,
    0x20: e.KEY_0,
    0x21: e.KEY_1,
    0x22: e.KEY_2,
    0x23: e.KEY_3,
    0x24: e.KEY_4,
    0x25: e.KEY_5,
    0x26: e.KEY_6,
    0x27: e.KEY_7,
    0x28: e.KEY_8,
    0x29: e.KEY_9,
    0x30: e.KEY_CHANNELUP,
    0x31: e.KEY_CHANNELDOWN,
    0x44: e.KEY_PLAYPAUSE,
    0x46: e.KEY_PAUSE,
    0x47: e.KEY_RECORD,
    0x49: e.KEY_REWIND,
    0x4a: e.KEY_FASTFORWARD,
    0x4c: e.KEY_NEXTSONG,
    0x4d: e.KEY_PREVIOUSSONG,
    0x60: e.KEY_INFO,
    0x6a: e.KEY_POWER,
    0x71: e.KEY_BLUE,
    0x72: e.KEY_RED,
    0x73: e.KEY_GREEN,
    0x74: e.KEY_YELLOW,
}

CEC_NAMES = {
    0x00: "Select",  0x01: "Up",     0x02: "Down",   0x03: "Left",
    0x04: "Right",   0x09: "Home",   0x0d: "Exit",
    0x44: "Play",    0x46: "Pause",  0x49: "Rewind", 0x4a: "FastFwd",
    0x4c: "Next",    0x4d: "Prev",
    0x71: "Blue",    0x72: "Red",    0x73: "Green",  0x74: "Yellow",
}

ui         = None
pressed_key = None


def on_log(event, level, time, message):
    print(f"cec-uinput [libcec]: {message}", flush=True)


def on_keypress(event, keycode, duration):
    """Called by libcec on CEC key press/release events."""
    global pressed_key
    key = CEC_KEYMAP.get(keycode)
    if key is None:
        print(f"cec-uinput: unmapped CEC 0x{keycode:02x}", flush=True)
        return
    name = CEC_NAMES.get(keycode, f"0x{keycode:02x}")
    if duration == 0:
        # Key pressed
        ui.write(e.EV_KEY, key, 1)
        ui.syn()
        pressed_key = key
        print(f"cec-uinput: press {name} → {e.KEY[key]}", flush=True)
    else:
        # Key released
        if pressed_key is not None:
            ui.write(e.EV_KEY, pressed_key, 0)
            ui.syn()
            pressed_key = None


def handle_command(cmd):
    """Handle a command received on the Unix socket."""
    cmd = cmd.strip().lower()
    if cmd == "activate" or cmd.startswith("switch:"):
        label = "activate" if cmd == "activate" else f"switch ({cmd})"
        print(f"cec-uinput: {label} — powering on base device and setting active source", flush=True)
        try:
            cec.Device(CEC_BASE).power_on()
            cec.set_active_source()
            print(f"cec-uinput: {label} done", flush=True)
        except Exception as ex:
            print(f"cec-uinput: {label} error: {ex}", flush=True)
    elif cmd == "standby":
        print(f"cec-uinput: standby — sending to device {CEC_STANDBY_ADDR}", flush=True)
        try:
            device = cec.Device(CEC_STANDBY_ADDR)
            device.standby()
            print("cec-uinput: standby done", flush=True)
        except Exception as ex:
            print(f"cec-uinput: standby error: {ex}", flush=True)
    else:
        print(f"cec-uinput: unknown command '{cmd}'", flush=True)


def socket_server():
    """Unix socket server for receiving commands."""
    try:
        os.unlink(SOCKET_PATH)
    except FileNotFoundError:
        pass

    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(SOCKET_PATH)
    os.chmod(SOCKET_PATH, 0o666)
    srv.listen(5)
    srv.settimeout(1)
    print(f"cec-uinput: command socket at {SOCKET_PATH}", flush=True)

    while True:
        try:
            conn, _ = srv.accept()
            with conn:
                data = conn.recv(256).decode(errors="replace")
                for line in data.splitlines():
                    if line.strip():
                        handle_command(line)
        except socket.timeout:
            continue
        except Exception as ex:
            print(f"cec-uinput: socket error: {ex}", flush=True)


def main():
    global ui

    print(f"cec-uinput: starting (base={CEC_BASE} port={CEC_PORT} standby_addr={CEC_STANDBY_ADDR})", flush=True)

    ui = UInput(
        {e.EV_KEY: sorted(set(CEC_KEYMAP.values()))},
        name="cec-uinput",
        vendor=0x0001,
        product=0x0001,
        version=0x0111,
        bustype=0x03,   # BUS_USB — triggers proper udev/gamescope discovery
    )
    print("cec-uinput: uinput device created", flush=True)

    # Initialise libcec — set_port must be called before init().
    cec.set_port(CEC_BASE, CEC_PORT)
    cec.init()
    if CEC_VERBOSE:
        cec.add_callback(on_log, cec.EVENT_LOG)
    cec.add_callback(on_keypress, cec.EVENT_KEYPRESS)
    print("cec-uinput: libcec initialised", flush=True)

    # Start socket server in a background thread.
    t = threading.Thread(target=socket_server, daemon=True)
    t.start()

    print("cec-uinput: ready", flush=True)

    # Block main thread — libcec callbacks run on their own thread.
    try:
        threading.Event().wait()
    except KeyboardInterrupt:
        pass

    ui.close()
    try:
        os.unlink(SOCKET_PATH)
    except FileNotFoundError:
        pass


if __name__ == "__main__":
    main()
