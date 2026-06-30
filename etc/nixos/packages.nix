{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    retroarch
    libretro.parallel-n64
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
