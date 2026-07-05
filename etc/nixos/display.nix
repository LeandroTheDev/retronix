{ pkgs, ... }:

let
  retro_os = pkgs.callPackage ./retro-os.nix {};
  retro_os_notification = pkgs.callPackage ./retro-os-notification.nix {};

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

  # Minimal openbox config: no decorations on any window, single desktop.
  # Openbox is a stacking WM so overlay windows can float on top of retro_os,
  # unlike matchbox which only ever shows one window at a time.
  openbox_rc = pkgs.writeText "openbox-rc.xml" ''
    <?xml version="1.0" encoding="UTF-8"?>
    <openbox_config xmlns="http://openbox.org/3.4/rc">
      <resistance><strength>10</strength><screen_edge_strength>20</screen_edge_strength></resistance>
      <focus><focusNew>yes</focusNew><followMouse>no</followMouse></focus>
      <placement><policy>Smart</policy></placement>
      <desktops><number>1</number></desktops>
      <keyboard>
        <chainQuitKey>C-g</chainQuitKey>
      </keyboard>
      <applications>
        <application class="*">
          <decor>no</decor>
        </application>
        <application class="retroarch">
          <fullscreen>no</fullscreen>
          <maximized>yes</maximized>
        </application>
      </applications>
    </openbox_config>
  '';

  retro_os_session = pkgs.writeShellScript "retro_os-session" ''
    DISPLAY_MODE_FILE="$HOME/.local/share/retro_os/display_mode"
    if [ -f "$DISPLAY_MODE_FILE" ]; then
      RESOLUTION=$(${pkgs.gnused}/bin/sed -n '1p' "$DISPLAY_MODE_FILE")
      RATE=$(${pkgs.gnused}/bin/sed -n '2p' "$DISPLAY_MODE_FILE")
      XRANDR_QUERY=$(${pkgs.xrandr}/bin/xrandr --query)
      # Pick whichever output is currently connected — doesn't assume HDMI-1.
      OUTPUT=$(echo "$XRANDR_QUERY" | ${pkgs.gnugrep}/bin/grep ' connected' | ${pkgs.coreutils}/bin/cut -d' ' -f1 | ${pkgs.coreutils}/bin/head -n1)

      # sed -n ".../,/^[^ ]/p" extracts only the block for that output (from
      # its "connected" header line up to the next non-indented line), so we
      # don't accidentally match a resolution that belongs to a different output.
      if echo "$XRANDR_QUERY" \
          | ${pkgs.gnused}/bin/sed -n "/^$OUTPUT connected/,/^[^ ]/p" \
          | ${pkgs.gnugrep}/bin/grep -qE "^ +$RESOLUTION( |$)"; then
        ${pkgs.xrandr}/bin/xrandr --output "$OUTPUT" --mode "$RESOLUTION" --rate "$RATE"
      fi
    fi

    # Disable the X11 screen saver and DPMS (monitor power-off) — this is a
    # kiosk that never idles; letting the screen blank would require a keyboard
    # event to wake it, which gamepads don't send to X.
    ${pkgs.xset}/bin/xset s off -dpms
    # There's no real mouse on this device (gamepad-only) — idle 0 hides the
    # cursor immediately instead of waiting for it to sit idle first, and
    # since nothing ever moves it, it stays hidden for good.
    ${pkgs.unclutter}/bin/unclutter -idle 0 -root &
    ${pkgs.openbox}/bin/openbox --config-file ${openbox_rc} &
    # retro_os_notification binary must be on PATH so retro_os can spawn it
    # as a subprocess to show system notifications as overlay windows.
    export PATH="${retro_os_notification}/bin:$PATH"
    exec ${retro_os}/bin/retro_os
  '';
