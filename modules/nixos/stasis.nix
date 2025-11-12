{
  self,
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
  cfg = config.services.stasis;
in
{
  options = {
    services.stasis = {
      enable = mkEnableOption "Stasis";
      package = mkPackageOption (lib.getAttrFromPath [ "packages" pkgs.system ] self) "stasis" { };
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

        ExecStartPre = "/bin/sh -c 'while [ ! -e /run/user/%U/wayland-0 ]; do sleep 0.1; done'";
      };

      Install = {
        WantedBy = [ "default.target" ];
      };
    };
  };
}
