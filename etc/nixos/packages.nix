{ pkgs, lib, ... }:

{
  environment.systemPackages = with pkgs; [
    retroarch
    libretro.mupen64plus
    vulkan-loader
    libretro.pcsx-rearmed
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
    wine
    box64
    umu-launcher
  ];
}
