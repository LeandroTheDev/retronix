{ pkgs, lib, ... }:

let
  fontsConf = pkgs.makeFontsConf { fontDirectories = [ pkgs.noto-fonts ]; };
in
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

  nativeBuildInputs = with pkgs; [ pkg-config makeWrapper ];
  buildInputs = with pkgs; [
    gtk3
    glib
    udev
  ];

  postInstall = ''
    wrapProgram $out/bin/retro_os \
      --set FONTCONFIG_FILE ${fontsConf}
  '';
}
