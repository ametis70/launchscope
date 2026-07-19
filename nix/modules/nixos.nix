self:
{ config, lib, pkgs, ... }:

# NixOS system-level module for Launchscope.
# `self` is the launchscope flake, captured in the closure by flake.nix.
#
# This module only handles system-level concerns:
#   - Autologin so the user's systemd session starts on boot
#   - Group membership (video, input) for DRM/KMS and uinput access
#   - Installing the packages
#   - Optional launchscope-cec bridge service for HDMI-CEC control
#
# The daemon lifecycle (launchscoped.service) and all config files are
# managed by the Home Manager module. The daemon itself owns every gamescope
# session — it launches the UI and apps. The login shell does nothing.

let
  cfg      = config.services.launchscope;
  selfPkgs = self.packages.${pkgs.system};

  anyDmEnabled =
    (config.services.xserver.displayManager.lightdm.enable or false) ||
    (config.services.displayManager.sddm.enable             or false) ||
    (config.services.xserver.displayManager.gdm.enable      or false) ||
    (config.services.greetd.enable                          or false) ||
    (config.services.xserver.displayManager.ly.enable       or false);

in
{
  options.services.launchscope = {

    enable = lib.mkEnableOption "Launchscope HTPC launcher (system-level config)";

    user = lib.mkOption {
      type        = lib.types.str;
      example     = "htpc";
      description = "The user that Launchscope runs as. Autologged in on the configured TTY.";
    };

    package = lib.mkOption {
      type        = lib.types.package;
      default     = selfPkgs.launchscope;
      defaultText = lib.literalExpression "launchscope";
      description = "The launchscope UI package.";
    };

    serverPackage = lib.mkOption {
      type        = lib.types.package;
      default     = selfPkgs.launchscoped;
      defaultText = lib.literalExpression "launchscoped";
      description = "The launchscoped server package.";
    };

    autologin = {
      enable = lib.mkOption {
        type    = lib.types.bool;
        default = true;
        description = ''
          Configure passwordless autologin for the Launchscope user.
          This starts the user's systemd session which runs launchscoped.service.
          Incompatible with a display manager being enabled simultaneously.
        '';
      };
      tty = lib.mkOption {
        type    = lib.types.str;
        default = "tty1";
        description = "Virtual terminal to autologin on.";
      };
    };

    cec = {
      enable = lib.mkOption {
        type    = lib.types.bool;
        default = false;
        description = ''
          Enable the launchscope-cec bridge service.
          Connects to a Pulse-Eight USB CEC adapter, forwards remote control
          button presses as uinput keyboard events, and exposes a Unix socket
          at /run/launchscope-cec/cmd.sock for CEC commands (power-on, set-source,
          standby, activate) from launchscoped.
        '';
      };
      adapterDevice = lib.mkOption {
        type    = lib.types.str;
        default = "ttyACM0";
        description = "Serial device name for the CEC adapter (e.g. ttyACM0).";
      };
      hasAvr = lib.mkOption {
        type    = lib.types.bool;
        default = true;
        description = ''
          Whether an AVR (Audio System) is present in the CEC topology.
          With AVR: standby goes to the AVR only (TV powers off via signal loss).
          Without AVR: standby goes to the TV directly.
          The AVR logical address is always 5 per the CEC spec.
        '';
      };
      sourceAddr = lib.mkOption {
        type    = lib.types.str;
        default = "";
        example = "1.6.0.0";
        description = ''
          Physical CEC address of the host PC as seen on the bus, e.g. "1.6.0.0"
          (AVR on TV port 1, host PC on AVR port 6). Used by set-source and
          activate to broadcast the correct ActiveSource message.
          Run: echo 'scan' | cec-client -s -d 1
          to discover addresses on your bus.
        '';
      };
      verbose = lib.mkOption {
        type    = lib.types.bool;
        default = false;
        description = "Enable verbose libcec logging.";
      };
      serverPort = lib.mkOption {
        type    = lib.types.int;
        default = 8765;
        description = "Port that launchscoped listens on. Used by launchscope-cec to push CEC state.";
      };
      package = lib.mkOption {
        type        = lib.types.package;
        default     = selfPkgs.launchscope-cec;
        defaultText = lib.literalExpression "launchscope-cec";
        description = "The launchscope-cec bridge package.";
      };
    };
  };

  config = lib.mkIf cfg.enable {

    assertions = [
      {
        assertion = !(cfg.autologin.enable && anyDmEnabled);
        message   = "services.launchscope.autologin.enable = true conflicts with an enabled display manager.";
      }
      { assertion = cfg.user != ""; message = "services.launchscope.user must not be empty."; }
    ];

    # Autologin so the user's systemd session (and launchscoped.service) starts on boot.
    services.getty = lib.mkIf cfg.autologin.enable {
      autologinUser = cfg.user;
    };

    systemd.services."getty@${cfg.autologin.tty}" =
      lib.mkIf (cfg.autologin.enable && cfg.autologin.tty != "tty1") {
        overrideStrategy = "asDropin";
        serviceConfig.ExecStart = lib.mkForce [
          ""
          "${pkgs.util-linux}/sbin/agetty --login-program ${pkgs.shadow}/bin/login --autologin ${cfg.user} --noclear %I $TERM"
        ];
      };

    # DRM/KMS access for gamescope; uinput for the CEC bridge.
    users.users.${cfg.user}.extraGroups = [ "video" "input" ];

    environment.systemPackages = [
      pkgs.gamescope
      cfg.package
      cfg.serverPackage
    ] ++ lib.optional cfg.cec.enable cfg.cec.package;

    # CEC → uinput bridge (optional).
    systemd.services.launchscope-cec = lib.mkIf cfg.cec.enable {
      description = "HDMI-CEC to uinput bridge (Pulse-Eight adapter)";
      after       = [ "dev-${cfg.cec.adapterDevice}.device" ];
      wants       = [ "dev-${cfg.cec.adapterDevice}.device" ];
      wantedBy    = [ "default.target" ];

      serviceConfig = {
        ExecStart           = "${cfg.cec.package}/bin/launchscope-cec";
        Restart             = "on-failure";
        RestartSec          = "3";
        SupplementaryGroups = [ "dialout" "input" ];
        RuntimeDirectory    = "launchscope-cec";
        Environment = [
          "CEC_HAS_AVR=${if cfg.cec.hasAvr then "1" else "0"}"
          "CEC_SOURCE_ADDR=${cfg.cec.sourceAddr}"
          "CEC_VERBOSE=${if cfg.cec.verbose then "1" else "0"}"
          "LAUNCHSCOPE_SERVER_URL=http://127.0.0.1:${toString cfg.cec.serverPort}"
        ];
      };
    };

    # Give the launchscope-cec virtual device a stable symlink.
    services.udev.extraRules = lib.mkIf cfg.cec.enable ''
      KERNEL=="event*", ATTRS{name}=="launchscope-cec", SYMLINK+="input/cec-remote", MODE="0664", GROUP="input"
    '';
  };
}
