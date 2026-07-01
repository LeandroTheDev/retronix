{ pkgs, ... }:

let
  retro_os = pkgs.callPackage ./retro-os.nix {};

  # The monitor's EDID-preferred mode is 3840x2160@30, but we want 1080p60.
  # NOTE: verify the output name with `xrandr --query` on first boot — RandR
  # names connectors like "HDMI-2" rather than wlroots' "HDMI-A-2".
  retro_os_session = pkgs.writeShellScript "retro_os-session" ''
    export FONTCONFIG_FILE=/etc/fonts/fonts.conf
    ${pkgs.xrandr}/bin/xrandr --output HDMI-2 --mode 1920x1080 --rate 60 >> /tmp/retro_os.log 2>&1
    ${pkgs.matchbox}/bin/matchbox-window-manager &
    exec ${retro_os}/bin/retro_os
  '';
in
{
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [ mesa ];
  };

  # Xorg + matchbox: minimal X11 kiosk stack — boots directly into retro_os
  # Flutter frontend. Switched from cage/Wayland because Flutter's GTK/GDK
  # embedder hits a known EGL_BAD_SURFACE bug in eglSwapInterval under the
  # wlroots (GDK-Wayland) backend; GDK's X11/GLX path doesn't have this issue.
  services.xserver = {
    enable = true;
    videoDrivers = [ "modesetting" ];
    windowManager.session = [{
      name = "retro-os-kiosk";
      start = ''
        exec ${retro_os_session}
      '';
    }];
  };

  services.displayManager = {
    defaultSession = "none+retro-os-kiosk";
    autoLogin = {
      enable = true;
      user = "admin";
    };
  };
  # lightdm hasn't been migrated to services.displayManager.* yet in this
  # nixpkgs revision (unlike gdm/sddm/lemurs) — it still lives under xserver.
  services.xserver.displayManager.lightdm.enable = true;

  # Audio
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
}
