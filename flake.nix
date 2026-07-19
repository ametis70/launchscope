{
  description = "Launchscope — lightweight HTPC launcher for Linux";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
    ...
  }: let
    linuxSystems = [
      "x86_64-linux"
      "aarch64-linux"
    ];

    forLinux = f:
      nixpkgs.lib.genAttrs linuxSystems (
        system:
          f {
            pkgs = import nixpkgs {inherit system;};
            inherit system;
          }
      );

    makePackages = pkgs: {
      launchscoped = pkgs.callPackage ./nix/packages/launchscoped.nix {};
      launchscope = pkgs.callPackage ./nix/packages/launchscope.nix {};
      launchscope-cec = pkgs.callPackage ./nix/packages/launchscope-cec.nix {};
    };
  in {
    packages = forLinux (
      {pkgs, ...}:
        (makePackages pkgs)
        // {
          default = (makePackages pkgs).launchscoped;
        }
    );

    devShells = forLinux (
      {pkgs, ...}: {
        default = import ./nix/dev/shell.nix {inherit pkgs;};
      }
    );

    nixosModules.default = import ./nix/modules/nixos.nix self;

    homeManagerModules.default = import ./nix/modules/home-manager.nix self;
  };
}
