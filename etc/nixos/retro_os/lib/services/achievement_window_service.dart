import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'achievements/achievement.dart';
import 'achievements/achievement_service.dart';
import '../utils/debug_logger.dart';

class AchievementWindowService {
  AchievementWindowService._();
  static final instance = AchievementWindowService._();

  StreamSubscription<Achievement>? _sub;
  int? _retroarchPid;

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

  void startSession(int retroarchPid) {
    _retroarchPid = retroarchPid;
    DebugLogger.log('[AchievementWindowService] session started, retroarch pid=$retroarchPid');
  }

  void stopSession() {
    DebugLogger.log('[AchievementWindowService] session stopped');
    _retroarchPid = null;
  }

  void dispose() {
    _sub?.cancel();
  }

  Future<void> _onUnlocked(Achievement achievement) async {
    if (_retroarchPid == null) return;

    DebugLogger.log('[AchievementWindowService] spawning notification: ${achievement.title}');
    try {
      await Process.start(_binary, [
        achievement.title,
        '${achievement.points}',
        '$_holdSeconds',
      ]);
    } catch (e) {
      DebugLogger.log('[AchievementWindowService] spawn error: $e');
    }
  }
}
