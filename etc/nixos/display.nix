{ pkgs, ... }:

let
  retro_os = pkgs.callPackage ./retro-os.nix {};
in
{
  hardware.graphics.enable = true;

  # cage: Wayland kiosk compositor — boots directly into retro_os Flutter frontend
  services.cage = {
    enable = true;
    user = "admin";
    program = "${retro_os}/bin/retro_os";
    environment.FONTCONFIG_FILE = "/etc/fonts/fonts.conf";
  };

  # Audio
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
}
