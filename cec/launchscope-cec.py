#!/usr/bin/env python3
"""
HDMI-CEC bridge for Pulse-Eight USB CEC adapters.

Maintains a persistent libcec connection that provides bidirectional
CEC integration with Launchscope:

  Input  — forwards TV remote key presses as uinput keyboard events.
  Output — listens on a Unix socket at /run/launchscope-cec/cmd.sock
           for commands from launchscoped.
  State  — monitors the CEC bus for power and source changes, pushing
           live state to launchscoped via HTTP.

Socket commands:
  activate     — ReportPhysicalAddress + DeviceVendorID + TextViewOn + ActiveSource
  power-on     — TextViewOn to TV only (wake without switching input)
  set-source   — ActiveSource broadcast (switch input without waking)
  standby      — standby AVR (or TV if no AVR); skipped if not active source

Two topologies are supported:

  PC → TV directly (CEC_HAS_AVR=0):
    standby  → standby(TV)

  PC → AVR → TV (CEC_HAS_AVR=1, default):
    standby  → standby(AVR) — TV powers off via signal loss

Configuration via environment variables:
  CEC_HAS_AVR            1 if an AVR is present (default: 1). AVR logical address
                         is always 5 per the CEC spec.
  CEC_SOURCE_ADDR        physical address of the host PC on the CEC bus, e.g. "1.6.0.0"
                         (required). Run: echo 'scan' | cec-client -s -d 1
  CEC_VERBOSE            set to 1 for verbose libcec logging (default: 0)
  LAUNCHSCOPE_SERVER_URL URL of launchscoped for pushing CEC state
                         (default: http://127.0.0.1:8765)
"""

import cec
import json
import os
import socket
import sys
import struct
import threading
import urllib.request

from evdev import UInput, ecodes as e

SOCKET_PATH = "/run/launchscope-cec/cmd.sock"

CEC_TV = 0  # always 0 per CEC spec (TV logical address)
CEC_AVR_LOGICAL = 5  # always 5 per CEC spec (Audio System logical address)
CEC_AVR = CEC_AVR_LOGICAL if os.environ.get("CEC_HAS_AVR", "1") == "1" else None
CEC_SOURCE_ADDR = os.environ.get("CEC_SOURCE_ADDR", "")
CEC_VERBOSE = os.environ.get("CEC_VERBOSE", "0") == "1"
SERVER_URL = os.environ.get("LAUNCHSCOPE_SERVER_URL", "http://127.0.0.1:8765")
SERVER_API_KEY = os.environ.get("LAUNCHSCOPE_API_KEY", "")

OWN_LOGICAL = 1  # libcec always registers as Recorder 1

# CEC UI Command codes → Linux key codes
CEC_KEYMAP = {
    0x00: e.KEY_ENTER,
    0x01: e.KEY_UP,
    0x02: e.KEY_DOWN,
    0x03: e.KEY_LEFT,
    0x04: e.KEY_RIGHT,
    0x09: e.KEY_HOME,
    0x0D: e.KEY_ESC,
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
    0x4A: e.KEY_FASTFORWARD,
    0x4C: e.KEY_NEXTSONG,
    0x4D: e.KEY_PREVIOUSSONG,
    0x60: e.KEY_INFO,
    0x6A: e.KEY_POWER,
    0x71: e.KEY_BLUE,
    0x72: e.KEY_RED,
    0x73: e.KEY_GREEN,
    0x74: e.KEY_YELLOW,
}

CEC_NAMES = {
    0x00: "Select",
    0x01: "Up",
    0x02: "Down",
    0x03: "Left",
    0x04: "Right",
    0x09: "Home",
    0x0D: "Exit",
    0x44: "Play",
    0x46: "Pause",
    0x49: "Rewind",
    0x4A: "FastFwd",
    0x4C: "Next",
    0x4D: "Prev",
    0x71: "Blue",
    0x72: "Red",
    0x73: "Green",
    0x74: "Yellow",
}

ui = None
pressed_key = None

# ── CEC state ─────────────────────────────────────────────────────────────── #
_state_lock = threading.Lock()
_tv_on = False
_avr_on = False
_active_source = None  # logical addr (int) of current active source, or None
_is_active_source = False  # _active_source == OWN_LOGICAL

# Physical address (2-byte big-endian hex) → logical address.
# Populated from environment + known fixed addresses.
_PHYS_TO_LOGICAL: dict[bytes, int] = {
    bytes.fromhex("0000"): 0,  # TV always 0.0.0.0
}


def _build_phys_map():
    """Populate _PHYS_TO_LOGICAL from configured addresses."""
    if CEC_SOURCE_ADDR:
        addr_bytes = parse_physical_addr(CEC_SOURCE_ADDR)
        _PHYS_TO_LOGICAL[addr_bytes] = OWN_LOGICAL


