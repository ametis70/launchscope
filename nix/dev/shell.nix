{pkgs}: let
  # Default font: DepartureMono Nerd Font.
  # Override at runtime with LAUNCHSCOPE_FONT=<fc-match name or path>.
  devFont = pkgs.nerd-fonts.departure-mono;
  devFontName = "DepartureMono Nerd Font";

  # UI scripts — all four combinations of session_mode × process_mode
  # that make sense in a desktop environment (nested_* sessions only;
  # drm_gamescope requires a bare-metal DRM session).

  # nested_direct + daemon: windowed LÖVE, no gamescope, connects to launchscoped.
  ls-ui = pkgs.writeShellScriptBin "ls-ui" ''
    export LAUNCHSCOPE_SESSION_MODE=nested_direct
    exec love "$PWD/ui" "$@"
  '';

  # nested_gamescope + daemon: gamescope window inside the compositor, connects to launchscoped.
  # Reads display config (resolution, refresh, flags) from config.json via gamescope-args.lua.
  ls-ui-gs = pkgs.writeShellScriptBin "ls-ui-gs" ''
    eval $(${pkgs.lua5_4}/bin/lua "$PWD/ui/tools/gamescope-args.lua" 2>/dev/null)
    if [ -n "$GS_ARGS" ]; then
      exec $GS_ARGS -- love "$PWD/ui" "$@"
    else
      exec love "$PWD/ui" "$@"
    fi
  '';

  # nested_direct + standalone: windowed LÖVE, no gamescope, UI manages app processes directly.
  ls-ui-standalone = pkgs.writeShellScriptBin "ls-ui-standalone" ''
    export LAUNCHSCOPE_SESSION_MODE=nested_direct
    export LAUNCHSCOPE_PROCESS_MODE=standalone
    exec love "$PWD/ui" "$@"
  '';

  # nested_gamescope + standalone: gamescope window inside the compositor, UI manages app processes directly.
  ls-ui-standalone-gs = pkgs.writeShellScriptBin "ls-ui-standalone-gs" ''
    export LAUNCHSCOPE_PROCESS_MODE=standalone
    eval $(${pkgs.lua5_4}/bin/lua "$PWD/ui/tools/gamescope-args.lua" 2>/dev/null)
    if [ -n "$GS_ARGS" ]; then
      exec $GS_ARGS -- love "$PWD/ui" "$@"
    else
      exec love "$PWD/ui" "$@"
    fi
  '';

  # Run daemon + UI together from source.
  # Sets LAUNCHSCOPE_BIN so the daemon launches the UI directly from the working tree.
  # Ctrl-C stops both.
  ls-dev = pkgs.writeShellScriptBin "ls-dev" ''
    trap 'kill 0' INT TERM EXIT

    echo "  [ls-dev] starting server (will launch UI automatically)..."
    LAUNCHSCOPE_SESSION_MODE=nested_direct LAUNCHSCOPE_BIN="love $PWD/ui" \
      go -C "$PWD/server" run ./cmd/launchscoped &
    SERVER_PID=$!

    wait $SERVER_PID
  '';

  # Run the Go server test suite.
  # With --coverage: writes cover.out and opens an HTML report in the browser.
  ls-server-test = pkgs.writeShellScriptBin "ls-server-test" ''
    if [ "$1" = "--coverage" ]; then
      shift
      COVER="$PWD/server/cover.out"
      go -C "$PWD/server" test ./... -coverprofile="$COVER" "$@"
      go tool cover -func="$COVER"
      go tool cover -html="$COVER"
    else
      exec go -C "$PWD/server" test ./... "$@"
    fi
  '';

  # Run the Home Assistant integration test suite.
  # On first run, creates a venv at homeassistant/.venv and installs
  # pytest-homeassistant-custom-component from PyPI automatically.
  # pytest-homeassistant-custom-component and its transitive HA dependencies
  # are not packaged in nixpkgs, so pip is used for this one task.
  # Run the Home Assistant integration test suite.
  # On first run, creates a venv at homeassistant/.venv and installs
  # pytest-homeassistant-custom-component from PyPI automatically.
  # pytest-homeassistant-custom-component and its transitive HA dependencies
  # are not packaged in nixpkgs, so pip is used for this one task.
  ls-ha-test = pkgs.writeShellScriptBin "ls-ha-test" ''
    VENV="$PWD/homeassistant/.venv"
    REQ="$PWD/homeassistant/requirements-test.txt"
    if [ ! -x "$VENV/bin/pytest" ]; then
      echo "  [ls-ha-test] creating venv and installing dependencies..."
      python3 -m venv "$VENV"
      "$VENV/bin/pip" install --quiet -r "$REQ"
    fi
    exec "$VENV/bin/pytest" --rootdir="$PWD/homeassistant" "$PWD/homeassistant/tests" "$@"
  '';

  # Lint + format scripts

  # ── Lint ──────────────────────────────────────────────────────────────── #
  ls-lint-server = pkgs.writeShellScriptBin "ls-lint-server" ''
    cd "$PWD/server" && exec golangci-lint run ./... "$@"
  '';
  ls-lint-ui = pkgs.writeShellScriptBin "ls-lint-ui" ''
    exec luacheck "$PWD/ui" --config "$PWD/.luacheckrc" "$@"
  '';
  ls-lint-cec = pkgs.writeShellScriptBin "ls-lint-cec" ''
    exec ruff check "$PWD/cec" "$@"
  '';
  ls-lint-ha = pkgs.writeShellScriptBin "ls-lint-ha" ''
    exec ruff check "$PWD/homeassistant" "$PWD/custom_components" "$@"
  '';
  ls-lint-nix = pkgs.writeShellScriptBin "ls-lint-nix" ''
    exec statix check "$PWD" "$@"
  '';
  ls-lint = pkgs.writeShellScriptBin "ls-lint" ''
    rc=0
    echo "==> server" && ls-lint-server || rc=1
    echo "==> ui"     && ls-lint-ui     || rc=1
    echo "==> cec"    && ls-lint-cec    || rc=1
    echo "==> ha"     && ls-lint-ha     || rc=1
    echo "==> nix"    && ls-lint-nix    || rc=1
    exit $rc
  '';

  # ── Fix (auto-fix lint issues) ─────────────────────────────────────────── #
  ls-fix-server = pkgs.writeShellScriptBin "ls-fix-server" ''
    cd "$PWD/server" && exec golangci-lint run --fix ./... "$@"
  '';
  # ls-fix-ui: luacheck has no auto-fix; use ls-fmt-ui instead
  ls-fix-cec = pkgs.writeShellScriptBin "ls-fix-cec" ''
    exec ruff check --fix "$PWD/cec" "$@"
  '';
  ls-fix-ha = pkgs.writeShellScriptBin "ls-fix-ha" ''
    exec ruff check --fix "$PWD/homeassistant" "$PWD/custom_components" "$@"
  '';
  ls-fix-nix = pkgs.writeShellScriptBin "ls-fix-nix" ''
    exec statix fix "$PWD" "$@"
  '';
  ls-fix = pkgs.writeShellScriptBin "ls-fix" ''
    rc=0
    echo "==> server" && ls-fix-server || rc=1
    echo "==> ui"     && ls-fmt-ui     || rc=1
    echo "==> cec"    && ls-fix-cec    || rc=1
    echo "==> ha"     && ls-fix-ha     || rc=1
    echo "==> nix"    && ls-fix-nix    || rc=1
    exit $rc
  '';

  # ── Format ────────────────────────────────────────────────────────────── #
  ls-fmt-server = pkgs.writeShellScriptBin "ls-fmt-server" ''
    exec gofmt -w "$PWD/server"
  '';
  ls-fmt-ui = pkgs.writeShellScriptBin "ls-fmt-ui" ''
    exec stylua "$PWD/ui" "$@"
  '';
  ls-fmt-cec = pkgs.writeShellScriptBin "ls-fmt-cec" ''
    exec ruff format "$PWD/cec" "$@"
  '';
  ls-fmt-ha = pkgs.writeShellScriptBin "ls-fmt-ha" ''
    exec ruff format "$PWD/homeassistant" "$PWD/custom_components" "$@"
  '';
  ls-fmt-nix = pkgs.writeShellScriptBin "ls-fmt-nix" ''
    exec alejandra "$PWD" "$@"
  '';
  ls-fmt = pkgs.writeShellScriptBin "ls-fmt" ''
    rc=0
    echo "==> server" && ls-fmt-server || rc=1
    echo "==> ui"     && ls-fmt-ui     || rc=1
    echo "==> cec"    && ls-fmt-cec    || rc=1
    echo "==> ha"     && ls-fmt-ha     || rc=1
    echo "==> nix"    && ls-fmt-nix    || rc=1
    exit $rc
  '';
