# RetroOS

Flutter-based frontend for the retro operating system, designed to run on ARM devices with NixOS. Provides a gamepad-navigable interface for selecting and launching games via RetroArch.

## Features

- Console and game selection navigable by gamepad or keyboard
- Nintendo 64 support via the `mupen64plus` core in RetroArch
- Per-console graphics settings (resolution, MSAA, texture filtering, frame duplication)
- Settings menu accessible via the Start button
- System shutdown screen

## Controls

| Button (gamepad) | Keyboard | Action |
|-----------------|---------|------|
| D-Pad / Analog | Arrow keys | Navigate |
| A | Enter | Confirm |
| B | Escape / Backspace | Back |
| Start | F1 | Open settings |

## File structure

Console and game files are located at:

**Linux/NixOS:**
```
~/.local/share/retro_os/Consoles/
└── Nintendo 64/
    ├── console_image.png
    └── Games/
        └── <Game Name>/
            ├── game_image.png
            └── Game/
                └── rom.z64
```

**Windows:**
```
%APPDATA%\retro_os\Consoles\
```

## Settings

Saved at `~/.local/share/retro_os/settings.json`. N64 graphics settings are applied to `~/.config/retroarch/config/Mupen64Plus-Next/Mupen64Plus-Next.opt` before each game starts.

## Build (NixOS)

```bash
nixos-rebuild switch
```

The app is built automatically via `retro-os.nix` using `buildFlutterApplication`. `pubspec.lock.json` must be kept in sync with `pubspec.lock`:

```bash
flutter pub get
dart run tool/lock_to_json.dart
```

## Dependencies

| Package | Use |
|--------|-----|
| `gamepads` | Gamepad event reading |
| `flutter_svg` | SVG logo rendering |
