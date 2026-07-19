{
  lib,
  buildGoModule,
  ...
}:
buildGoModule {
  pname = "launchscoped";
  version = "0.1.0";

  # The server/ subdirectory is the Go module root.
  src = ../../server;

  vendorHash = "sha256-0Qxw+MUYVgzgWB8vi3HBYtVXSq/btfh4ZfV/m1chNrA=";

  subPackages = ["cmd/launchscoped"];

  meta = {
    description = "Launchscope HTPC launcher — server daemon";
    mainProgram = "launchscoped";
    platforms = lib.platforms.linux;
    license = lib.licenses.agpl3Only;
  };
}
