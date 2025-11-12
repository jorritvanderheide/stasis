{
  description = "Flake for the Stasis NixOS- and Home-Manager modules and development shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    let
      # Top-level module files
      nixosModuleFile = ./modules/nixos/stasis.nix;
      homeModuleFile  = ./modules/home/stasis.nix;

      # Helper function to build stasis from a pkgs set
      mkStasis = pkgs: pkgs.rustPlatform.buildRustPackage {
        pname = "stasis";
        version = "unstable";
        src = ./.;
        cargoLock = { lockFile = ./Cargo.lock; };
        nativeBuildInputs = [ pkgs.pkg-config ];
        buildInputs = [
          pkgs.openssl
          pkgs.zlib
          pkgs.udev
          pkgs.dbus
          pkgs.libinput
        ];
        RUSTFLAGS = "-C target-cpu=native";
      };

      # Per-system outputs
      perSystem = flake-utils.lib.eachDefaultSystem (system:
        let
          pkgs = import nixpkgs { inherit system; };
          stasis = mkStasis pkgs;
        in
        {
          packages.stasis = stasis;
          defaultPackage = stasis;

          devShells.default = pkgs.mkShell {
            name = "stasis-devshell";
            buildInputs = [
              pkgs.rustc
              pkgs.cargo
              pkgs.openssl
              pkgs.pkg-config
              pkgs.git
              pkgs.zlib
            ];
            RUSTFLAGS = "-C target-cpu=native";
            shellHook = ''
              echo "Entering stasis dev shell — run: cargo build, cargo run, or nix build .#stasis"
            '';
          };

          # Pass the built package to the module so it can reference it
          nixosModules.stasis = import nixosModuleFile {
            inherit pkgs stasis;
          };

          homeManagerModules.stasis = import homeModuleFile {
            inherit pkgs stasis;
          };
        }
      );
    in

    # Merge per-system outputs with top-level module exports
    perSystem;
}
