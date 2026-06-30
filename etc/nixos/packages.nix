{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    vim
    wget
    sudo
    htop
    tmux
    file
    binutils
    git
    retroarch
    libretro.mupen64plus
  ];
}
