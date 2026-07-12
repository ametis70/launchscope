{
  description = "Launchscope — lightweight HTPC launcher for Linux";

  inputs = {
    nixpkgs.url     = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    let
      linuxSystems = [ "x86_64-linux" "aarch64-linux" ];

      forLinux = f: nixpkgs.lib.genAttrs linuxSystems (system: f {
        pkgs = import nixpkgs { inherit system; };
        inherit system;
      });

      # Build both packages for a given pkgs instance.
      # Used both in the packages output and inside the modules.
      makePackages = pkgs: {
        launchscoped = pkgs.callPackage ./nix/packages/launchscoped.nix { };
        launchscope  = pkgs.callPackage ./nix/packages/launchscope.nix  { };
        cec-uinput   = pkgs.callPackage ./nix/packages/cec-uinput.nix   { };
      };

    in
    {
      # ------------------------------------------------------------------ #
      # Packages                                                             #
      # ------------------------------------------------------------------ #
      packages = forLinux ({ pkgs, ... }: (makePackages pkgs) // {
        default = (makePackages pkgs).launchscoped;
      });

      # ------------------------------------------------------------------ #
      # Development shell                                                    #
      # ------------------------------------------------------------------ #
      devShells = forLinux ({ pkgs, ... }: {
        default = import ./nix/dev/shell.nix { inherit pkgs; };
      });

      # ------------------------------------------------------------------ #
      # NixOS module                                                         #
      # ------------------------------------------------------------------ #
      # The module is a curried function: `self: { config, lib, pkgs, ... }`.
      # Passing `self` here bakes the launchscope flake reference in so the
      # module can resolve self.packages.${pkgs.system} without requiring
      # the user to apply any overlay or pass specialArgs.
      #
      # Usage:
      #   imports = [ inputs.launchscope.nixosModules.default ];
      #   services.launchscope = { enable = true; user = "htpc"; ... };
      #
      nixosModules.default = import ./nix/modules/nixos.nix self;

      # ------------------------------------------------------------------ #
      # Home Manager module                                                  #
      # ------------------------------------------------------------------ #
      # Same curried pattern — self is baked in, the result is a standard
      # module function { config, lib, pkgs, ... }.
      #
      # Usage:
      #   imports = [ inputs.launchscope.homeManagerModules.default ];
      #   programs.launchscope = { enable = true; settings = { ... }; };
      #
      homeManagerModules.default = import ./nix/modules/home-manager.nix self;
    };
}
