{ pkgs, ... }:

let
  retro_os = pkgs.callPackage ./retro-os.nix {};

  # Output name isn't hardcoded — detected below, since which HDMI port
  # reports as connected depends on the cable/port actually in use.
  #
  # retro_os writes the user's chosen resolution to display_mode (line 1 =
  # resolution, line 2 = rate) whenever they change it in System Settings, so
  # it's applied here on every boot before the app even starts — no need for
  # Flutter to re-apply it itself after launch. If the file doesn't exist yet
  # (fresh install, never touched the setting), we don't call xrandr at all —
  # Xorg's own EDID-preferred mode is the fallback.
  #
  # HDMI-1/HDMI-2 names are tied to the physical port, not to whatever
  # monitor is plugged in — but the saved mode itself might not be: if the
  # user picked 3840x2160 with a 4K TV and later swaps in a 1080p-only
  # display (same port or a different one), that mode won't be in the new
  # display's EDID and xrandr would just fail. So we only apply the saved
  # mode if the currently connected output actually advertises it; otherwise
  # we skip it and fall back to Xorg's default, same as a missing file.
  retro_os_session = pkgs.writeShellScript "retro_os-session" ''
    export FONTCONFIG_FILE=/etc/fonts/fonts.conf

    DISPLAY_MODE_FILE="$HOME/.local/share/retro_os/display_mode"
    if [ -f "$DISPLAY_MODE_FILE" ]; then
      RESOLUTION=$(${pkgs.gnused}/bin/sed -n '1p' "$DISPLAY_MODE_FILE")
      RATE=$(${pkgs.gnused}/bin/sed -n '2p' "$DISPLAY_MODE_FILE")
      XRANDR_QUERY=$(${pkgs.xrandr}/bin/xrandr --query)
      OUTPUT=$(echo "$XRANDR_QUERY" | ${pkgs.gnugrep}/bin/grep ' connected' | ${pkgs.coreutils}/bin/cut -d' ' -f1 | ${pkgs.coreutils}/bin/head -n1)

      if echo "$XRANDR_QUERY" \
          | ${pkgs.gnused}/bin/sed -n "/^$OUTPUT connected/,/^[^ ]/p" \
          | ${pkgs.gnugrep}/bin/grep -qE "^ +$RESOLUTION( |$)"; then
        ${pkgs.xrandr}/bin/xrandr --output "$OUTPUT" --mode "$RESOLUTION" --rate "$RATE" >> /tmp/retro_os.log 2>&1
      else
        echo "[retro_os-session] saved mode $RESOLUTION@$RATE not supported by $OUTPUT, using Xorg default" >> /tmp/retro_os.log
      fi
    fi

    ${pkgs.xset}/bin/xset s off -dpms
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

  # Audio — raw ALSA without PipeWire middleware for lowest latency
  hardware.alsa.enable = true;
}
