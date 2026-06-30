{ config, pkgs, ... }:
{
  services.resolved = {
    enable = true;
    settings = {
      Resolve = {
        MulticastDNS = "resolve";
      };
    };
  };

  networking.networkmanager = {
    enable = true;
    connectionConfig = {
      "connection.mdns" = 2;
    };
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;

    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };
}