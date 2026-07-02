import 'dart:io';
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

// Returns [deviceName]'s volume as a percentage (0–100). Empty = system
// default sink (matching the AudioDevice convention). Returns 50 if
// it can't be determined.
//
// Uses pactl (PipeWire's ALSA mixer controls are owned by WirePlumber, which
// re-syncs them to its own remembered volume the instant something else sets
// them via amixer — reading the value back right after would just show
// whatever WirePlumber reverted it to, not what was requested).
Future<int> getVolumeLevel(String deviceName) async {
  final sink = deviceName.isEmpty ? '@DEFAULT_SINK@' : deviceName;
  try {
    final result = await Process.run('sh', [
      '-c',
      "pactl get-sink-volume '$sink' 2>/dev/null | grep -oP '\\d+(?=%)' | head -1",
    ]);
    final value = int.tryParse((result.stdout as String).trim());
    if (value != null) return value;
  } catch (e) {
    DebugLogger.log('[system_info] getVolumeLevel($sink) failed: $e');
  }
  return 50;
}

// Sets [deviceName] as the PipeWire default sink. Empty = no-op.
Future<void> setDefaultAudioDevice(String deviceName) async {
  if (deviceName.isEmpty) return;
  try {
    final result = await Process.run('sh', [
      '-c',
      "pactl set-default-sink '$deviceName'",
    ]);
    DebugLogger.log('[system_info] setDefaultAudioDevice($deviceName): exit=${result.exitCode}');
  } catch (e) {
    DebugLogger.log('[system_info] setDefaultAudioDevice($deviceName) exception: $e');
  }
}

// Sets [deviceName]'s volume to [percent] (0–100) and unmutes it. Empty =
// system default sink.
Future<void> setVolumeLevel(int percent, String deviceName) async {
  final sink = deviceName.isEmpty ? '@DEFAULT_SINK@' : deviceName;
  try {
    final result = await Process.run('sh', [
      '-c',
      "pactl set-sink-mute '$sink' 0 && pactl set-sink-volume '$sink' $percent%",
    ]);
    DebugLogger.log('[system_info] setVolumeLevel($sink, $percent%): exit=${result.exitCode} stdout="${(result.stdout as String).trim()}" stderr="${(result.stderr as String).trim()}"');
  } catch (e) {
    DebugLogger.log('[system_info] setVolumeLevel($sink) exception: $e');
  }
}

// Raises and focuses the X11 window owned by [targetPid] — used to switch
// between retro_os and RetroArch (matchbox auto-raises new windows on map,
// but has no alt-tab, so anything after that needs to be driven manually).
// Silently no-ops if xdotool can't find a window for that pid.
Future<void> focusWindowByPid(int targetPid) async {
  try {
    final result = await Process.run('xdotool', ['search', '--pid', '$targetPid', 'windowactivate']);
    if (result.exitCode != 0) {
      DebugLogger.log('[system_info] focusWindowByPid($targetPid) failed: ${result.stderr}');
    }
  } catch (e) {
    DebugLogger.log('[system_info] focusWindowByPid($targetPid) failed: $e');
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
