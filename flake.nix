{
  description = "Flake for the Stasis NixOS- and Home-Manager modules and development shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Pure Nix build using buildRustPackage. This is hermetic and CI-friendly.
        stasis = pkgs.rustPlatform.buildRustPackage {
          pname = "stasis";
          version = "0.6.1";
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

          meta = with pkgs.lib; {
            description = "A modern Wayland idle manager that knows when to step back";
            homepage = "https://github.com/saltnpepper97/stasis";
            license = licenses.mit;
            mainProgram = "stasis";
          };
        };
      in
      {
        packages = {
          stasis = stasis;
          default = stasis;
        };

        # Developer shell: rustc, cargo, openssl, pkg-config and git
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

      }
    )
    // {
      # NixOS module for running the service
      nixosModules.stasis =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        import ./modules/nixos/stasis.nix {
          inherit
            self
            config
            lib
            pkgs
            ;
        };

      # Home-manager module for configuration
      homeModules.stasis = import ./modules/home/stasis.nix;
    };
}