def on_source_activated(event, logical_addr, activated):
    # EVENT_ACTIVATED only fires for our own device — not useful for tracking
    # which device is currently active. Active source tracking is done via
    # on_command watching for ActiveSource (0x82) and RoutingChange (0x80).
    pass


def on_command(event, cmd):
    """Track active source and power state from incoming CEC commands."""
    global _active_source, _is_active_source, _tv_on, _avr_on
    opcode = cmd.get("opcode")
    initiator = cmd.get("initiator")
    params = cmd.get("parameters", b"")

    # TV power ON — ReportPowerStatus (0x90) from TV with params=0x00
    if opcode == 0x90 and initiator == CEC_TV and params and params[0] == 0x00:
        with _state_lock:
            if _tv_on:
                return
            _tv_on = True
        print("launchscope-cec: TV power on", flush=True)
        push_state()

    # TV standby — Standby (0x36) broadcast from TV
    elif opcode == 0x36 and initiator == CEC_TV:
        with _state_lock:
            if not _tv_on and not _avr_on:
                return
            _tv_on = False
            _avr_on = False
        print("launchscope-cec: TV standby — marking AVR off too", flush=True)
        push_state()

    # AVR on/off — SetSystemAudioMode (0x72) from AVR
    elif opcode == 0x72 and CEC_AVR is not None and initiator == CEC_AVR:
        avr_on = bool(params) and params[0] == 0x01
        with _state_lock:
            if avr_on == _avr_on:
                return
            _avr_on = avr_on
        print(f"launchscope-cec: AVR system audio → {'on' if avr_on else 'off'}", flush=True)
        push_state()

    # ActiveSource (0x82) — device announcing itself as active source
    elif opcode == cec.CEC_OPCODE_ACTIVE_SOURCE:
        if initiator is None:
            return
        with _state_lock:
            if _active_source == initiator:
                return
            _active_source = initiator
            _is_active_source = initiator == OWN_LOGICAL
        print(
            f"launchscope-cec: active source → logical {initiator} (us={_is_active_source})",
            flush=True,
        )
        push_state()

    # RoutingChange (0x80) from AVR — new physical addr in params[2:4]
    elif opcode == 0x80 and CEC_AVR is not None and initiator == CEC_AVR:
        if len(params) < 4:
            return
        new_phys = bytes(params[2:4])
        logical = _PHYS_TO_LOGICAL.get(new_phys)
        if logical is None:
            return  # unknown/dummy device — ignore
        with _state_lock:
            if _active_source == logical:
                return
            _active_source = logical
            _is_active_source = logical == OWN_LOGICAL
        print(
            f"launchscope-cec: routing change → physical {new_phys.hex()} logical {logical}",
            flush=True,
        )
        push_state()


def push_state():
    """POST current CEC state to the Go server."""
    with _state_lock:
        payload = {
            "tv_on": _tv_on,
            "avr_on": _avr_on,
            "active_source": _active_source,
            "is_active_source": _is_active_source,
        }
    body = json.dumps(payload).encode()
    headers = {"Content-Type": "application/json"}
    if SERVER_API_KEY:
        headers["X-Api-Key"] = SERVER_API_KEY
    try:
        req = urllib.request.Request(
            f"{SERVER_URL}/api/cec/state",
            data=body,
            headers=headers,
            method="POST",
        )
        urllib.request.urlopen(req, timeout=5)
    except Exception as ex:
        print(f"launchscope-cec: push_state error: {ex}", flush=True)


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
    cec.transmit(
        cec.CECDEVICE_BROADCAST, cec.CEC_OPCODE_REPORT_PHYSICAL_ADDRESS, addr_bytes + bytes([0x04])
    )


def do_device_vendor_id():
    cec.transmit(
        cec.CECDEVICE_BROADCAST, cec.CEC_OPCODE_DEVICE_VENDOR_ID, bytes([0x00, 0x15, 0x82])
    )


def do_set_source():
    global _active_source, _is_active_source
    if not CEC_SOURCE_ADDR:
        print(
            "launchscope-cec: set-source — CEC_SOURCE_ADDR not set, falling back to set_active_source()",
            flush=True,
        )
        cec.set_active_source()
    else:
        addr_bytes = parse_physical_addr(CEC_SOURCE_ADDR)
        cec.transmit(cec.CECDEVICE_BROADCAST, cec.CEC_OPCODE_ACTIVE_SOURCE, addr_bytes)
        # SystemAudioModeRequest to AVR — explicitly asks it to wake and take
        # audio control. Parameters are our physical address.
        if CEC_AVR is not None:
            cec.transmit(CEC_AVR, cec.CEC_OPCODE_SYSTEM_AUDIO_MODE_REQUEST, addr_bytes)
    # Outgoing ActiveSource is not echoed back via EVENT_COMMAND — update state directly.
    with _state_lock:
        _active_source = OWN_LOGICAL
        _is_active_source = True
    push_state()


