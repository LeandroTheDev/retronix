{ pkgs, lib, ... }:

let
  pkgs-x86 = import pkgs.path {
    system = "x86_64-linux";
    config = pkgs.config;
    # Replace x86_64 bwrap with a shell script that delegates to the native
    # ARM setuid bwrap (/run/wrappers/bin/bwrap).  The Pi kernel does not
    # support unprivileged user namespaces, so the x86_64 bwrap (running
    # under box64 emulation) can never acquire the privileges it needs.
    # box64 cannot exec a shell script as x86_64 ELF, falls back to native
    # ARM exec — which is exactly what we want so the setuid bit takes effect.
    overlays = [(self: super: {
      bubblewrap = pkgs.writeShellScriptBin "bwrap" ''
        exec /run/wrappers/bin/bwrap "$@"
      '';
    })];
  };
in
{
  # binfmt registers x86_64 as plataforma suportada — o Nix pode baixar
  # binários x86_64 do cache e o kernel sabe executá-los via Box64/QEMU.
  boot.binfmt.emulatedSystems = [ "x86_64-linux" ];

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
    box64
    pkgs-x86.wine
    pkgs-x86.umu-launcher
  ];
}
