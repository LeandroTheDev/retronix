{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    retroarch
    libretro.mupen64plus
    libretro.pcsx2
    vim
    wget
    sudo
    htop
    tmux
    file
    binutils
    git
    libraspberrypi
    xrandr
    drm_info
    nvtopPackages.v3d
    mesa-demos
    alsa-utils
    pulseaudio
    xdotool
    unclutter
    bluez
  ];
}
