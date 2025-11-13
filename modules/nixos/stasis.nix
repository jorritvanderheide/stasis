{
  self,
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkPackageOption
    mkIf
    getExe
    ;

  cfg = config.services.stasis;
in
{
  options = {
    services.stasis = {
      enable = mkEnableOption "Stasis";
      package = mkPackageOption { stasis = self.packages.${pkgs.system}.default; } "stasis" { };
    };
  };

  config = mkIf cfg.enable {
    systemd.user.services."stasis" = {
      description = "Stasis Wayland Idle Manager";
      after = [ "graphical-session.target" ];
      wants = [ "graphical-session.target" ];
      wantedBy = [ "default.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${getExe cfg.package}";
        Restart = "always";
        RestartSec = "5";
        Environment = "WAYLAND_DISPLAY=wayland-0";

        # Optional: wait until WAYLAND_DISPLAY exists
        ExecStartPre = "/bin/sh -c 'while [ ! -e /run/user/%U/wayland-0 ]; do sleep 0.1; done'";
      };
    };
  };
}
