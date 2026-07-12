#!/usr/bin/env python3
"""
CEC → uinput bridge for Pulse-Eight USB CEC adapter.

Uses the python-cec library (libcec bindings) for a single connection that
handles both incoming remote key presses and outgoing CEC commands.

Remote key presses are forwarded as uinput keyboard events.
Commands are received via a Unix socket at /run/cec-uinput/cmd.sock:
  power-on     — power on the display (and AVR if configured)
  set-source   — broadcast ActiveSource with CEC_SOURCE_ADDR
  standby      — send standby to the AVR (or TV if no AVR)
  activate     — power-on, wait CEC_ACTIVATE_DELAY, set-source

Two topologies are supported:

  PC → TV directly (no AVR, CEC_AVR_DEVICE unset):
    power-on  → power_on(TV)
    standby   → standby(TV)
    set_port  → set_port(TV, CEC_SOURCE_PORT)

  PC → AVR → TV (CEC_AVR_DEVICE = 5):
    power-on  → ImageViewOn(TV) — AVR wakes automatically on ActiveSource broadcast
    standby   → standby(AVR) — TV powers off via signal loss
    set_port  → set_port(AVR, CEC_SOURCE_PORT)

Configuration via environment variables:
  CEC_TV_DEVICE      logical address of the TV/projector (default: 0, always 0 per CEC spec)
  CEC_AVR_DEVICE     logical address of the AVR/audio system (default: 5). Leave empty for no AVR.
  CEC_SOURCE_PORT    HDMI port on the AVR (or TV if no AVR) the host PC is connected to (default: 1)
  CEC_SOURCE_ADDR    physical address of the host PC on the CEC bus, e.g. "1.6.0.0".
                     Run: echo 'scan' | cec-client -s -d 1
  CEC_OSD_NAME       name shown in TV/AVR input menus, max 14 chars (default: "launchscope")
  CEC_VERBOSE        set to 1 for verbose libcec logging (default: 0)
"""

import cec
import os
import socket
import sys
import struct
import threading

from evdev import UInput, ecodes as e

SOCKET_PATH = "/run/cec-uinput/cmd.sock"

CEC_TV             = int(os.environ.get("CEC_TV_DEVICE",      "0"))
CEC_AVR            = os.environ.get("CEC_AVR_DEVICE",     "")
CEC_AVR            = int(CEC_AVR) if CEC_AVR != "" else None
CEC_SOURCE_PORT    = int(os.environ.get("CEC_SOURCE_PORT",    "1"))
CEC_SOURCE_ADDR    = os.environ.get("CEC_SOURCE_ADDR",        "")
CEC_VERBOSE        = os.environ.get("CEC_VERBOSE", "0") == "1"

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

ui          = None
pressed_key = None
_is_active_source = False


def on_source_activated(event, logical_addr, activated):
    global _is_active_source
    _is_active_source = bool(activated)
    state = "active" if activated else "inactive"
    print(f"cec-uinput: source {state} (logical {logical_addr})", flush=True)


def parse_physical_addr(s):
    """Parse "A.B.C.D" into a 2-byte big-endian CEC physical address."""
    parts = s.strip().split(".")
    if len(parts) != 4:
        raise ValueError(f"invalid physical address: {s!r}")
    a, b, c, d = (int(p) for p in parts)
    return bytes([(a << 4) | b, (c << 4) | d])


def do_power_on():
    # Send TextViewOn (0x0d) to TV — this is what the Chromecast sends.
    # ImageViewOn (0x04) is technically correct per spec but some displays
    # only wake on TextViewOn.
    cec.transmit(CEC_TV, cec.CEC_OPCODE_TEXT_VIEW_ON, bytes())


def do_report_physical_addr():
    if not CEC_SOURCE_ADDR:
        return
    addr_bytes = parse_physical_addr(CEC_SOURCE_ADDR)
    cec.transmit(cec.CECDEVICE_BROADCAST, cec.CEC_OPCODE_REPORT_PHYSICAL_ADDRESS, addr_bytes + bytes([0x04]))


def do_device_vendor_id():
    cec.transmit(cec.CECDEVICE_BROADCAST, cec.CEC_OPCODE_DEVICE_VENDOR_ID, bytes([0x00, 0x15, 0x82]))


