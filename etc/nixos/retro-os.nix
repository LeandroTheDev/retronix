{ pkgs, lib, ... }:

pkgs.flutter.buildFlutterApplication {
  pname = "retro_os";
  version = "1.0.0";

  src = lib.cleanSourceWith {
    src = ./retro_os;
    filter = path: type:
      let name = baseNameOf path;
      in name != ".dart_tool" && name != "build";
  };

  pubspecLock = lib.importJSON ./retro_os/pubspec.lock.json;

  nativeBuildInputs = with pkgs; [ pkg-config ];
  buildInputs = with pkgs; [
    gtk3
    glib
    udev
  ];
}
