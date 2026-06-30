{ config, lib, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./display.nix
      ./mdns.nix
      ./packages.nix
      ./users.nix
    ];

  nix.settings = {
    max-jobs = "auto"; # All Cores
    cores = 0; # All Cores per job
  };

  # Use the extlinux boot loader. (NixOS wants to enable GRUB by default)
  boot.loader.grub.enable = false;
  # Enables the generation of /boot/extlinux/extlinux.conf
  boot.loader.generic-extlinux-compatible.enable = true;

  networking.hostName = "dont_forget_to_change_the_machine_name_here_alright_interrogation_pontuation";
  networking.networkmanager.enable = true;
  networking.firewall.enable = false;

  # Time zone.
  time.timeZone = "America/SaoPaulo";

  # Open SSH
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      KbdInteractiveAuthentication = false;
    };
  };

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
