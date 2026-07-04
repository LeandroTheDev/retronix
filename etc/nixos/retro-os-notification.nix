{ pkgs, lib, ... }:

pkgs.flutter.buildFlutterApplication {
  pname = "retro_os_notification";
  version = "1.0.0";

  src = lib.cleanSourceWith {
    src = ./retro_os_notification;
    filter = path: type:
      let name = baseNameOf path;
      in name != ".dart_tool" && name != "build";
  };

  pubspecLock = lib.importJSON ./retro_os_notification/pubspec.lock.json;

  nativeBuildInputs = with pkgs; [ pkg-config ];
  buildInputs = with pkgs; [
    gtk3
    glib
    gtk-layer-shell
  ];
}
