{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    retroarch
    libretro.mupen64plus
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
