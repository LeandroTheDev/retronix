import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'debug_logger.dart';

const _ps1CoreCandidates = [
  '/run/current-system/sw/lib/retroarch/cores/pcsx_rearmed_libretro.so',  // NixOS
  '/usr/lib/libretro/pcsx_rearmed_libretro.so',                           // Arch Linux
  '/usr/share/libretro/cores/pcsx_rearmed_libretro.so',                   // Debian/Ubuntu
];

const _ps2CoreCandidates = [
  '/run/current-system/sw/lib/retroarch/cores/play_libretro.so',  // NixOS
  '/usr/lib/libretro/play_libretro.so',                           // Arch Linux
  '/usr/share/libretro/cores/play_libretro.so',                   // Debian/Ubuntu
];

const _n64CoreCandidates = [
  '/run/current-system/sw/lib/retroarch/cores/mupen64plus_next_libretro.so', // NixOS
  '/usr/lib/libretro/mupen64plus_next_libretro.so',                          // Arch Linux
  '/usr/share/libretro/cores/mupen64plus_next_libretro.so',                  // Debian/Ubuntu
];

// Resolution: user key → [16:9 value, 4:3 value]
const _resolutionMap = {
  'native':  ['640x360',   '640x480'],
  'hd':      ['1280x720',  '1280x960'],
  'fullhd':  ['1920x1080', '1920x1440'],
  '4k':      ['3840x2160', '3840x2880'],
};

class SettingsService {
  SettingsService._();
  static final instance = SettingsService._();

  Map<String, dynamic> _data = {};
  bool _loaded = false;

