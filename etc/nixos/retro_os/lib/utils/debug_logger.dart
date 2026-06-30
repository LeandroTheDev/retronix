import 'dart:io';

class DebugLogger {
  DebugLogger._();

  static final _file = File('${Directory.systemTemp.path}/retro_os_debug.log');

  static String get path => _file.path;

  static void log(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final line = '[$timestamp] $message';
    print(line);
    _file.writeAsStringSync('$line\n', mode: FileMode.append);
  }

  static void clear() {
    if (_file.existsSync()) _file.deleteSync();
  }
}
