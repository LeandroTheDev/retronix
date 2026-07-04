import 'dart:convert';
import 'dart:io';
import 'package:yaml/yaml.dart';

void main() {
  final lock = File('pubspec.lock');
  if (!lock.existsSync()) {
    print('pubspec.lock not found. Run "flutter pub get" first.');
    exit(1);
  }

  final yaml = loadYaml(lock.readAsStringSync());
  final json = JsonEncoder.withIndent('  ').convert(yaml);
  File('pubspec.lock.json').writeAsStringSync('$json\n');
  print('pubspec.lock.json updated.');
}