  String _settingsPath() {
    if (Platform.isLinux) {
      final xdgDataHome = Platform.environment['XDG_DATA_HOME'] ??
          '${Platform.environment['HOME']}/.local/share';
      return '$xdgDataHome/retro_os/settings.json';
    } else if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ??
          '${Platform.environment['USERPROFILE']}\\AppData\\Roaming';
      return '$appData\\retro_os\\settings.json';
    }
    return '${File(Platform.resolvedExecutable).parent.path}/settings.json';
  }

  String _optFilePath() {
    if (Platform.isLinux) {
      return '${Platform.environment['HOME']}/.config/retroarch/config/Mupen64Plus-Next/Mupen64Plus-Next.opt';
    } else if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ??
          '${Platform.environment['USERPROFILE']}\\AppData\\Roaming';
      return '$appData\\RetroArch\\config\\Mupen64Plus-Next\\Mupen64Plus-Next.opt';
    }
    return '${File(Platform.resolvedExecutable).parent.path}/Mupen64Plus-Next.opt';
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final file = File(_settingsPath());
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        _data = json.decode(content) as Map<String, dynamic>;
        DebugLogger.log('[SettingsService] loaded: $_data');
      } catch (e) {
        DebugLogger.log('[SettingsService] failed to parse settings: $e');
        _data = {};
      }
    }
    _loaded = true;
  }

  Future<void> _save() async {
    final file = File(_settingsPath());
    await file.parent.create(recursive: true);
    await file.writeAsString(json.encode(_data));
    DebugLogger.log('[SettingsService] saved: $_data');
  }

  // ── Core path ─────────────────────────────────────────────────────────────

  Future<String> n64CorePath() async {
    await _ensureLoaded();
    if (_data['n64_core_path'] is String) return _data['n64_core_path'] as String;
    for (final candidate in _n64CoreCandidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return _n64CoreCandidates.first;
  }

  Future<void> setN64CorePath(String path) async {
    await _ensureLoaded();
    _data['n64_core_path'] = path;
    await _save();
  }

  // ── Graphics ──────────────────────────────────────────────────────────────

  // n64_resolution: 'native' | 'hd' | 'fullhd' | '4k'
  Future<String> n64Resolution() async {
    await _ensureLoaded();
    return (_data['n64_resolution'] as String?) ?? 'native';
  }

  Future<void> setN64Resolution(String value) async {
    await _ensureLoaded();
    _data['n64_resolution'] = value;
    await _save();
  }

  // n64_msaa: '0' | '2' | '4' | '8'
  Future<String> n64Msaa() async {
    await _ensureLoaded();
    return (_data['n64_msaa'] as String?) ?? '0';
  }

  Future<void> setN64Msaa(String value) async {
    await _ensureLoaded();
    _data['n64_msaa'] = value;
    await _save();
  }

  // n64_texture_filter: 'nearest' | 'linear'
  Future<String> n64TextureFilter() async {
    await _ensureLoaded();
    return (_data['n64_texture_filter'] as String?) ?? 'nearest';
  }

  Future<void> setN64TextureFilter(String value) async {
    await _ensureLoaded();
    _data['n64_texture_filter'] = value;
    await _save();
  }

  // n64_frame_dupes: 'false' | 'true'
  Future<String> n64FrameDupes() async {
    await _ensureLoaded();
    return (_data['n64_frame_dupes'] as String?) ?? 'true';
  }

  Future<void> setN64FrameDupes(String value) async {
    await _ensureLoaded();
    _data['n64_frame_dupes'] = value;
    await _save();
  }

  // n64_aspect: '4:3' | '16:9' | '16:9 adjusted'
  Future<String> n64Aspect() async {
    await _ensureLoaded();
    return (_data['n64_aspect'] as String?) ?? '4:3';
  }

  Future<void> setN64Aspect(String value) async {
    await _ensureLoaded();
    _data['n64_aspect'] = value;
    await _save();
  }

  // n64_overscan_enabled: 'false' | 'true' — core defaults to enabled
  Future<String> n64OverscanEnabled() async {
    await _ensureLoaded();
    return (_data['n64_overscan_enabled'] as String?) ?? 'true';
  }

  Future<void> setN64OverscanEnabled(String value) async {
    await _ensureLoaded();
    _data['n64_overscan_enabled'] = value;
    await _save();
  }

  // n64_overscan_amount: '0'..'50', applied to all four sides
  Future<String> n64OverscanAmount() async {
    await _ensureLoaded();
    return (_data['n64_overscan_amount'] as String?) ?? '0';
  }

  Future<void> setN64OverscanAmount(String value) async {
    await _ensureLoaded();
    _data['n64_overscan_amount'] = value;
    await _save();
  }

  // n64_fps_show: 'false' | 'true' — RetroArch's on-screen FPS counter
  Future<String> n64FpsShow() async {
    await _ensureLoaded();
    return (_data['n64_fps_show'] as String?) ?? 'false';
  }

  Future<void> setN64FpsShow(String value) async {
    await _ensureLoaded();
    _data['n64_fps_show'] = value;
    await _save();
  }

  // n64_audio_volume: extra gain in dB on top of RetroArch's 0dB (unity)
  // baseline — '0' | '3' | '6' | '9' | '12' | '15' | '18'
  Future<String> n64AudioVolume() async {
    await _ensureLoaded();
    return (_data['n64_audio_volume'] as String?) ?? '0';
  }

  Future<void> setN64AudioVolume(String value) async {
    await _ensureLoaded();
    _data['n64_audio_volume'] = value;
    await _save();
  }

  // ── Screen resolution ────────────────────────────────────────────────────
  // Plain text, not settings.json — display.nix's session script reads this
  // directly (via sed) at boot, before Flutter is even running, so the
  // resolution is already correct by the time retro_os starts.

  String _displayModePath() {
    if (Platform.isLinux) {
      final xdgDataHome = Platform.environment['XDG_DATA_HOME'] ??
          '${Platform.environment['HOME']}/.local/share';
      return '$xdgDataHome/retro_os/display_mode';
    } else if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ??
          '${Platform.environment['USERPROFILE']}\\AppData\\Roaming';
      return '$appData\\retro_os\\display_mode';
    }
    return '${File(Platform.resolvedExecutable).parent.path}/display_mode';
  }

  Future<void> setSystemDisplayMode(String resolution, double rate) async {
    final file = File(_displayModePath());
    await file.parent.create(recursive: true);
    await file.writeAsString('$resolution\n${rate.toStringAsFixed(2)}\n');
  }

  // ── Audio device ─────────────────────────────────────────────────────────
  // Empty string = system default.

  Future<String> audioDevice() async {
    await _ensureLoaded();
    return (_data['audio_device'] as String?) ?? '';
  }

  Future<void> setAudioDevice(String value) async {
    await _ensureLoaded();
    _data['audio_device'] = value;
    await _save();
  }

  // ── Volume ────────────────────────────────────────────────────────────────
  // ALSA/PipeWire don't persist the hardware mixer level across reboots, so
  // we save the user's last choice ourselves and re-apply it at startup
  // (see main.dart) — same approach as the display mode below.

  Future<int> savedVolume() async {
    await _ensureLoaded();
    return (_data['volume'] as int?) ?? 70;
  }

  Future<void> setSavedVolume(int value) async {
    await _ensureLoaded();
    _data['volume'] = value;
    await _save();
  }

  // ── Language ──────────────────────────────────────────────────────────────

  Future<String> language() async {
    await _ensureLoaded();
    return (_data['language'] as String?) ?? 'en_us';
  }

  Future<void> setLanguage(String value) async {
    await _ensureLoaded();
    _data['language'] = value;
    await _save();
  }

  // ── PS1 Core path ─────────────────────────────────────────────────────────

  String _ps1OptFilePath() {
    if (Platform.isLinux) {
      return '${Platform.environment['HOME']}/.config/retroarch/config/PCSX-ReARMed/PCSX-ReARMed.opt';
    } else if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ??
          '${Platform.environment['USERPROFILE']}\\AppData\\Roaming';
      return '$appData\\RetroArch\\config\\PCSX-ReARMed\\PCSX-ReARMed.opt';
    }
    return '${File(Platform.resolvedExecutable).parent.path}/PCSX-ReARMed.opt';
  }

  Future<String> ps1CorePath() async {
    await _ensureLoaded();
    if (_data['ps1_core_path'] is String) return _data['ps1_core_path'] as String;
    for (final candidate in _ps1CoreCandidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return _ps1CoreCandidates.first;
  }

  Future<void> setPs1CorePath(String path) async {
    await _ensureLoaded();
    _data['ps1_core_path'] = path;
    await _save();
  }

  // ps1_dithering: 'enabled' | 'disabled'
  Future<String> ps1Dithering() async {
    await _ensureLoaded();
    return (_data['ps1_dithering'] as String?) ?? 'enabled';
  }

  Future<void> setPs1Dithering(String value) async {
    await _ensureLoaded();
    _data['ps1_dithering'] = value;
    await _save();
  }

  // ps1_neon_enhancement: 'disabled' | 'enabled'
  Future<String> ps1NeonEnhancement() async {
    await _ensureLoaded();
    return (_data['ps1_neon_enhancement'] as String?) ?? 'disabled';
  }

  Future<void> setPs1NeonEnhancement(String value) async {
    await _ensureLoaded();
    _data['ps1_neon_enhancement'] = value;
    await _save();
  }

  // ps1_enhance_resolution: 'disabled' | 'enabled'
  Future<String> ps1EnhanceResolution() async {
    await _ensureLoaded();
    return (_data['ps1_enhance_resolution'] as String?) ?? 'disabled';
  }

  Future<void> setPs1EnhanceResolution(String value) async {
    await _ensureLoaded();
    _data['ps1_enhance_resolution'] = value;
    await _save();
  }

  // ps1_frameskip_type: 'disabled' | 'auto'
  Future<String> ps1FrameskipType() async {
    await _ensureLoaded();
    return (_data['ps1_frameskip_type'] as String?) ?? 'disabled';
  }

  Future<void> setPs1FrameskipType(String value) async {
    await _ensureLoaded();
    _data['ps1_frameskip_type'] = value;
    await _save();
  }

  // ps1_aspect: '4:3' | 'fill'
  Future<String> ps1Aspect() async {
    await _ensureLoaded();
    return (_data['ps1_aspect'] as String?) ?? '4:3';
  }

  Future<void> setPs1Aspect(String value) async {
    await _ensureLoaded();
    _data['ps1_aspect'] = value;
    await _save();
  }

  // ps1_fps_show: 'false' | 'true'
  Future<String> ps1FpsShow() async {
    await _ensureLoaded();
    return (_data['ps1_fps_show'] as String?) ?? 'false';
  }

  Future<void> setPs1FpsShow(String value) async {
    await _ensureLoaded();
    _data['ps1_fps_show'] = value;
    await _save();
  }

  // ps1_audio_volume: extra gain in dB — '0' | '3' | '6' | ... | '18'
  Future<String> ps1AudioVolume() async {
    await _ensureLoaded();
    return (_data['ps1_audio_volume'] as String?) ?? '0';
  }

  Future<void> setPs1AudioVolume(String value) async {
    await _ensureLoaded();
    _data['ps1_audio_volume'] = value;
    await _save();
  }

  Future<void> applyPs1CoreOptions() async {
    final dithering        = await ps1Dithering();
    final neonEnhancement  = await ps1NeonEnhancement();
    final enhanceResolution = await ps1EnhanceResolution();
    final frameskipType    = await ps1FrameskipType();

    final content = [
      'pcsx_rearmed_dithering = "$dithering"',
      'pcsx_rearmed_neon_enhancement_enable = "$neonEnhancement"',
      'pcsx_rearmed_enhance_resolution = "$enhanceResolution"',
      'pcsx_rearmed_frameskip_type = "$frameskipType"',
    ].join('\n');

    final file = File(_ps1OptFilePath());
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    DebugLogger.log('[SettingsService] wrote PS1 core options to ${_ps1OptFilePath()}');
  }

  Future<String> applyPs1RetroarchOverrides() async {
    final aspect = await ps1Aspect();
    final aspectRatioIndex = aspect == 'fill' ? '24' : '22';
    final device = await audioDevice();
    final fpsShow = await ps1FpsShow();
    final audioVolume = await ps1AudioVolume();

    final display = PlatformDispatcher.instance.displays.firstOrNull;
    final dpr = display?.devicePixelRatio ?? 1.0;
    final screenW = display != null ? (display.size.width / dpr).round() : 1920;
    final screenH = display != null ? (display.size.height / dpr).round() : 1080;

    final lines = [
      'aspect_ratio_index = "$aspectRatioIndex"',
      'audio_device = "$device"',
      'fps_show = "$fpsShow"',
      'audio_volume = "$audioVolume"',
      'network_cmd_enable = "true"',
      'video_fullscreen = "false"',
      'video_windowed_fullscreen = "false"',
      'video_windowed_position_width = "$screenW"',
      'video_windowed_position_height = "$screenH"',
      'video_window_show_decorations = "false"',
    ];

    final path = _retroarchOverridePath();
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString('${lines.join('\n')}\n');
    DebugLogger.log('[SettingsService] wrote PS1 RetroArch overrides to $path');
    return path;
  }

  Future<void> resetPs1() async {
    await _ensureLoaded();
    _data
      ..remove('ps1_core_path')
      ..remove('ps1_dithering')
      ..remove('ps1_neon_enhancement')
      ..remove('ps1_enhance_resolution')
      ..remove('ps1_frameskip_type')
      ..remove('ps1_aspect')
      ..remove('ps1_fps_show')
      ..remove('ps1_audio_volume');
    await _save();
  }

  // ── PS2 Core path ─────────────────────────────────────────────────────────

  Future<String> ps2CorePath() async {
    await _ensureLoaded();
    if (_data['ps2_core_path'] is String) return _data['ps2_core_path'] as String;
    for (final candidate in _ps2CoreCandidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return _ps2CoreCandidates.first;
  }

  Future<void> setPs2CorePath(String path) async {
    await _ensureLoaded();
    _data['ps2_core_path'] = path;
    await _save();
  }

  // ── PS2 Core options ──────────────────────────────────────────────────────

  String _ps2OptFilePath() {
    if (Platform.isLinux) {
      return '${Platform.environment['HOME']}/.config/retroarch/config/Play!/Play!.opt';
    } else if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ??
          '${Platform.environment['USERPROFILE']}\\AppData\\Roaming';
      return '$appData\\RetroArch\\config\\Play!\\Play!.opt';
    }
    return '${File(Platform.resolvedExecutable).parent.path}/Play!.opt';
  }

  // ps2_upscale_multiplier: '1x' | '2x' | '4x' | '8x'
  Future<String> ps2UpscaleMultiplier() async {
    await _ensureLoaded();
    return (_data['ps2_upscale_multiplier'] as String?) ?? '1x';
  }

  Future<void> setPs2UpscaleMultiplier(String value) async {
    await _ensureLoaded();
    _data['ps2_upscale_multiplier'] = value;
    await _save();
  }

  // ps2_presentation_mode: 'Fit Screen' | 'Fill Screen' | 'Original Size'
  Future<String> ps2PresentationMode() async {
    await _ensureLoaded();
    return (_data['ps2_presentation_mode'] as String?) ?? 'Fit Screen';
  }

  Future<void> setPs2PresentationMode(String value) async {
    await _ensureLoaded();
    _data['ps2_presentation_mode'] = value;
    await _save();
  }

  // ps2_bilinear_filtering: 'false' | 'true'
  Future<String> ps2BilinearFiltering() async {
    await _ensureLoaded();
    return (_data['ps2_bilinear_filtering'] as String?) ?? 'false';
  }

  Future<void> setPs2BilinearFiltering(String value) async {
    await _ensureLoaded();
    _data['ps2_bilinear_filtering'] = value;
    await _save();
  }

  Future<void> applyPs2CoreOptions() async {
    final upscale      = await ps2UpscaleMultiplier();
    final presentation = await ps2PresentationMode();
    final bilinear     = await ps2BilinearFiltering();

    final content = [
      'play_res_multi = "$upscale"',
      'play_presentation_mode = "$presentation"',
      'play_bilinear_filtering = "$bilinear"',
    ].join('\n');

    final file = File(_ps2OptFilePath());
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    DebugLogger.log('[SettingsService] wrote PS2 core options to ${_ps2OptFilePath()}');
  }

  // ── PS2 Settings ──────────────────────────────────────────────────────────

  // ps2_fps_show: 'false' | 'true'
  Future<String> ps2FpsShow() async {
    await _ensureLoaded();
    return (_data['ps2_fps_show'] as String?) ?? 'false';
  }

  Future<void> setPs2FpsShow(String value) async {
    await _ensureLoaded();
    _data['ps2_fps_show'] = value;
    await _save();
  }

  // ps2_audio_volume: extra gain in dB — '0' | '3' | '6' | ... | '18'
  Future<String> ps2AudioVolume() async {
    await _ensureLoaded();
    return (_data['ps2_audio_volume'] as String?) ?? '0';
  }

  Future<void> setPs2AudioVolume(String value) async {
    await _ensureLoaded();
    _data['ps2_audio_volume'] = value;
    await _save();
  }

  Future<String> applyPs2RetroarchOverrides() async {
    final device = await audioDevice();
    final fpsShow = await ps2FpsShow();
    final audioVolume = await ps2AudioVolume();

    final display = PlatformDispatcher.instance.displays.firstOrNull;
    final dpr = display?.devicePixelRatio ?? 1.0;
    final screenW = display != null ? (display.size.width / dpr).round() : 1920;
    final screenH = display != null ? (display.size.height / dpr).round() : 1080;

    final lines = [
      'audio_device = "$device"',
      'fps_show = "$fpsShow"',
      'audio_volume = "$audioVolume"',
      'network_cmd_enable = "true"',
      'video_fullscreen = "false"',
      'video_windowed_fullscreen = "false"',
      'video_windowed_position_width = "$screenW"',
      'video_windowed_position_height = "$screenH"',
      'video_window_show_decorations = "false"',
      // Play! core requests OpenGL 3.2 core profile via HW render. Under X11
      // the GLX path fails with GLXBadFBConfig on RPi4/V3D because Mesa's GLX
      // implementation doesn't expose core-profile FBConfigs. EGL (DRI3 path)
      // does, so we force the EGL context driver here.
      'video_context_driver = "egl"',
    ];

    final path = _retroarchOverridePath();
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString('${lines.join('\n')}\n');
    DebugLogger.log('[SettingsService] wrote PS2 RetroArch overrides to $path');
    return path;
  }

  // ── Reset ─────────────────────────────────────────────────────────────────

  Future<void> resetN64Graphics() async {
    await _ensureLoaded();
    _data
      ..remove('n64_core_path')
      ..remove('n64_resolution')
      ..remove('n64_msaa')
      ..remove('n64_texture_filter')
      ..remove('n64_frame_dupes')
      ..remove('n64_aspect')
      ..remove('n64_overscan_enabled')
      ..remove('n64_overscan_amount')
      ..remove('n64_fps_show')
      ..remove('n64_audio_volume');
    await _save();
  }

  Future<void> resetPs2() async {
    await _ensureLoaded();
    _data
      ..remove('ps2_core_path')
      ..remove('ps2_upscale_multiplier')
      ..remove('ps2_presentation_mode')
      ..remove('ps2_bilinear_filtering')
      ..remove('ps2_fps_show')
      ..remove('ps2_audio_volume');
    await _save();
  }

  // ── Apply to RetroArch .opt ───────────────────────────────────────────────

  Future<void> applyN64CoreOptions() async {
    final resolution = await n64Resolution();
    final msaa = await n64Msaa();
    final filter = await n64TextureFilter();

    final res = _resolutionMap[resolution] ?? _resolutionMap['hd']!;
    final bilinear = filter == 'linear' ? 'standard' : '3point';

    final frameDupes = await n64FrameDupes();
    final frameDupesValue = frameDupes == 'true' ? 'True' : 'False';

    final aspect = await n64Aspect();
    // 'fill' isn't a valid mupen64plus-aspect value — that's handled at the
    // RetroArch level instead, via applyRetroarchOverrides(). The core still
    // needs a real base aspect to render, so fall back to 16:9 for it.
    final coreAspect = aspect == 'fill' ? '16:9' : aspect;
    final overscanEnabled = await n64OverscanEnabled();
    final overscanEnabledValue = overscanEnabled == 'true' ? 'Enabled' : 'Disabled';
    final overscanAmount = await n64OverscanAmount();

    final content = [
      'mupen64plus-169screensize = "${res[0]}"',
      'mupen64plus-43screensize = "${res[1]}"',
      'mupen64plus-MultiSampling = "$msaa"',
      'mupen64plus-BilinearMode = "$bilinear"',
      'mupen64plus-FrameDuping = "$frameDupesValue"',
      'mupen64plus-aspect = "$coreAspect"',
      'mupen64plus-EnableOverscan = "$overscanEnabledValue"',
      'mupen64plus-OverscanTop = "$overscanAmount"',
      'mupen64plus-OverscanLeft = "$overscanAmount"',
      'mupen64plus-OverscanRight = "$overscanAmount"',
      'mupen64plus-OverscanBottom = "$overscanAmount"',
    ].join('\n');

    final file = File(_optFilePath());
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    DebugLogger.log('[SettingsService] wrote N64 core options to ${_optFilePath()}');
  }

  // ── Apply to RetroArch (transient, via --appendconfig) ──────────────────

  String _retroarchOverridePath() {
    if (Platform.isLinux) {
      return '${Platform.environment['HOME']}/.config/retroarch/retro_os_override.cfg';
    } else if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ??
          '${Platform.environment['USERPROFILE']}\\AppData\\Roaming';
      return '$appData\\RetroArch\\retro_os_override.cfg';
    }
    return '${File(Platform.resolvedExecutable).parent.path}/retro_os_override.cfg';
  }

  // Writes a small cfg meant for `retroarch --appendconfig=<path>` — settings
  // that live on the RetroArch side rather than in a core's .opt file, so we
  // never touch the main retroarch.cfg. Returns the path to pass along.
  Future<String> applyRetroarchOverrides() async {
    final aspect = await n64Aspect();
    // aspectratio_lut index: 22 = Core Provided, 24 = Full (stretch to fill,
    // ignoring aspect entirely).
    final aspectRatioIndex = aspect == 'fill' ? '24' : '22';
    final device = await audioDevice();
    final fpsShow = await n64FpsShow();
    final audioVolume = await n64AudioVolume();

    final display = PlatformDispatcher.instance.displays.firstOrNull;
    final dpr = display?.devicePixelRatio ?? 1.0;
    final screenW = display != null ? (display.size.width / dpr).round() : 1920;
    final screenH = display != null ? (display.size.height / dpr).round() : 1080;

    final lines = [
      'aspect_ratio_index = "$aspectRatioIndex"',
      'audio_device = "$device"',
      'fps_show = "$fpsShow"',
      'audio_volume = "$audioVolume"',
      'network_cmd_enable = "true"',
      'video_fullscreen = "false"',
      'video_windowed_fullscreen = "false"',
      'video_windowed_position_width = "$screenW"',
      'video_windowed_position_height = "$screenH"',
      'video_window_show_decorations = "false"',
    ];

    final path = _retroarchOverridePath();
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString('${lines.join('\n')}\n');
    DebugLogger.log('[SettingsService] wrote RetroArch overrides to $path');
    return path;
  }
}
