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
}
