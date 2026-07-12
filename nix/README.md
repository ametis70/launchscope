<div align="center">

# launchscope — Nix

![license](https://img.shields.io/github/license/ametis70/launchscope?style=flat-square)
![nix](https://img.shields.io/badge/nix-flake-5277C3?style=flat-square&logo=nixos&logoColor=white)

NixOS module, Home Manager module, packages, and development shell.

<br>

</div>

## Flake outputs

```
packages.<system>.launchscoped    Go daemon
packages.<system>.launchscope     LÖVE2D UI
packages.<system>.cec-uinput      HDMI-CEC bridge
packages.<system>.default         → launchscoped

nixosModules.default              NixOS system module
homeManagerModules.default        Home Manager user module
devShells.<system>.default        Development shell
```

Supported systems: `x86_64-linux`, `aarch64-linux`.

## Packages

### `launchscoped`

The Go HTTP daemon. Built with `buildGoModule`; dependencies fetched via the Go module proxy (no vendor directory).

```nix
nix build .#launchscoped
```

### `launchscope`

The LÖVE2D frontend. The source tree is zipped into a `.love` archive at build time. The installed binary is a shell wrapper that runs `gamescope-args.lua` to determine the session mode and prepend gamescope if needed.

Fonts are **not** bundled — resolved at runtime via `fc-match`.

```nix
nix build .#launchscope
```

### `cec-uinput`

The HDMI-CEC bridge. A Python script bundled with its own Python interpreter, `python-cec` (libcec bindings), and `evdev`. Built with `buildPythonPackage` inside `mkDerivation`.

```nix
nix build .#cec-uinput
```

## NixOS module

`nixosModules.default` — system-level concerns only: autologin, group membership, system packages, and the optional `cec-uinput` systemd service.

```nix
# flake.nix
inputs.launchscope.nixosModules.default
```

### Options

#### `services.launchscope.enable`

Enable the module.

#### `services.launchscope.user`

The user Launchscope runs as. Autologged in on the configured TTY.

#### `services.launchscope.autologin`

| Option | Default | Description |
|---|---|---|
| `autologin.enable` | `true` | Configure passwordless autologin. Incompatible with any display manager. |
| `autologin.tty` | `"tty1"` | Virtual terminal to autologin on. |

#### `services.launchscope.cec`

| Option | Default | Description |
|---|---|---|
| `cec.enable` | `false` | Enable the `cec-uinput` bridge service |
| `cec.adapterDevice` | `"ttyACM0"` | Serial device of the Pulse-Eight adapter |
| `cec.baseDevice` | `0` | Logical CEC address of the connected device (0 = TV, 5 = AVR) |
| `cec.hdmiPort` | `1` | HDMI port on the base device |
| `cec.standbyAddr` | `null` | Address to send standby to (defaults to `baseDevice`) |
| `cec.verbose` | `false` | Enable verbose libcec logging |

### Example

```nix
services.launchscope = {
  enable = true;
  user   = "htpc";
  autologin.tty = "tty1";
  cec = {
    enable       = true;
    adapterDevice = "ttyACM0";
    baseDevice   = 0;
    hdmiPort     = 1;
  };
};
```

## Home Manager module

`homeManagerModules.default` — user-level concerns: config files, fonts, and the `launchscoped.service` systemd user unit.

Writes three config files into `~/.config/`:

| File | Purpose |
|---|---|
| `launchscope/config.json` | UI settings (session mode, display, font, idle…) |
| `launchscoped/config.json` | Daemon settings (API port, key, CEC) |
| `launchscoped/apps.json` | App list |

```nix
# flake.nix
inputs.launchscope.homeManagerModules.default
```

### Options

#### `programs.launchscope.enable`

Enable the module.

#### `programs.launchscope.settings.api`

| Option | Default | Description |
|---|---|---|
| `api.port` | `8765` | HTTP listen port |
| `api.api_key` | `""` | Inline API key. If empty, the daemon auto-generates one on first boot. |
| `api.api_key_file` | `""` | Path to a file containing the key (e.g. an agenix secret). Takes precedence over `api_key`. |

The recommended approach for keeping the key out of the Nix store is `api_key_file` with a secret manager:

```nix
# agenix
age.secrets.launchscope-key.file = ./secrets/launchscope-key.age;
programs.launchscope.settings.api.api_key_file =
  config.age.secrets.launchscope-key.path;

# sops-nix
sops.secrets."launchscope/api_key" = {};
programs.launchscope.settings.api.api_key_file =
  config.sops.secrets."launchscope/api_key".path;
```

If neither field is set, the daemon auto-generates a random key on first boot and writes it to `~/.config/launchscoped/api_key` (`0600`).

#### `programs.launchscope.settings.cec`

| Option | Default | Description |
|---|---|---|
| `cec.enabled` | `false` | Enable CEC control endpoints in the daemon API |
| `cec.switch_port` | `0` | HDMI port used by `POST /api/cec/switch-input` (0 = disabled) |

#### `programs.launchscope.settings.ui`

| Option | Default | Description |
|---|---|---|
| `ui.session_mode` | `"drm_gamescope"` | `"drm_gamescope"`, `"nested_gamescope"`, or `"nested_direct"` |
| `ui.process_mode` | `"daemon"` | `"daemon"` or `"standalone"` |
| `ui.font` | `"departure-mono"` | Nerd Font key — the package is installed automatically |
| `ui.scale` | `1.0` | UI scale multiplier (`0.5`–`3.0`) |
| `ui.icons` | `"pixel"` | `"pixel"`, `"unicode"`, or `"none"` |
| `ui.display` | — | Gamescope config for the launcher window (see below) |
| `ui.background.type` | `"shader"` | `"shader"` or `"solid"` |
| `ui.background.animate` | `true` | Animate the shader |
| `ui.background.color` | `"#0d1440"` | Background colour (hex) |
| `ui.idle.dim_timeout` | `60` | Seconds before dimming. `0` = disabled |
| `ui.idle.blank_timeout` | `0` | Seconds before blanking. `0` = disabled |
| `ui.idle.blank_mode` | `"wlopm"` | `"wlopm"` or `"cec"`. `"cec"` sends CEC standby/activate via the daemon's API (daemon mode only) |
| `ui.idle.blank_off` | `""` | Shell command to blank display (`blank_mode = "wlopm"` only) |
| `ui.idle.blank_on` | `""` | Shell command to unblank display (`blank_mode = "wlopm"` only) |

#### `programs.launchscope.settings.apps`

List of apps shown in the launcher. Each app:

| Field | Type | Description |
|---|---|---|
| `id` | string | Unique identifier (`[a-z0-9_-]+`) |
| `name` | string | Display name |
| `exec` | string | Command to run |
| `gamescope.enabled` | bool | Wrap in gamescope (default `true`) |
| `gamescope.output` | `{ width, height, refresh }` | Output resolution |
| `gamescope.inner` | `{ width, height }` | Render resolution (for upscaling) |
| `gamescope.filter` | string | `linear`, `nearest`, `fsr`, `nis`, `pixel` |
| `gamescope.hdr` | bool | `--hdr-enabled` |
| `gamescope.extra_flags` | string[] | Verbatim extra gamescope flags |

### Example

```nix
programs.launchscope = {
  enable = true;

  settings = {
    api.api_key_file = config.age.secrets.launchscope-key.path;

    ui = {
      session_mode = "drm_gamescope";
      process_mode = "daemon";
      font         = "departure-mono";
      scale        = 1.0;
      display.output = { width = 2560; height = 1440; refresh = 120; };
      idle.dim_timeout = 60;
    };

    apps = [
      {
        id   = "kodi";
        name = "Kodi";
        exec = "${pkgs.kodi-wayland}/bin/kodi-standalone";
        gamescope = {
          enabled  = true;
          output   = { width = 3840; height = 2160; refresh = 60; };
        };
      }
      {
        id   = "steam";
        name = "Steam";
        exec = "start-gamescope-session";
        gamescope.enabled = false;
      }
    ];
  };
};
```

## Development shell

```nix
nix develop
# or with direnv
direnv allow
```

After changing `flake.nix` or `shell.nix`, refresh the nix-direnv cache:

```bash
touch .envrc          # mark stale — fastest
# or
direnv reload         # force full reload
```

### Scripts

| Script | Session mode | Process mode | Description |
|---|---|---|---|
| `ls-ui` | `nested_direct` | `daemon` | Windowed UI, connects to a running `launchscoped` |
| `ls-ui-gs` | `nested_gamescope` | `daemon` | Gamescope window, connects to a running `launchscoped` |
| `ls-ui-standalone` | `nested_direct` | `standalone` | Windowed UI, manages apps directly |
| `ls-ui-standalone-gs` | `nested_gamescope` | `standalone` | Gamescope window, manages apps directly |
| `ls-dev` | `nested_direct` | `daemon` | Starts `launchscoped` from source; daemon launches the UI automatically |
| `ls-server-test` | — | — | Runs the Go server test suite. Pass `--coverage` to write `server/cover.out` and open an HTML report. |
| `ls-ha-test` | — | — | Runs the Home Assistant integration test suite (venv created automatically on first run) |

`ls-ha-test` creates and populates the venv automatically on first run. `pytest-homeassistant-custom-component` and its transitive Home Assistant dependencies are not packaged in nixpkgs, so pip is used for this one task.
