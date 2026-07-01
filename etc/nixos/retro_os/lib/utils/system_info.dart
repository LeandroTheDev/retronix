import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'debug_logger.dart';

const _unknown = 'Unknown';

class DisplayMode {
  const DisplayMode(this.resolution, this.rate);

  final String resolution; // e.g. "1920x1080"
  final double rate;       // e.g. 60.0

  String get label => '$resolution @ ${rate.round()}Hz';
}

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

  // Desktop/laptop motherboard via DMI (x86 systems)
  try {
    final vendorFile = File('/sys/class/dmi/id/board_vendor');
    final nameFile = File('/sys/class/dmi/id/board_name');
    if (await vendorFile.exists() && await nameFile.exists()) {
      final vendor = (await vendorFile.readAsString()).trim();
      final name = (await nameFile.readAsString()).trim();
      if (vendor.isNotEmpty && name.isNotEmpty) return '$vendor $name';
      if (name.isNotEmpty) return name;
    }
  } catch (e) {
    DebugLogger.log('[system_info] getDeviceModel: DMI read failed: $e');
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

// Name of the first output xrandr reports as connected (e.g. "HDMI-1",
// "HDMI-2") — whichever HDMI port is actually plugged in, not hardcoded.
Future<String?> getConnectedOutput() async {
  try {
    final result = await Process.run(
      'sh',
      ['-c', "xrandr --query 2>/dev/null | grep ' connected' | cut -d' ' -f1 | head -n1"],
    );
    final output = (result.stdout as String).trim();
    if (output.isEmpty) {
      DebugLogger.log('[system_info] getConnectedOutput: no connected output found');
      return null;
    }
    return output;
  } catch (e) {
    DebugLogger.log('[system_info] getConnectedOutput failed: $e');
    return null;
  }
}

// Currently active output mode, or null if it couldn't be determined/parsed.
Future<DisplayMode?> getCurrentDisplayMode() async {
  try {
    final result = await Process.run(
      'sh',
      ['-c', "xrandr --current 2>/dev/null | grep '\\*'"],
    );
    final output = (result.stdout as String).trim();
    if (output.isEmpty) {
      DebugLogger.log('[system_info] getCurrentDisplayMode: no active mode found in xrandr output');
      return null;
    }

    final line = output.split('\n').first;
    final match = RegExp(r'(\d+x\d+)\s+([\d.]+)\*').firstMatch(line);
    if (match == null) {
      DebugLogger.log('[system_info] getCurrentDisplayMode: failed to parse xrandr line: $line');
      return null;
    }

    final rate = double.tryParse(match.group(2)!);
    if (rate == null) return null;
    return DisplayMode(match.group(1)!, rate);
  } catch (e) {
    DebugLogger.log('[system_info] getCurrentDisplayMode failed: $e');
    return null;
  }
}

// e.g. "1920x1080 @ 60Hz"
Future<String> getDisplayMode() async {
  final mode = await getCurrentDisplayMode();
  return mode?.label ?? _unknown;
}

// Every resolution the display advertises via EDID, each paired with its
// highest available refresh rate.
Future<List<DisplayMode>> getAvailableDisplayModes() async {
  try {
    final connectedOutput = await getConnectedOutput();
    if (connectedOutput == null) return [];

    final result = await Process.run('sh', ['-c', 'xrandr --query 2>/dev/null']);
    final lines = (result.stdout as String).split('\n');

    final startIdx = lines.indexWhere((l) => l.startsWith('$connectedOutput connected'));
    if (startIdx == -1) {
      DebugLogger.log('[system_info] getAvailableDisplayModes: $connectedOutput not found in xrandr output');
      return [];
    }

    final modes = <DisplayMode>[];
    for (var i = startIdx + 1; i < lines.length; i++) {
      final line = lines[i];
      if (!line.startsWith('  ')) break; // next output section

      final match = RegExp(r'^\s+(\d+x\d+)\s+(.+)$').firstMatch(line);
      if (match == null) continue;

      final rates = RegExp(r'[\d.]+')
          .allMatches(match.group(2)!)
          .map((m) => double.parse(m.group(0)!))
          .toList();
      if (rates.isEmpty) continue;

      modes.add(DisplayMode(match.group(1)!, rates.reduce((a, b) => a > b ? a : b)));
    }
    return modes;
  } catch (e) {
    DebugLogger.log('[system_info] getAvailableDisplayModes failed: $e');
    return [];
  }
}

// Returns true on success.
Future<bool> applyDisplayMode(DisplayMode mode) async {
  try {
    final connectedOutput = await getConnectedOutput();
    if (connectedOutput == null) {
      DebugLogger.log('[system_info] applyDisplayMode(${mode.label}): no connected output found');
      return false;
    }

    final result = await Process.run('sh', [
      '-c',
      'xrandr --output $connectedOutput --mode ${mode.resolution} --rate ${mode.rate.toStringAsFixed(2)}',
    ]);
    if (result.exitCode != 0) {
      DebugLogger.log('[system_info] applyDisplayMode(${mode.label}) failed: ${result.stderr}');
    }
    return result.exitCode == 0;
  } catch (e) {
    DebugLogger.log('[system_info] applyDisplayMode(${mode.label}) failed: $e');
    return false;
  }
}

class AudioDevice {
  const AudioDevice(this.name, this.label);
  final String name;  // PipeWire sink name, empty = system default
  final String label;
}

// Plays a short beep on [deviceName] (PipeWire sink). Empty = system default.
// Generates raw PCM inline — no sound file needed.
Future<void> playBeep(String deviceName) async {
  const rate = 44100;
  const freq = 520.0;
  final frames = (rate * 0.18).toInt();
  final data = ByteData(frames * 2);
  for (var i = 0; i < frames; i++) {
    final fadeIn  = i < frames * 0.1 ? i / (frames * 0.1) : 1.0;
    final fadeOut = i > frames * 0.5 ? (frames - i) / (frames * 0.5) : 1.0;
    final sample  = (sin(2 * pi * freq * i / rate) * 5000 * fadeIn * fadeOut).round();
    data.setInt16(i * 2, sample, Endian.little);
  }
  try {
    final args = ['--raw', '--format=s16le', '--rate=$rate', '--channels=1'];
    if (deviceName.isNotEmpty) args.add('--device=$deviceName');
    final process = await Process.start('paplay', args);
    process.stdin.add(data.buffer.asUint8List());
    await process.stdin.close();
    await process.exitCode;
  } catch (e) {
    DebugLogger.log('[system_info] playBeep failed: $e');
  }
}

// Softer, shorter beep for volume feedback.
Future<void> playVolumeBeep(String deviceName) async {
  const rate = 44100;
  const freq = 480.0;
  final frames = (rate * 0.1).toInt();
  final data = ByteData(frames * 2);
  for (var i = 0; i < frames; i++) {
    final fadeIn  = i < frames * 0.1 ? i / (frames * 0.1) : 1.0;
    final fadeOut = i > frames * 0.4 ? (frames - i) / (frames * 0.6) : 1.0;
    final sample  = (sin(2 * pi * freq * i / rate) * 2500 * fadeIn * fadeOut).round();
    data.setInt16(i * 2, sample, Endian.little);
  }
  try {
    final args = ['--raw', '--format=s16le', '--rate=$rate', '--channels=1'];
    if (deviceName.isNotEmpty) args.add('--device=$deviceName');
    final process = await Process.start('paplay', args);
    process.stdin.add(data.buffer.asUint8List());
    await process.stdin.close();
    await process.exitCode;
  } catch (e) {
    DebugLogger.log('[system_info] playVolumeBeep failed: $e');
  }
}

// Lists PipeWire sinks via pactl. Always includes a "Default" entry first.
Future<List<AudioDevice>> getAudioDevices() async {
  final devices = <AudioDevice>[const AudioDevice('', 'Default')];
  try {
    final result = await Process.run('sh', ['-c', 'pactl list sinks 2>/dev/null']);
    final output = result.stdout as String;
    String? currentName;
    for (final line in output.split('\n')) {
      final nameMatch = RegExp(r'^\s+Name:\s+(.+)$').firstMatch(line);
      if (nameMatch != null) {
        currentName = nameMatch.group(1)!.trim();
        continue;
      }
      final descMatch = RegExp(r'^\s+Description:\s+(.+)$').firstMatch(line);
      if (descMatch != null && currentName != null) {
        devices.add(AudioDevice(currentName, descMatch.group(1)!.trim()));
        currentName = null;
      }
    }
  } catch (e) {
    DebugLogger.log('[system_info] getAudioDevices failed: $e');
  }
  return devices;
}

// Returns the current master volume as a percentage (0–100), trying 'Master'
// then 'PCM' as fallback. Returns 50 if neither control is found.
Future<int> getVolumeLevel() async {
  for (final control in ['Master', 'PCM']) {
    try {
      final result = await Process.run('sh', [
        '-c',
        "amixer get '$control' 2>/dev/null | grep -oP '(?<=\\[)\\d+(?=%\\])' | head -1",
      ]);
      final value = int.tryParse((result.stdout as String).trim());
      if (value != null) return value;
    } catch (e) {
      DebugLogger.log('[system_info] getVolumeLevel($control) failed: $e');
    }
  }
  return 50;
}

// Sets the master volume to [percent] (0–100), trying 'Master' then 'PCM'.
Future<void> setVolumeLevel(int percent) async {
  for (final control in ['Master', 'PCM']) {
    try {
      final result = await Process.run('sh', [
        '-c',
        "amixer set '$control' $percent% 2>/dev/null",
      ]);
      if (result.exitCode == 0) return;
    } catch (e) {
      DebugLogger.log('[system_info] setVolumeLevel($control) failed: $e');
    }
  }
  DebugLogger.log('[system_info] setVolumeLevel: no working amixer control found');
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

// e.g. "V3D 4.2" or "llvmpipe (LLVM 17.0.6, 128 bits)"
Future<String> getOpenGlRenderer() async {
  try {
    final result = await Process.run(
      'sh',
      ['-c', "glxinfo 2>/dev/null | grep 'OpenGL renderer string'"],
    );
    final output = (result.stdout as String).trim();
    if (output.isEmpty) {
      DebugLogger.log('[system_info] getOpenGlRenderer: no output from glxinfo');
      return _unknown;
    }

    final renderer = output.split(':').skip(1).join(':').trim();
    return renderer.isNotEmpty ? renderer : _unknown;
  } catch (e) {
    DebugLogger.log('[system_info] getOpenGlRenderer failed: $e');
    return _unknown;
  }
}
