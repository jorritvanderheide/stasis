{
  description = "Flake for the Stasis NixOS- and Home-Manager modules and development shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        stasis = pkgs.rustPlatform.buildRustPackage {
          pname = "stasis";
          version = "unstable";
          src = ./.;

          cargoLock = ./Cargo.lock;

          nativeBuildInputs = [ pkgs.pkg-config ];
          buildInputs = [
            pkgs.openssl
            pkgs.zlib
            pkgs.udev
            pkgs.dbus
            pkgs.libinput
          ];

          # optional optimization
          RUSTFLAGS = "-C target-cpu=native";
        };
      in
      {
        packages = {
          stasis = stasis;
        };

        defaultPackage = stasis;

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

        nixosModules = {
          stasis = import ./modules/nixos/stasis.nix {
            inherit pkgs;
            stasis = stasis;
          };
          default = import ./modules/nixos/stasis.nix {
            inherit pkgs;
            stasis = stasis;
          };
        };

        homeManagerModules = {
          stasis = import ./modules/home/stasis.nix {
            inherit pkgs;
            stasis = stasis;
          };
          default = import ./modules/home/stasis.nix {
            inherit pkgs;
            stasis = stasis;
          };
        };
      }
    );
}
