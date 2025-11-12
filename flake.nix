{
  description = "Flake for the Stasis NixOS- and Home-Manager modules and development shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    let
      # Top-level module files (keeps modules in separate locations)
      nixosModuleFile = ./modules/nixos/stasis.nix;
      homeModuleFile  = ./modules/home/stasis.nix;

      # Per-system outputs: packages, devShells, etc.
      perSystem = flake-utils.lib.eachDefaultSystem (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          packages = {
            stasis = pkgs.rustPlatform.buildRustPackage {
              pname = "stasis";
              version = "0.1.0";
              src = ./.;

              # Use the repository Cargo.lock to avoid querying crates.io during the
              # derivation evaluation step.
              cargoLock = {
                lockFile = ./Cargo.lock;
              };

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
          };

          devShells = {
            default = pkgs.mkShell {
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
          };
        }
      );
    in

    # Merge per-system outputs with top-level module exports
    (perSystem // {
      nixosModules = {
        stasis = import nixosModuleFile;
        default = import nixosModuleFile;
      };

      homeModules = {
        stasis = import homeModuleFile;
        default = import homeModuleFile;
      };
    });
}
