{ pkgs, ... }:

let
  retroarchWithCores = pkgs.retroarch.override {
    cores = [ pkgs.libretro.mupen64plus ];
  };
in
{
  environment.systemPackages = with pkgs; [
    retroarchWithCores
    vim
    wget
    sudo
    htop
    tmux
    file
    binutils
    git
  ];
}
