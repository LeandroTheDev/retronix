{ config, lib, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./display.nix
      ./mdns.nix
      ./packages.nix
      ./raspberrypi.nix
      ./users.nix
    ];

  nix.settings = {
    max-jobs = "auto"; # All Cores
    cores = 0; # All Cores per job
  };

  # Keep CPU at full speed — prevents the throttle-to-375MHz slow motion in RetroArch
  powerManagement.cpuFreqGovernor = "performance";

  # Use the extlinux boot loader. (NixOS wants to enable GRUB by default)
  boot.loader.grub.enable = false;
  # Enables the generation of /boot/extlinux/extlinux.conf
  boot.loader.generic-extlinux-compatible = {
    enable = true;
    configurationLimit = 2; # current + 1 rollback generation
  };
  boot.loader.timeout = 0; # boot immediately, no selection screen

  # Increase CMA pool so the GPU (DRM/KMS) can allocate framebuffers
  #boot.kernelParams = [ "cma=256M" ];

  networking.hostName = "retronix";
  networking.networkmanager.enable = true;
  networking.firewall.enable = false;

  # Time zone.
  time.timeZone = "America/SaoPaulo";

  # Audio — PipeWire with PulseAudio compatibility (pactl/paplay) and ALSA
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # Start PipeWire eagerly on login instead of waiting for socket activation,
  # so audio sinks are ready before the app queries them.
  systemd.user.services.pipewire.wantedBy = [ "default.target" ];
  systemd.user.services.pipewire-pulse.wantedBy = [ "default.target" ];

  # Bluetooth — needed for wireless controllers (e.g. Xbox Series S/X pads).
  hardware.bluetooth.enable = true;

  # xpadneo gives full Xbox One/Series controller support over Bluetooth
  # (correct button mapping, rumble, trigger deadzones) instead of relying
  # on the generic HID gamepad quirks the kernel falls back to otherwise.
  boot.extraModulePackages = [ config.boot.kernelPackages.xpadneo ];
  boot.kernelModules = [ "xpadneo" ];

  # Open SSH
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      KbdInteractiveAuthentication = false;
    };
  };

  # bwrap / pressure-vessel (used by umu-launcher + Proton) requires the
  # ability to create user namespaces.  On standard kernels this sysctl
  # controls the per-user limit; 0 disables them for unprivileged users.
  security.unprivilegedUsernsClone = true;
  boot.kernel.sysctl."user.max_user_namespaces" = 15000;

  # Goodies for administrators (no passwords)
  security.sudo.wheelNeedsPassword = false;
  security.pam.services.su = {
    text = ''
      auth required pam_wheel.so use_uid deny group=nosu
      auth sufficient pam_wheel.so trust use_uid
      auth required pam_unix.so
      account required pam_unix.so
      session required pam_unix.so
    '';
  };
  
  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "26.11"; # Did you read the comment?

}
