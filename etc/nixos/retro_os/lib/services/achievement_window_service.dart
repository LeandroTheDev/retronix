import 'dart:async';
import 'dart:io';
import 'achievements/achievement.dart';
import 'achievements/achievement_service.dart';
import '../utils/debug_logger.dart';

/// Handles the X11 window-stacking dance needed to show achievement
/// notifications on top of a fullscreen RetroArch process.
///
/// When a game session is active and an achievement unlocks:
///   1. Raises the Flutter window via `xdotool windowraise` — no focus
///      change, so RetroArch keeps receiving gamepad input and the game
///      does NOT pause (pause_nonactive only reacts to X11 focus, not Z-order).
///   2. After all queued notifications have been shown (tracked via ref-count),
///      raises the RetroArch window back to the top.
///
/// When no session is active (game not running), the
/// [AchievementNotificationOverlay] widget handles everything within the
/// Flutter window itself — this service does nothing.
class AchievementWindowService {
  AchievementWindowService._();
  static final instance = AchievementWindowService._();

  StreamSubscription<Achievement>? _sub;

  int? _retroarchPid;

  // Number of notifications currently being shown. Window is lowered back
  // to RetroArch only when this reaches zero.
  int _activeCount = 0;

  static const _holdDuration = Duration(seconds: 4);

  void init() {
    _sub = AchievementService.instance.unlocked.listen(_onUnlocked);
  }

  /// Call immediately after the RetroArch process is started.
  void startSession(int retroarchPid) {
    _retroarchPid = retroarchPid;
    _activeCount = 0;
    DebugLogger.log('[AchievementWindowService] session started, retroarch pid=$retroarchPid');
  }

  /// Call after the RetroArch process exits.
  void stopSession() {
    DebugLogger.log('[AchievementWindowService] session stopped');
    _retroarchPid = null;
    _activeCount = 0;
  }

  void dispose() {
    _sub?.cancel();
  }

  Future<void> _onUnlocked(Achievement achievement) async {
    final retroPid = _retroarchPid;
    if (retroPid == null) return; // not in a game session — overlay handles it

    _activeCount++;

    if (_activeCount == 1) {
      // First notification in this batch: raise Flutter on top of RetroArch.
      // windowraise changes the stacking order only — _NET_ACTIVE_WINDOW stays
      // as the RetroArch window, gamepad input is unaffected.
      await _raiseWindow(pid); // pid == this Flutter process's PID (dart:io)
    }

    // Wait for this notification's hold time, then decrement.
    await Future.delayed(_holdDuration);
    _activeCount--;

    if (_activeCount == 0) {
      // All notifications done: put RetroArch back on top.
      await _raiseWindow(retroPid);
    }
  }

  Future<void> _raiseWindow(int targetPid) async {
    try {
      final result = await Process.run('xdotool', ['search', '--pid', '$targetPid', 'windowraise']);
      DebugLogger.log('[AchievementWindowService] windowraise(pid=$targetPid): exit=${result.exitCode}');
      if (result.exitCode != 0) {
        DebugLogger.log('[AchievementWindowService] windowraise stderr: ${result.stderr}');
      }
    } catch (e) {
      DebugLogger.log('[AchievementWindowService] windowraise(pid=$targetPid) exception: $e');
    }
  }
}
