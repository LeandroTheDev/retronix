import 'dart:io';
import 'debug_logger.dart';

String _consolesRoot() {
  String root;

  if (Platform.isLinux) {
    final xdgDataHome = Platform.environment['XDG_DATA_HOME']
        ?? '${Platform.environment['HOME']}/.local/share';
    root = '$xdgDataHome/retro_os/Consoles';
  } else if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA']
        ?? '${Platform.environment['USERPROFILE']}\\AppData\\Roaming';
    root = '$appData\\retro_os\\Consoles';
  } else {
    root = '${File(Platform.resolvedExecutable).parent.path}/Consoles';
  }

  DebugLogger.log('[devices] consolesRoot: $root');
  return root;
}

// Returns the list of console names (subdirectory names inside Consoles/)
Future<List<String>> getAvailableConsoles() async {
  final path = _consolesRoot();
  final directory = Directory(path);

  if (!await directory.exists()) {
    DebugLogger.log('[devices] getAvailableConsoles: directory not found: $path');
    return [];
  }

  final entries = await directory.list().toList();
  final consoles = entries
      .whereType<Directory>()
      .map((d) => d.uri.pathSegments.lastWhere((s) => s.isNotEmpty))
      .toList()
    ..sort();

  DebugLogger.log('[devices] getAvailableConsoles: found ${consoles.length} consoles: $consoles');
  return consoles;
}

// Returns the list of game names (subdirectory names inside <console>/Games/)
Future<List<String>> getAvailableGames(String console) async {
  final path = '${_consolesRoot()}/$console/Games';
  final directory = Directory(path);

  if (!await directory.exists()) {
    DebugLogger.log('[devices] getAvailableGames($console): directory not found: $path');
    return [];
  }

  final entries = await directory.list().toList();
  final games = entries
      .whereType<Directory>()
      .map((d) => d.uri.pathSegments.lastWhere((s) => s.isNotEmpty))
      .toList()
    ..sort();

  DebugLogger.log('[devices] getAvailableGames($console): found ${games.length} games: $games');
  return games;
}

const _imageExtensions = ['png', 'jpg', 'jpeg', 'webp'];

String? _findImage(String basePath) {
  for (final ext in _imageExtensions) {
    final file = File('$basePath.$ext');
    if (file.existsSync()) return file.path;
  }
  return null;
}

// Path to <console>/console_image.* (first matching extension found)
String? getConsoleImagePath(String console) {
  return _findImage('${_consolesRoot()}/$console/console_image');
}

// Path to <console>/Games/<game>/game_image.* (first matching extension found)
String? getGameImagePath(String console, String game) {
  return _findImage('${_consolesRoot()}/$console/Games/$game/game_image');
}

// Path to the ROM file inside <console>/Games/<game>/Game/
Future<String?> getGameFilePath(String console, String game) async {
  final path = '${_consolesRoot()}/$console/Games/$game/Game';
  final directory = Directory(path);

  if (!await directory.exists()) {
    DebugLogger.log('[devices] getGameFilePath($console, $game): directory not found: $path');
    return null;
  }

  final entries = await directory.list().toList();
  final files = entries.whereType<File>().toList();
  final result = files.isEmpty ? null : files.first.path;

  DebugLogger.log('[devices] getGameFilePath($console, $game): ${result ?? "no file found"} in $path');
  return result;
}