in
{
  hardware.graphics = {
    enable = true;
    # mesa provides the open-source OpenGL/Vulkan drivers; without it the RPi's
    # modesetting driver falls back to software rendering and Flutter's GL
    # surface fails to initialize.
    extraPackages = with pkgs; [ mesa ];
  };

  # Xorg + openbox: minimal X11 stack — boots directly into retro_os Flutter
  # frontend. Openbox replaces matchbox because we need overlay windows to
  # float on top of retro_os; matchbox only shows one window at a time.
  # Switched from cage/Wayland because Flutter's GTK/GDK embedder hits a
  # known EGL_BAD_SURFACE bug in eglSwapInterval under the wlroots
  # (GDK-Wayland) backend; GDK's X11/GLX path doesn't have this issue.
  services.xserver = {
    enable = true;
    # modesetting is the generic KMS/DRM driver; works on RPi with mesa and
    # doesn't require the proprietary broadcom driver that was dropped upstream.
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

  # Force HDMI output even when no display is detected at boot (TV off).
  # Without this the RPi firmware disables HDMI entirely, and X11 comes up
  # with no connected output — the screen never appears when the TV is later
  # turned on. hdmi_drive=2 keeps HDMI mode (with audio) instead of DVI.
  system.activationScripts.rpi-hdmi-force = ''
    # NixOS 24.05+ mounts the FAT boot partition at /boot/firmware; older
    # images use /boot directly. Try both so the script works across versions.
    CFG=/boot/firmware/config.txt
    [ -f "$CFG" ] || CFG=/boot/config.txt
    [ -f "$CFG" ] || exit 0
    grep -q 'hdmi_force_hotplug' "$CFG" || echo 'hdmi_force_hotplug=1' >> "$CFG"
    grep -q 'hdmi_drive'         "$CFG" || echo 'hdmi_drive=2'         >> "$CFG"
  '';

  # Re-run xrandr --auto when the TV is hotplugged after boot (TV was off
  # during boot). The modesetting driver fires a DRM change event on hotplug;
  # xrandr --auto enables the newly-detected output at its preferred resolution.
  services.udev.extraRules = ''
    ACTION=="change", SUBSYSTEM=="drm", RUN+="${pkgs.bash}/bin/sh -c 'DISPLAY=:0 XAUTHORITY=/home/admin/.Xauthority ${pkgs.xrandr}/bin/xrandr --auto'"
  '';

  # Watchdog that polls xrandr every 5 s and re-enables the HDMI output when
  # the TV is turned on after boot. The udev rule above fires on hotplug events
  # but can miss them (udev environment is restricted, timing is tight). This
  # service is the reliable fallback: it simply checks whether any output has
  # an active mode and runs xrandr --auto when none does.
  systemd.services.hdmi-watchdog = {
    description = "HDMI display reconnect watchdog";
    after = [ "display-manager.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "admin";
      # DISPLAY and XAUTHORITY must be set explicitly because this is a system
      # service (not a user session), so it has no access to the session bus or
      # the ~/.Xauthority cookie that X11 uses for client authentication.
      Environment = [ "DISPLAY=:0" "XAUTHORITY=/home/admin/.Xauthority" ];
      ExecStart = pkgs.writeShellScript "hdmi-watchdog" ''
        # Wait for the X server to become available before entering the loop.
        until ${pkgs.xrandr}/bin/xrandr --query &>/dev/null; do
          sleep 2
        done
        while true; do
          sleep 5
          # An active output has a resolution token like 1920x1080+0+0 on the
          # "connected" line.  No such token → TV is connected but X has no
          # active mode set (boot-with-TV-off scenario).
          ACTIVE=$(${pkgs.xrandr}/bin/xrandr --query 2>/dev/null \
            | ${pkgs.gnugrep}/bin/grep ' connected' \
            | ${pkgs.gnugrep}/bin/grep -E '[0-9]+x[0-9]+\+[0-9]+\+[0-9]+')
          if [ -z "$ACTIVE" ]; then
            ${pkgs.xrandr}/bin/xrandr --auto
            # Give the display time to negotiate EDID before the next check.
            sleep 3
          fi
        done
      '';
      # Restart the watchdog if it crashes (e.g. X server restarted and the
      # XAUTHORITY cookie changed — the loop will re-sync on the next try).
      Restart = "always";
      RestartSec = "5s";
    };
  };

  # Audio
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
}
