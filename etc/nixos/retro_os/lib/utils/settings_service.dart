import 'dart:convert';
import 'dart:io';
import 'debug_logger.dart';

const _n64CoreDefault =
    '/run/current-system/sw/lib/retroarch/cores/mupen64plus_libretro.so';

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
    return (_data['n64_core_path'] as String?) ?? _n64CoreDefault;
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
    return (_data['n64_resolution'] as String?) ?? 'hd';
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
    return (_data['n64_texture_filter'] as String?) ?? 'linear';
  }

  Future<void> setN64TextureFilter(String value) async {
    await _ensureLoaded();
    _data['n64_texture_filter'] = value;
    await _save();
  }

  // n64_frame_dupes: 'false' | 'true'
  Future<String> n64FrameDupes() async {
    await _ensureLoaded();
    return (_data['n64_frame_dupes'] as String?) ?? 'false';
  }

  Future<void> setN64FrameDupes(String value) async {
    await _ensureLoaded();
    _data['n64_frame_dupes'] = value;
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

  // ── Reset ─────────────────────────────────────────────────────────────────

  Future<void> resetN64Graphics() async {
    await _ensureLoaded();
    _data
      ..remove('n64_core_path')
      ..remove('n64_resolution')
      ..remove('n64_msaa')
      ..remove('n64_texture_filter')
      ..remove('n64_frame_dupes');
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

    final content = [
      'mupen64plus-169resolutions = "${res[0]}"',
      'mupen64plus-43resolutions = "${res[1]}"',
      'mupen64plus-MSAA = "$msaa"',
      'mupen64plus-BilinearMode = "$bilinear"',
      'mupen64plus-FrameDupes = "$frameDupesValue"',
    ].join('\n');

    final file = File(_optFilePath());
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    DebugLogger.log('[SettingsService] wrote N64 core options to ${_optFilePath()}');
  }
}