def do_set_source():
    if not CEC_SOURCE_ADDR:
        print("cec-uinput: set-source — CEC_SOURCE_ADDR not set, falling back to set_active_source()", flush=True)
        cec.set_active_source()
        return
    addr_bytes = parse_physical_addr(CEC_SOURCE_ADDR)
    cec.transmit(cec.CECDEVICE_BROADCAST, cec.CEC_OPCODE_ACTIVE_SOURCE, addr_bytes)
    # SystemAudioModeRequest to AVR — explicitly asks it to wake and take
    # audio control. Parameters are our physical address.
    if CEC_AVR is not None:
        cec.transmit(CEC_AVR, cec.CEC_OPCODE_SYSTEM_AUDIO_MODE_REQUEST, addr_bytes)


def do_standby():
    if not _is_active_source:
        print("cec-uinput: standby — skipped, host PC is not the active source", flush=True)
        return
    if CEC_AVR is not None:
        cec.Device(CEC_AVR).standby()
    else:
        cec.Device(CEC_TV).standby()


def handle_command(cmd):
    """Handle a command received on the Unix socket."""
    cmd = cmd.strip().lower()
    if cmd == "power-on":
        print(f"cec-uinput: power-on — ImageViewOn to TV ({CEC_TV})", flush=True)
        try:
            do_power_on()
            print("cec-uinput: power-on done", flush=True)
        except Exception as ex:
            print(f"cec-uinput: power-on error: {ex}", flush=True)
    elif cmd == "set-source":
        print(f"cec-uinput: set-source — ActiveSource {CEC_SOURCE_ADDR}", flush=True)
        try:
            do_set_source()
            print("cec-uinput: set-source done", flush=True)
        except Exception as ex:
            print(f"cec-uinput: set-source error: {ex}", flush=True)
    elif cmd == "standby":
        print(f"cec-uinput: standby — AVR ({CEC_AVR})", flush=True)
        try:
            do_standby()
            print("cec-uinput: standby done", flush=True)
        except Exception as ex:
            print(f"cec-uinput: standby error: {ex}", flush=True)
    elif cmd == "activate":
        print("cec-uinput: activate — ReportPhysicalAddress, DeviceVendorID, TextViewOn, ActiveSource", flush=True)
        try:
            do_report_physical_addr()
            do_device_vendor_id()
            do_power_on()
            do_set_source()
            print("cec-uinput: activate done", flush=True)
        except Exception as ex:
            print(f"cec-uinput: activate error: {ex}", flush=True)
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

    print(f"cec-uinput: starting (tv={CEC_TV} avr={CEC_AVR} source={CEC_SOURCE_ADDR!r})", flush=True)
    ui = UInput(
        {e.EV_KEY: sorted(set(CEC_KEYMAP.values()))},
        name="cec-uinput",
        vendor=0x0001,
        product=0x0001,
        version=0x0111,
        bustype=0x03,
    )
    print("cec-uinput: uinput device created", flush=True)

    # Set our physical address directly from CEC_SOURCE_ADDR rather than
    # using set_port() which relies on libcec querying the base device's
    # physical address — unreliable when devices are in standby.
    if CEC_SOURCE_ADDR:
        cec.set_physical_addr(CEC_SOURCE_ADDR)
    else:
        cec.set_port(CEC_AVR if CEC_AVR is not None else CEC_TV, CEC_SOURCE_PORT)
    cec.init()
    if CEC_VERBOSE:
        cec.add_callback(on_log, cec.EVENT_LOG)
    cec.add_callback(on_keypress, cec.EVENT_KEYPRESS)
    cec.add_callback(on_source_activated, cec.EVENT_ACTIVATED)
    print("cec-uinput: libcec initialised", flush=True)

    t = threading.Thread(target=socket_server, daemon=True)
    t.start()

    print("cec-uinput: ready", flush=True)

    try:
        threading.Event().wait()
    except KeyboardInterrupt:
        pass

    ui.close()
    try:
        os.unlink(SOCKET_PATH)
    except FileNotFoundError:
        pass


def on_log(event, level, time, message):
    print(f"cec-uinput [libcec]: {message}", flush=True)


def on_keypress(event, keycode, duration):
    global pressed_key
    key = CEC_KEYMAP.get(keycode)
    if key is None:
        print(f"cec-uinput: unmapped CEC 0x{keycode:02x}", flush=True)
        return
    name = CEC_NAMES.get(keycode, f"0x{keycode:02x}")
    if duration == 0:
        ui.write(e.EV_KEY, key, 1)
        ui.syn()
        pressed_key = key
        print(f"cec-uinput: press {name} → {e.KEY[key]}", flush=True)
    else:
        if pressed_key is not None:
            ui.write(e.EV_KEY, pressed_key, 0)
            ui.syn()
            pressed_key = None


if __name__ == "__main__":
    main()
