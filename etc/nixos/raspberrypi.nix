{ pkgs, ... }:

{
  # Overclock. config.txt lives on the FAT boot partition and isn't exposed
  # via a NixOS option (boot.loader.raspberrypi.firmwareConfig was removed
  # upstream in 24.11), so we patch it on activation — same trick as the
  # HDMI force-hotplug hack in display.nix, but set-or-replace instead of
  # append-only so changing a value here actually takes effect on rebuild.
  # Needs a reboot after `nixos-rebuild switch` — firmware only reads
  # config.txt at boot. Verify with `vcgencmd measure_temp` / `get_throttled`
  # (bit 0x2/0x20000 = currently/previously throttled due to undervoltage or
  # overtemp — back off if you see either after a play session).
  system.activationScripts.rpi-overclock = ''
    [ -f /proc/device-tree/model ] || exit 0
    ${pkgs.gnugrep}/bin/grep -q "Raspberry Pi" /proc/device-tree/model || exit 0

    CFG=/boot/firmware/config.txt
    [ -f "$CFG" ] || CFG=/boot/config.txt
    [ -f "$CFG" ] || exit 0
    set_cfg() {
      if ${pkgs.gnugrep}/bin/grep -q "^$1=" "$CFG"; then
        ${pkgs.gnused}/bin/sed -i "s/^$1=.*/$1=$2/" "$CFG"
      else
        echo "$1=$2" >> "$CFG"
      fi
    }
    set_cfg arm_freq 2000
    set_cfg over_voltage 6
    set_cfg gpu_freq 700
    set_cfg sdram_freq 3200
    set_cfg temp_limit 80
  '';
}
