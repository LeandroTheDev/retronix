# Retronix

A NixOS configuration that turns an aarch64 device (Raspberry Pi 4/5) into a dedicated retro gaming console, featuring a custom Flutter graphical frontend, RetroArch emulation, and a local achievement system.

## Overview

Retronix assembles several components into a reproducible, kiosk-style system:

- **retro_os** — Flutter desktop app that serves as the game launcher and UI
- **retro_os_notification** — lightweight Flutter overlay window for in-game notifications
- **RetroArch + mupen64plus** — N64 emulation backend
- **OpenBox** — minimal window manager (X11, chosen for Flutter EGL compatibility)
- **LightDM** — display manager with auto-login into a custom kiosk session
- **PipeWire** — audio server with PulseAudio and ALSA compatibility

## Features

- Kiosk mode: auto-login, hidden cursor, no screensaver, no window decorations
- Local achievement system — RetroAchievements-style, account-free, polling RetroArch via UDP
- Smart display management — persists user resolution, handles TV hotplug at boot
- Bluetooth game controller support (Xbox Series S/X via xpadneo)
- Raspberry Pi overclocking (CPU 2000 MHz, GPU 700 MHz, RAM 3200 MHz)
- mDNS network discovery (`retronix.local`)
- SSH remote management (key-based only)

## Project Structure

```
etc/nixos/
├── configuration.nix          # Main entry point, imports all modules
├── hardware-configuration.nix # Generated hardware config (aarch64)
├── display.nix                # X11, OpenBox, LightDM, HDMI watchdog
├── packages.nix               # System packages (RetroArch, tools, drivers)
├── raspberrypi.nix            # RPi overclocking and firmware settings
├── users.nix                  # User setup and home directory seeding
├── mdns.nix                   # Avahi/mDNS network discovery
├── retro-os.nix               # Nix build definition for retro_os
├── retro-os-notification.nix  # Nix build definition for notification app
├── home/                      # Home directory templates (/etc/skel/)
│   └── .config/
│       ├── retro_os/          # Achievement JSON examples
│       └── retroarch/         # RetroArch config and controller mappings
├── retro_os/                  # Flutter frontend source
└── retro_os_notification/     # Flutter notification overlay source
```

## Runtime Flow

```
Boot
 └── LightDM auto-login (admin)
      └── X server + retro_os_session script
           ├── Apply saved display resolution (xrandr)
           ├── Disable screensaver/DPMS
           ├── Hide cursor (unclutter)
           └── OpenBox → exec retro_os (Flutter)
                └── User launches game
                     └── RetroArch [ROM path]
                          └── Achievement system polls RAM via UDP
                               └── retro_os_notification shows overlay
```

## Requirements

- Raspberry Pi 4 or 5 (aarch64-linux)
- NixOS installed on the device
- Active cooling recommended (overclocking enabled by default)

## Deployment

Copy the `etc/nixos/` contents to `/etc/nixos/` on the target device, then:

```bash
sudo nixos-rebuild switch
sudo reboot
```

The activation scripts will:
- Write overclock settings to `/boot/firmware/config.txt`
- Force HDMI hotplug configuration
- Seed `/home/admin/.config/` with default configs

> **Note:** config.txt changes require a reboot to take effect.

## Achievement System

Game achievements are defined in JSON files alongside the ROM:

```
Consoles/Nintendo 64/Games/[GameName]/game_achievements.json
```

Progress is stored in:

```
~/.local/share/retro_os/achievements/progress/[console]/[game].json
```

The achievement engine reads N64 RAM by sending `READ_CORE_RAM` commands to RetroArch's network command interface (UDP port 55355) and evaluates memory conditions every 500 ms.

## Audio

After modifying Flutter app dependencies, regenerate the lock JSON used by the Nix build:

```bash
dart tool/lock_to_json.dart
```
