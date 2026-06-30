{ pkgs, ... }:

{
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" "video" "audio" "input" ];
    packages = with pkgs; [
      tree
    ];
  };
}
