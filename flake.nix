{
  description = "Flake for the Stasis NixOS- and Home-Manager modules and development shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { nixpkgs, flake-utils, ... }:
    let

      # Top-level module files
      nixosModuleFile = ./modules/nixos/stasis.nix;
      homeModuleFile = ./modules/home/stasis.nix;

      # Per-system outputs packages and devShell outputs
      perSystem = flake-utils.lib.eachDefaultSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };

          stasisPkg = pkgs.rustPlatform.buildRustPackage {
            pname = "stasis";
            version = "unstable";
            src = ./.;

            # Use the repository Cargo.lock to avoid querying crates.io during the
            # derivation evaluation step.
            cargoLock = {
              lockFile = ./Cargo.lock;
            };

            # Dependencies required at build/runtime
            nativeBuildInputs = [ pkgs.pkg-config ];
            buildInputs = [
              pkgs.openssl
              pkgs.zlib
              pkgs.udev
              pkgs.dbus
              pkgs.libinput
            ];

            # Optionally set RUSTFLAGS or other env vars
            RUSTFLAGS = "-C target-cpu=native";
          };
        in
        {
          packages.stasis = stasisPkg;

          # Developer shell
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
                echo "Entering stasis dev shell — run: cargo build, cargo run, or nix build .#stasis""
              '';
            };
          };

          nixosModules = {
            stasis = import nixosModuleFile {
              inherit pkgs;
              stasis = stasisPkg;
            };
            default = import nixosModuleFile {
              inherit pkgs;
              stasis = stasisPkg;
            };
          };

          homeModules = {
            stasis = import homeModuleFile;
            default = import homeModuleFile;
          };
        }
      );
    in

    # Use the per-system outputs
    perSystem;
}
