{
  description = "Flake for Stasis: builds the binary and provides a home-manager service";

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
        # Pure Nix build using buildRustPackage. This is hermetic and CI-friendly.
        packages.stasis = pkgs.rustPlatform.buildRustPackage {
          pname = "stasis";
          version = "0.1.0";
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

        # NixOS module
        nixosModules = {
          nirinit =
            {
              config,
              pkgs,
              lib,
              ...
            }:
            let
              inherit (lib)
                mkEnableOption
                mkPackageOption
                mkIf
                getExe
                ;
              cfg = config.services.nirinit;
            in
            {
              options = {
                services.stasis = {
                  enable = mkEnableOption "Stasis";
                  package = mkPackageOption self.packages.${pkgs.system} "stasis" { };
                };
              };

              config = mkIf cfg.enable {
                systemd.user.services.stasis = {
                  enable = true;

                  Unit = {
                    Description = "Stasis Wayland Idle Manager";
                    After = [ "graphical-session.target" ];
                    Wants = [ "graphical-session.target" ];
                  };

                  Service = {
                    Type = "simple";
                    ExecStart = "${getExe cfg.package}";
                    Restart = "always";
                    RestartSec = "5";
                    Environment = "WAYLAND_DISPLAY=wayland-0";

                    # Optional: wait until WAYLAND_DISPLAY exists
                    ExecStartPre = "/bin/sh -c 'while [ ! -e /run/user/%U/wayland-0 ]; do sleep 0.1; done'";
                  };

                  Install = {
                    WantedBy = [ "default.target" ];
                  };
                };
              };
            };

          default = self.nixosModules.stasis;
        };

        # Home-manager module
        homeModules = {
          nirinit =
            {
              osConfig,
              pkgs,
              lib,
              ...
            }:
            let
              inherit (lib) mkIf;
              cfg = osConfig.services.stasis;
            in
            {
              config = mkIf cfg.enable {
                xdg.configFile."stasis/config.rune" = {
                  source = (pkgs.formats.rune { }).generate "stasis/config.rune" cfg.settings;
                };
              };

            };

          default = self.homeModules.stasis;
        };

        # Development shell
        devShell = pkgs.mkShell {
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
    );
}