in
  pkgs.mkShell {
    name = "launchscope-dev";

    packages = with pkgs; [
      # Go — server development.
      go
      gopls
      gotools
      golangci-lint
      delve

      # Lua / LÖVE2D — UI development.
      love
      lua5_4 # gamescope-args.lua and tools
      lua-language-server
      luajitPackages.luacheck
      stylua

      # Python — CEC bridge and Home Assistant integration.
      python3
      ruff

      # Nix — modules and packages.
      alejandra
      statix

      # Runtime — gamescope for nested_gamescope session mode.
      gamescope
      fontconfig # fc-match for font name resolution

      # Fonts.
      devFont

      # Dev scripts.
      ls-ui
      ls-ui-gs
      ls-ui-standalone
      ls-ui-standalone-gs
      ls-dev
      ls-server-test
      ls-ha-test
      ls-lint-server
      ls-lint-ui
      ls-lint-cec
      ls-lint-ha
      ls-lint-nix
      ls-lint
      ls-fmt-server
      ls-fmt-ui
      ls-fmt-cec
      ls-fmt-ha
      ls-fmt-nix
      ls-fmt
      ls-fix-server
      ls-fix-cec
      ls-fix-ha
      ls-fix-nix
      ls-fix
    ];

    env.LAUNCHSCOPE_FONT = devFontName;

    shellHook = ''
      # Re-exec as zsh when launched interactively by `nix develop`.
      # Skip when nix-direnv is sourcing the environment (DIRENV_IN_ENVRC is set).
      if [ -z "$__LAUNCHSCOPE_DEV_SHELL" ] && [ -z "$DIRENV_IN_ENVRC" ]; then
        export __LAUNCHSCOPE_DEV_SHELL=1
        exec ${pkgs.zsh}/bin/zsh
      fi

      echo ""
      echo "  launchscope dev shell"
      echo ""
      echo "  LAUNCHSCOPE_FONT=${devFontName}"
      echo ""
      echo "  UI scripts"
      echo "  ls-ui                nested_direct + daemon     — windowed, connects to launchscoped"
      echo "  ls-ui-gs             nested_gamescope + daemon  — gamescope window, connects to launchscoped"
      echo "  ls-ui-standalone     nested_direct + standalone — windowed, UI manages apps"
      echo "  ls-ui-standalone-gs  nested_gamescope + standalone — gamescope window, UI manages apps"
      echo ""
      echo "  Server scripts"
      echo "  ls-dev               run launchscoped + UI together (server launches UI)"
      echo ""
      echo "  Test scripts"
      echo "  ls-server-test       run Go server test suite (--coverage for HTML report)"
      echo "  ls-ha-test           run Home Assistant integration tests"
      echo ""
      echo "  Lint"
      echo "  ls-lint              lint all packages"
      echo "  ls-lint-server       golangci-lint (Go)"
      echo "  ls-lint-ui           luacheck (Lua)"
      echo "  ls-lint-cec          ruff check (Python)"
      echo "  ls-lint-ha           ruff check (Python)"
      echo "  ls-lint-nix          statix (Nix)"
      echo ""
      echo "  Fix (auto-fix lint issues)"
      echo "  ls-fix               fix all packages"
      echo "  ls-fix-server        golangci-lint --fix (Go)"
      echo "  ls-fix-cec           ruff check --fix (Python)"
      echo "  ls-fix-ha            ruff check --fix (Python)"
      echo "  ls-fix-nix           statix fix (Nix)"
      echo "  (Lua: no auto-fix — use ls-fmt-ui)"
      echo ""
      echo "  Format"
      echo "  ls-fmt               format all packages"
      echo "  ls-fmt-server        gofmt (Go)"
      echo "  ls-fmt-ui            stylua (Lua)"
      echo "  ls-fmt-cec           ruff format (Python)"
      echo "  ls-fmt-ha            ruff format (Python)"
      echo "  ls-fmt-nix           alejandra (Nix)"
      echo ""
      echo "  Build"
      echo "  nix build .#launchscoped"
      echo "  nix build .#launchscope"
      echo ""
    '';
  }
