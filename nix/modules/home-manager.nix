self:
{
  config,
  lib,
  pkgs,
  ...
}:

# Home Manager module for Launchscope.
#
# Writes config files:
#   ~/.config/launchscope/config.json   — UI settings
#   ~/.config/launchscoped/apps.json    — app list for the daemon
#   ~/.config/launchscoped/config.json  — daemon settings

let
  cfg = config.programs.launchscope;
  fmt = pkgs.formats.json { };
  selfPkgs = self.packages.${pkgs.system};

  # Nerd Fonts supported by the module.
  fontDefs = {
    departure-mono = {
      package = pkgs.nerd-fonts.departure-mono;
      fcName = "DepartureMono Nerd Font";
    };
  };

  selectedFontDef = fontDefs.${cfg.settings.ui.font} or fontDefs.departure-mono;
  fontPackage = selectedFontDef.package;
  fontFcName = selectedFontDef.fcName;

  # ── Gamescope submodule (shared by display and per-app gamescope) ──────── #

  # Common gamescope options shared by display config and per-app config.
  gamescopeBaseOptions = {
    fullscreen = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    output = {
      width = lib.mkOption {
        type = lib.types.int;
        default = 1920;
      };
      height = lib.mkOption {
        type = lib.types.int;
        default = 1080;
      };
      refresh = lib.mkOption {
        type = lib.types.int;
        default = 60;
      };
    };
    inner = {
      width = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
      };
      height = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
      };
    };
    filter = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "linear"
          "nearest"
          "fsr"
          "nis"
          "pixel"
        ]
      );
      default = null;
    };
    scaler = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "auto"
          "integer"
          "fit"
          "fill"
          "stretch"
        ]
      );
      default = null;
    };
    sharpness = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
    };
    hdr = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
    adaptive_sync = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
    force_grab = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
    expose_wayland = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
    composite_debug = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
    mangoapp = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
    extra_flags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
  };

  gamescopeOpts = { ... }: { options = gamescopeBaseOptions; };

  # Per-app gamescope adds an 'enabled' toggle.
  gamescopeAppOpts = { ... }: {
    options = gamescopeBaseOptions // {
      enabled = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
    };
  };

  appOpts = { ... }: {
    options = {
      id = lib.mkOption { type = lib.types.strMatching "[a-z0-9_-]+"; };
      name = lib.mkOption { type = lib.types.str; };
      exec = lib.mkOption { type = lib.types.str; };
      gamescope = lib.mkOption {
        type = lib.types.submodule gamescopeAppOpts;
        default = { };
      };
    };
  };

  # UI config written to launchscope/config.json.
  uiConfig = fmt.generate "launchscope-config.json" {
    session_mode = cfg.settings.ui.session_mode;
    process_mode = cfg.settings.ui.process_mode;
    font = fontFcName;
    icons = cfg.settings.ui.icons;
    icon_size = cfg.settings.ui.icon_size;
    scale = cfg.settings.ui.scale;
    display = cfg.settings.ui.display;
    background = cfg.settings.ui.background;
    idle = {
      dim_timeout           = cfg.settings.ui.idle.dim_timeout;
      blank_timeout         = cfg.settings.ui.idle.blank_timeout;
      blank_mode            = cfg.settings.ui.idle.blank_mode;
      cec_activate_on_start = cfg.settings.ui.idle.cec_activate_on_start;
      cec_poll_interval     = cfg.settings.ui.idle.cec_poll_interval;
      cec_poll_mode         = cfg.settings.ui.idle.cec_poll_mode;
    }
    // lib.optionalAttrs (cfg.settings.ui.idle.blank_off != "") {
      blank_off = cfg.settings.ui.idle.blank_off;
    }
    // lib.optionalAttrs (cfg.settings.ui.idle.blank_on != "") {
      blank_on = cfg.settings.ui.idle.blank_on;
    };
  };

  daemonConfig = fmt.generate "launchscoped-config.json" {
    api = {
      port = cfg.settings.api.port;
    }
    // lib.optionalAttrs (cfg.settings.api.api_key_file != "") {
      api_key_file = cfg.settings.api.api_key_file;
    };
    cec = cfg.settings.cec;
  };
  appsConfig = fmt.generate "launchscoped-apps.json" cfg.settings.apps;

