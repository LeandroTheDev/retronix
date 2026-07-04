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

  gitHashes = {
    window_manager = "sha256-MP+X30PZLfFbOgtXpDjYnN8uinFsTKCcfJGZuKIJFqU=";
  };

  nativeBuildInputs = with pkgs; [ pkg-config makeWrapper ];
  buildInputs = with pkgs; [
    gtk3
    glib
    udev
    # audioplayers uses GStreamer on Linux for decoding/playback.
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    # gstreamer-1.0.pc pulls in libunwind (Requires.private) — without it in
    # buildInputs, pkg-config can't resolve gstreamer-1.0 in the sandbox.
    libunwind
    # gstreamer-audio-1.0.pc requires orc-0.4 the same way.
    orc
  ];

  # GStreamer discovers plugins via GST_PLUGIN_SYSTEM_PATH_1_0 at runtime —
  # buildInputs alone is not enough because plugins live in the Nix store, not
  # in the standard /usr/lib/gstreamer-1.0 that the scanner checks by default.
  postFixup = with pkgs.gst_all_1; ''
    wrapProgram $out/bin/retro_os \
      --set GST_PLUGIN_SYSTEM_PATH_1_0 "${lib.makeSearchPathOutput "lib" "lib/gstreamer-1.0" [
        gstreamer
        gst-plugins-base
        gst-plugins-good
      ]}"
  '';
}
