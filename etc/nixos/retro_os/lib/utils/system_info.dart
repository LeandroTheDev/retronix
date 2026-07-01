import 'dart:io';
import 'debug_logger.dart';

const _unknown = 'Unknown';

// Raspberry Pi model string (falls back to hostname on non-Pi/dev machines)
Future<String> getDeviceModel() async {
  try {
    final model = await Process.run(
      'sh',
      ['-c', "cat /proc/device-tree/model 2>/dev/null | tr -d '\\0'"],
    );
    final name = (model.stdout as String).trim();
    if (name.isNotEmpty) return name;
  } catch (e) {
    DebugLogger.log('[system_info] getDeviceModel: device-tree read failed: $e');
  }

  try {
    final hostname = await Process.run('sh', ['-c', 'hostname']);
    final result = (hostname.stdout as String).trim();
    if (result.isNotEmpty) return result;
  } catch (e) {
    DebugLogger.log('[system_info] getDeviceModel: hostname fallback failed: $e');
  }

  return _unknown;
}

// e.g. "aarch64", "x86_64"
Future<String> getCpuArchitecture() async {
  try {
    final result = await Process.run('sh', ['-c', 'uname -m']);
    final arch = (result.stdout as String).trim();
    return arch.isNotEmpty ? arch : _unknown;
  } catch (e) {
    DebugLogger.log('[system_info] getCpuArchitecture failed: $e');
    return _unknown;
  }
}

// Current Xorg output mode, e.g. "1920x1080 @ 60Hz"
Future<String> getDisplayMode() async {
  try {
    final result = await Process.run(
      'sh',
      ['-c', "xrandr --current 2>/dev/null | grep '\\*'"],
    );
    final output = (result.stdout as String).trim();
    if (output.isEmpty) {
      DebugLogger.log('[system_info] getDisplayMode: no active mode found in xrandr output');
      return _unknown;
    }

    final line = output.split('\n').first;
    final match = RegExp(r'(\d+x\d+)\s+([\d.]+)\*').firstMatch(line);
    if (match == null) {
      DebugLogger.log('[system_info] getDisplayMode: failed to parse xrandr line: $line');
      return _unknown;
    }

    final resolution = match.group(1)!;
    final rate = double.tryParse(match.group(2)!);
    final hz = rate != null ? rate.round().toString() : match.group(2)!;
    return '$resolution @ ${hz}Hz';
  } catch (e) {
    DebugLogger.log('[system_info] getDisplayMode failed: $e');
    return _unknown;
  }
}

// e.g. "3.1 Mesa 24.0.0" — via glxinfo, requires the glxinfo package
Future<String> getOpenGlVersion() async {
  try {
    final result = await Process.run(
      'sh',
      ['-c', "glxinfo 2>/dev/null | grep 'OpenGL version string'"],
    );
    final output = (result.stdout as String).trim();
    if (output.isEmpty) {
      DebugLogger.log('[system_info] getOpenGlVersion: no output from glxinfo');
      return _unknown;
    }

    final version = output.split(':').skip(1).join(':').trim();
    return version.isNotEmpty ? version : _unknown;
  } catch (e) {
    DebugLogger.log('[system_info] getOpenGlVersion failed: $e');
    return _unknown;
  }
}
