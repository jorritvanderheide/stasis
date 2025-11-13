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
      in
      {
        packages = {
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
          };

          default = self.packages.${system}.stasis;
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
          self,
          config,
          pkgs,
          lib,
          ...
        }:
        import ./modules/nixos/stasis.nix {
          inherit
            config
            pkgs
            lib
            ;
          stasisPackage = self.packages.${pkgs.system}.stasis;
        };

      homeModules.stasis = import ./modules/home/stasis.nix;
    };
}