def do_standby():
    with _state_lock:
        active = _is_active_source
    if not active:
        print("launchscope-cec: standby — skipped, host PC is not the active source", flush=True)
        return
    if CEC_AVR is not None:
        cec.Device(CEC_AVR).standby()
    else:
        cec.Device(CEC_TV).standby()


def handle_command(cmd):
    """Handle a command received on the Unix socket."""
    cmd = cmd.strip().lower()
    if cmd == "power-on":
        print(f"launchscope-cec: power-on — ImageViewOn to TV ({CEC_TV})", flush=True)
        try:
            do_power_on()
            print("launchscope-cec: power-on done", flush=True)
        except Exception as ex:
            print(f"launchscope-cec: power-on error: {ex}", flush=True)
    elif cmd == "set-source":
        print(f"launchscope-cec: set-source — ActiveSource {CEC_SOURCE_ADDR}", flush=True)
        try:
            do_set_source()
            print("launchscope-cec: set-source done", flush=True)
        except Exception as ex:
            print(f"launchscope-cec: set-source error: {ex}", flush=True)
    elif cmd == "standby":
        print(f"launchscope-cec: standby — AVR ({CEC_AVR})", flush=True)
        try:
            do_standby()
            print("launchscope-cec: standby done", flush=True)
        except Exception as ex:
            print(f"launchscope-cec: standby error: {ex}", flush=True)
    elif cmd == "activate":
        print(
            "launchscope-cec: activate — ReportPhysicalAddress, DeviceVendorID, TextViewOn, ActiveSource",
            flush=True,
        )
        try:
            do_report_physical_addr()
            do_device_vendor_id()
            do_power_on()
            do_set_source()
            print("launchscope-cec: activate done", flush=True)
        except Exception as ex:
            print(f"launchscope-cec: activate error: {ex}", flush=True)
    else:
        print(f"launchscope-cec: unknown command '{cmd}'", flush=True)


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
    print(f"launchscope-cec: command socket at {SOCKET_PATH}", flush=True)

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
            print(f"launchscope-cec: socket error: {ex}", flush=True)


def main():
    global ui

    print(
        f"launchscope-cec: starting (tv={CEC_TV} avr={CEC_AVR} source={CEC_SOURCE_ADDR!r})",
        flush=True,
    )
    ui = UInput(
        {e.EV_KEY: sorted(set(CEC_KEYMAP.values()))},
        name="launchscope-cec",
        vendor=0x0001,
        product=0x0001,
        version=0x0111,
        bustype=0x03,
    )
    print("launchscope-cec: uinput device created", flush=True)

    if not CEC_SOURCE_ADDR:
        print(
            "launchscope-cec: error — CEC_SOURCE_ADDR is required. Run: echo 'scan' | cec-client -s -d 1",
            flush=True,
        )
        sys.exit(1)

    cec.set_physical_addr(CEC_SOURCE_ADDR)
    cec.init()
    _build_phys_map()
    if CEC_VERBOSE:
        cec.add_callback(on_log, cec.EVENT_LOG)
    cec.add_callback(on_keypress, cec.EVENT_KEYPRESS)
    cec.add_callback(on_source_activated, cec.EVENT_ACTIVATED)
    cec.add_callback(on_command, cec.EVENT_COMMAND)
    print("launchscope-cec: libcec initialised", flush=True)

    t = threading.Thread(target=socket_server, daemon=True)
    t.start()

    print("launchscope-cec: ready", flush=True)

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
    print(f"launchscope-cec [libcec]: {message}", flush=True)


def on_keypress(event, keycode, duration):
    global pressed_key
    key = CEC_KEYMAP.get(keycode)
    if key is None:
        print(f"launchscope-cec: unmapped CEC 0x{keycode:02x}", flush=True)
        return
    name = CEC_NAMES.get(keycode, f"0x{keycode:02x}")
    if duration == 0:
        ui.write(e.EV_KEY, key, 1)
        ui.syn()
        pressed_key = key
        print(f"launchscope-cec: press {name} → {e.KEY[key]}", flush=True)
    else:
        if pressed_key is not None:
            ui.write(e.EV_KEY, pressed_key, 0)
            ui.syn()
            pressed_key = None


if __name__ == "__main__":
    main()
