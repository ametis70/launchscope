{
  lib,
  stdenv,
  love,
  lua5_4,
  zip,
  makeWrapper,
  gamescope,
  wlopm,
  sdl_gamecontrollerdb,
}:
# LÖVE2D apps are distributed as .love archives (zip files containing Lua
# sources). This derivation:
#   1. Zips ui/ into launchscope.love, injecting gamecontrollerdb.txt from
#      the sdl_gamecontrollerdb nixpkg (not committed to the repo).
#   2. Installs the archive and the gamescope-args helper to $out/share/launchscope/
#   3. Wraps the launch binary in a shell that reads display config and
#      optionally prepends gamescope based on session_mode.
#
# Fonts are NOT bundled. The UI resolves fonts at runtime via fc-match(1).
stdenv.mkDerivation {
  pname = "launchscope";
  version = "0.1.0";

  src = ../../ui;

  nativeBuildInputs = [zip makeWrapper];
  buildInputs = [lua5_4 gamescope wlopm];

  dontBuild = false;

  buildPhase = ''
    runHook preBuild
    pushd $src
    zip -r $TMPDIR/launchscope.love .
    popd
    # Inject the community gamepad mapping database from nixpkgs.
    # The file is excluded from the repo to stay up to date with the package.
    zip -j $TMPDIR/launchscope.love \
      -o assets/gamecontrollerdb.txt \
      ${sdl_gamecontrollerdb}/share/gamecontrollerdb.txt
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm644 $TMPDIR/launchscope.love \
      $out/share/launchscope/launchscope.love

    install -Dm755 $src/tools/gamescope-args.lua \
      $out/share/launchscope/gamescope-args.lua

    # Shell wrapper: evaluates gamescope-args.lua which exports
    # LAUNCHSCOPE_SESSION_MODE and optionally GS_ARGS, then launches
    # love with or without gamescope depending on session_mode.
    # wlopm is added to PATH for idle screen blanking in DRM/gamescope mode.
    makeWrapper ${love}/bin/love $out/bin/launchscope \
      --prefix PATH : ${lib.makeBinPath [wlopm]} \
      --run '
        eval $(${lua5_4}/bin/lua '"$out/share/launchscope/gamescope-args.lua"' 2>/dev/null)
        if [ -n "$GS_ARGS" ]; then
          exec $GS_ARGS -- ${love}/bin/love '"$out/share/launchscope/launchscope.love"' "$@"
        fi
      ' \
      --add-flags "$out/share/launchscope/launchscope.love"

    runHook postInstall
  '';

  meta = {
    description = "Launchscope HTPC launcher — LÖVE2D frontend";
    mainProgram = "launchscope";
    platforms = lib.platforms.linux;
    license = lib.licenses.agpl3Only;
  };
}
