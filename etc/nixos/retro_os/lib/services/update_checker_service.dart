import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../utils/debug_logger.dart';

class UpdateCheckerService {
  UpdateCheckerService._();
  static final instance = UpdateCheckerService._();

  static const _repoUrl  = 'https://github.com/LeandroTheDev/retronix';
  static const _branch   = 'main';
  static const _checkInterval = Duration(hours: 1);

  final hasUpdates = ValueNotifier<bool>(false);
  Timer? _timer;

  String get _sourceDir {
    final home = Platform.environment['HOME'] ?? '/home/admin';
    return '$home/.local/share/retro_os/source';
  }

  void init() {
    _initAsync();
  }

  void checkNow() {
    _checkForUpdates();
  }

  void dispose() {
    _timer?.cancel();
  }

  Future<void> _initAsync() async {
    try {
      await _ensureCloned();
      await _checkForUpdates();
      _timer = Timer.periodic(_checkInterval, (_) => _checkForUpdates());
    } catch (e) {
      DebugLogger.log('[UpdateChecker] unexpected init error: $e');
    }
  }

  Future<void> _ensureCloned() async {
    final dir = Directory(_sourceDir);
    if (await dir.exists()) return;

    DebugLogger.log('[UpdateChecker] source dir missing — cloning $_repoUrl into $_sourceDir');
    try {
      await dir.parent.create(recursive: true);
      final result = await Process.run('git', ['clone', _repoUrl, _sourceDir]);
      if (result.exitCode != 0) {
        DebugLogger.log('[UpdateChecker] clone failed (exit ${result.exitCode}): ${result.stderr}');
      } else {
        DebugLogger.log('[UpdateChecker] clone complete');
      }
    } catch (e) {
      DebugLogger.log('[UpdateChecker] clone exception: $e');
    }
  }

  Future<void> _checkForUpdates() async {
    try {
      final fetch = await Process.run('git', ['-C', _sourceDir, 'fetch', 'origin', '--quiet']);
      if (fetch.exitCode != 0) {
        DebugLogger.log('[UpdateChecker] fetch failed (exit ${fetch.exitCode}): ${fetch.stderr}');
        return;
      }

      final log = await Process.run(
        'git',
        ['-C', _sourceDir, 'log', 'HEAD..origin/$_branch', '--oneline'],
      );
      final behind = (log.stdout as String).trim();
      final updates = behind.isNotEmpty;
      DebugLogger.log('[UpdateChecker] hasUpdates=$updates${updates ? ' ($behind)' : ''}');
      hasUpdates.value = updates;
    } catch (e) {
      DebugLogger.log('[UpdateChecker] check exception: $e');
    }
  }
}
