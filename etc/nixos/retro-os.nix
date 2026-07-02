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
    # audioplayers (boot jingle) uses GStreamer on Linux for decoding/playback.
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    # gstreamer-1.0.pc pulls in libunwind (Requires.private) — without it in
    # buildInputs, pkg-config can't resolve gstreamer-1.0 in the sandbox.
    libunwind
  ];
}
