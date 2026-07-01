{ pkgs, ... }:

let
  mupen64plus-gles = pkgs.libretro.mupen64plus.overrideAttrs (old: {
    makeFlags = (old.makeFlags or []) ++ [ "HAVE_OPENGLES=1" "HAVE_OPENGLES3=1" ];
  });
in
{
  environment.systemPackages = with pkgs; [
    retroarch
    mupen64plus-gles
    vim
    wget
    sudo
    htop
    tmux
    file
    binutils
    git
    libraspberrypi
  ];
}
