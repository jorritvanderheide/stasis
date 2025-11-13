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

        stasis = pkgs.rustPlatform.buildRustPackage {
          pname = "stasis";
          version = "unstable";
          src = ./.;

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
          # default = self.packages.${system}.stasis;
        };

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
      nixosModules.stasis =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        import ./modules/nixos/stasis.nix {
          inherit
            config
            lib
            ;
          pkgs = self.packages.${pkgs.system}.default;
        };

      homeModules.stasis = import ./modules/home/stasis.nix;
    };
}