in
{
  options.programs.launchscope = {

    enable = lib.mkEnableOption "Launchscope HTPC launcher";

    package = lib.mkOption {
      type = lib.types.package;
      default = selfPkgs.launchscope;
    };

    serverPackage = lib.mkOption {
      type = lib.types.package;
      default = selfPkgs.launchscoped;
    };

    settings = {
      api = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 8765;
        };
        api_key = lib.mkOption {
          type = lib.types.str;
          default = "";
          example = "my-secret-key";
          description = ''
            Inline API key. If empty and api_key_file is also unset, the daemon
            generates a key on first boot and writes it to
            $XDG_CONFIG_HOME/launchscoped/api_key.
          '';
        };
        api_key_file = lib.mkOption {
          type = lib.types.str;
          default = "";
          example = "/run/secrets/launchscope-api-key";
          description = ''
            Path to a file containing the API key (one line; leading/trailing
            whitespace is stripped). Takes precedence over api_key. Intended for
            use with secret managers such as agenix or sops-nix that write
            secrets to a path at activation time.
          '';
        };
      };

      cec = {
        enabled = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable HDMI-CEC control via the launchscope-cec socket.";
        };
      };

      ui = {
        session_mode = lib.mkOption {
          type = lib.types.enum [
            "drm_gamescope"
            "nested_gamescope"
            "nested_direct"
          ];
          default = "drm_gamescope";
          description = ''
            How the launcher session itself is run.
            - drm_gamescope    — gamescope owns the display via KMS/DRM (default)
            - nested_gamescope — gamescope runs inside an existing compositor
            - nested_direct    — love runs directly inside an existing compositor
          '';
        };

        process_mode = lib.mkOption {
          type = lib.types.enum [
            "daemon"
            "standalone"
          ];
          default = "daemon";
          description = ''
            Who manages app processes.
            - daemon     — delegates to launchscoped over HTTP (default)
            - standalone — manages processes directly, no daemon needed
          '';
        };

        font = lib.mkOption {
          type = lib.types.enum (lib.attrNames fontDefs);
          default = "departure-mono";
          description = "Nerd Font to use. The package is installed automatically.";
        };

        scale = lib.mkOption {
          type = lib.types.float;
          default = 1.0;
          description = "UI scale multiplier (0.5–3.0).";
        };

        icons = lib.mkOption {
          type = lib.types.enum [
            "pixel"
            "unicode"
            "none"
          ];
          default = "pixel";
          description = ''
            Icon rendering mode.
            - pixel   — pre-bundled pixel art PNG assets (default); tinted at runtime
            - unicode — Nerd Font codepoint glyphs (requires a Nerd Font)
            - none    — no icons
          '';
        };

        icon_size = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
        };

        display = lib.mkOption {
          type = lib.types.submodule gamescopeOpts;
          default = { };
          description = "Gamescope session config for the launcher window.";
        };

        background = {
          type = lib.mkOption {
            type = lib.types.enum [
              "shader"
              "solid"
            ];
            default = "shader";
          };
          animate = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Shader only: false = static first frame.";
          };
          color = lib.mkOption {
            type = lib.types.str;
            default = "#0d1440";
            description = "Solid only: hex colour (#rrggbb).";
          };
        };

        idle = {
          dim_timeout = lib.mkOption {
            type = lib.types.int;
            default = 60;
            description = "Seconds of inactivity before the screen starts dimming. 0 = disabled.";
          };
          blank_timeout = lib.mkOption {
            type = lib.types.int;
            default = 0;
            description = "Seconds of inactivity before blanking the display. 0 = disabled (default).";
          };
          blank_mode = lib.mkOption {
            type = lib.types.enum [ "wlopm" "cec" ];
            default = "wlopm";
            description = ''
              Blank mode. "wlopm" runs the blank_off/blank_on shell commands (default).
              "cec" sends standby/activate via the daemon's CEC API, physically powering
              the display off rather than just blanking the output. Only valid in daemon
              process mode.
            '';
          };
          cec_activate_on_start = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              When blank_mode = "cec" and process_mode = "daemon", send a CEC activate
              command (power on + set active source) when the UI starts. Set to false
              to suppress the startup activation.
            '';
          };
          blank_off = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = ''
              Shell command to turn the display off. Leave empty to use the
              bundled wlopm default (correct for DRM/gamescope mode).
            '';
          };
          blank_on = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = ''
              Shell command to turn the display back on. Leave empty to use the
              bundled wlopm default (correct for DRM/gamescope mode).
            '';
          };
          cec_poll_interval = lib.mkOption {
            type = lib.types.int;
            default = 5;
            description = ''
              Seconds between CEC state polls when blank_mode = "cec".
              Controls how quickly the UI reacts to TV/source changes.
            '';
          };
          cec_poll_mode = lib.mkOption {
            type = lib.types.enum [ "http" ];
            default = "http";
            description = ''
              CEC state polling mode. "http" polls /api/cec/state over HTTP.
              "ws" (WebSocket) is reserved for future use.
            '';
          };
        };
      };

      apps = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule appOpts);
        default = [ ];
        description = "Apps shown in the launcher.";
      };
    };
  };

  config = lib.mkIf cfg.enable {

    assertions = [
      {
        assertion = cfg.settings.ui.scale >= 0.5 && cfg.settings.ui.scale <= 3.0;
        message = "programs.launchscope.settings.ui.scale must be 0.5–3.0.";
      }
    ];

    home.packages = [
      cfg.package
      cfg.serverPackage
      fontPackage
    ];

    xdg.configFile."launchscope/config.json".source = uiConfig;
    xdg.configFile."launchscoped/config.json".source = daemonConfig;
    xdg.configFile."launchscoped/apps.json".source = appsConfig;

    # When api_key is set, write it as a store-backed symlink (immutable,
    # like all other config files). If unset, the daemon auto-generates
    # ~/.config/launchscoped/api_key on first boot and reuses it.
    # To keep the key out of the store entirely, use api_key_file instead.
    xdg.configFile."launchscoped/api_key" = lib.mkIf (cfg.settings.api.api_key != "") {
      source = pkgs.writeText "launchscoped-api-key" cfg.settings.api.api_key;
    };

    systemd.user.services.launchscoped = {
      Unit = {
        Description = "Launchscope HTPC launcher daemon";
        After = [
          "pipewire.service"
          "wireplumber.service"
        ];
        Wants = [
          "pipewire.service"
          "wireplumber.service"
        ];
      };
      Service = {
        ExecStart = "${cfg.serverPackage}/bin/launchscoped";
        Restart = "always";
        RestartSec = "2";
        Environment = [
          "XDG_CONFIG_HOME=%h/.config"
          "XDG_RUNTIME_DIR=/run/user/%U"
          "LAUNCHSCOPE_BIN=${cfg.package}/bin/launchscope"
          # Required for Steam's gamescope integration mode (-e flag)
          "ENABLE_GAMESCOPE_WSI=1"
          # cec-client must be on PATH for the CEC activate endpoint.
          # Also include the user profile bin so app executables are found.
          "PATH=${lib.makeBinPath [ pkgs.libcec ]}:/etc/profiles/per-user/%u/bin:/run/current-system/sw/bin"
        ];
        # Disable core dumps for this service and all child processes
        # (gamescope crashes on some apps produce large, noisy core dumps).
        LimitCORE = "0";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
