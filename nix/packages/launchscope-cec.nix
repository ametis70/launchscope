{
  lib,
  stdenv,
  python3,
  libcec,
  makeWrapper,
}:
# CEC → uinput bridge for Pulse-Eight USB CEC adapters.
# Runs as a system service; exposes a Unix socket at /run/launchscope-cec/cmd.sock
# for receiving commands (activate, standby, set-source, power-on) from launchscoped.
let
  # python-cec: Python bindings for libcec (from PyPI).
  python-cec = python3.pkgs.buildPythonPackage rec {
    pname = "cec";
    version = "0.2.8";
    format = "setuptools";

    src = python3.pkgs.fetchPypi {
      inherit pname version;
      sha256 = "81e59d85dffdd5552b9bec556779e97fb1d6bd120c7320c216c020743a46083a";
    };

    buildInputs = [libcec];
    nativeBuildInputs = [python3.pkgs.setuptools];

    # Point the build at the libcec headers and library.
    preBuild = ''
      export CFLAGS="-I${libcec}/include/libcec"
      export LDFLAGS="-L${libcec}/lib"
    '';
  };

  python = python3.withPackages (p: [p.evdev python-cec]);
in
  stdenv.mkDerivation {
    pname = "launchscope-cec";
    version = "0.1.0";

    src = ../../cec;

    nativeBuildInputs = [makeWrapper];

    dontBuild = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 $src/launchscope-cec.py $out/bin/.launchscope-cec-unwrapped
      makeWrapper ${python}/bin/python3 $out/bin/launchscope-cec \
        --add-flags "$out/bin/.launchscope-cec-unwrapped" \
        --prefix PATH : ${lib.makeBinPath [libcec]}
      runHook postInstall
    '';

    meta = {
      description = "HDMI-CEC to uinput bridge for Pulse-Eight USB adapters";
      mainProgram = "launchscope-cec";
      platforms = lib.platforms.linux;
      license = lib.licenses.agpl3Only;
    };
  }
