import 'dart:io';

class DebugLogger {
  DebugLogger._();

  static final _file = File('${Directory.systemTemp.path}/retro_os_debug.log');
  static final _achFile = File('${Directory.systemTemp.path}/retro_os_debug_achivements.log');

  static String get path => _file.path;
  static String get achPath => _achFile.path;

  static void log(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final line = '[$timestamp] $message';
    print(line);
    _file.writeAsStringSync('$line\n', mode: FileMode.append);
  }

  static void achLog(String message) {
    final timestamp = DateTime.now().toIso8601String();
    _achFile.writeAsStringSync('[$timestamp] $message\n', mode: FileMode.append);
  }

  static void cleanIfOld() {
    _deleteIfOlderThanOneDay(_file);
    _deleteIfOlderThanOneDay(_achFile);
  }

  static void _deleteIfOlderThanOneDay(File file) {
    if (!file.existsSync()) return;
    final age = DateTime.now().difference(file.lastModifiedSync());
    if (age.inHours >= 24) file.deleteSync();
  }

  static void clear() {
    if (_file.existsSync()) _file.deleteSync();
  }

  static void clearAch() {
    if (_achFile.existsSync()) _achFile.deleteSync();
  }
}
