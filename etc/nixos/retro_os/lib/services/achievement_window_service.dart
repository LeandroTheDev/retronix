import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'achievements/achievement.dart';
import 'achievements/achievement_service.dart';
import '../utils/app_localizations.dart';
import '../utils/debug_logger.dart';
import '../utils/locale_service.dart';

class AchievementWindowService {
  AchievementWindowService._();
  static final instance = AchievementWindowService._();

  StreamSubscription<Achievement>? _sub;
  int? _retroarchPid;
  Process? _process;

  static const _holdSeconds = 4;

  static String get _binary {
    if (kDebugMode) {
      return '/home/leans/Templates/retronix/etc/nixos/retro_os_notification'
          '/build/linux/x64/release/bundle/retro_os_notification';
    }
    return 'retro_os_notification';
  }

  void init() {
    _sub = AchievementService.instance.unlocked.listen(_onUnlocked);
  }

  Future<void> _launchProcess() async {
    try {
      _process = await Process.start(_binary, []);
      DebugLogger.log('[AchievementWindowService] notification process started (pid=${_process!.pid})');
      _process!.exitCode.then((_) {
        _process = null;
        if (_retroarchPid != null) {
          DebugLogger.log('[AchievementWindowService] notification process exited, restarting...');
          _launchProcess();
        }
      });
    } catch (e) {
      DebugLogger.log('[AchievementWindowService] failed to start notification process: $e');
    }
  }

  void startSession(int retroarchPid) {
    _retroarchPid = retroarchPid;
    DebugLogger.log('[AchievementWindowService] session started, retroarch pid=$retroarchPid');
    _launchProcess();
  }

  void stopSession() {
    DebugLogger.log('[AchievementWindowService] session stopped');
    _retroarchPid = null;
    _process?.stdin.close();
    _process?.kill();
    _process = null;
  }

  void dispose() {
    _sub?.cancel();
    _process?.stdin.close();
    _process?.kill();
    _process = null;
  }

  Future<void> _onUnlocked(Achievement achievement) async {
    if (_retroarchPid == null) return;
    if (_process == null) await _launchProcess();

    final message = jsonEncode({
      'header': AppLocalizations(LocaleService.instance.locale).achievementUnlocked,
      'title': achievement.title,
      'points': achievement.points,
      'seconds': _holdSeconds,
    });

    DebugLogger.log('[AchievementWindowService] sending notification: ${achievement.title}');
    try {
      _process!.stdin.writeln(message);
    } catch (e) {
      DebugLogger.log('[AchievementWindowService] send error: $e');
    }
  }
}
