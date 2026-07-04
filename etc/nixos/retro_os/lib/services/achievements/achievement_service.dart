import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../utils/debug_logger.dart';
import '../../utils/devices.dart';
import 'achievement.dart';
import 'evaluators/achievement_condition.dart';
import 'evaluators/achievement_evaluator.dart';
import 'ram_reader/retroarch_ram_reader.dart';

/// Owns the poll loop tying [RetroarchRamReader] (memory access) and
/// [AchievementEvaluator] (unlock logic) together for one running game, plus
/// on-disk persistence of achievement definitions and unlocked progress.
///
/// Definitions are authored by hand (see [Achievement.fromJson] /
/// AchievementCondition.fromJson for the expected shape) and stored at
/// `<console>/Games/<game>/game_achievements.json` — right next to
/// `game_image.*`, since it's content that ships with the game rather than
/// app-managed state. There is no server, no account, and no hash lookup
/// involved. Unlocked progress, which *is* runtime state, is kept separately
/// in the app's own data dir.
class AchievementService {
  AchievementService._();
  static final instance = AchievementService._();

  final RetroarchRamReader _ramReader = RetroarchRamReader();
  final AchievementEvaluator _evaluator = AchievementEvaluator();

  final _unlockedController = StreamController<Achievement>.broadcast();
  Stream<Achievement> get unlocked => _unlockedController.stream;

  List<Achievement> _achievements = [];
  Timer? _pollTimer;
  String? _currentConsole;
  String? _currentGame;
  int _pollCount = 0;
  // int? _lastDebugStarCount;

  // Previous poll's readings, keyed the same way as the current poll's
  // snapshot in [_poll] — needed for CompareTarget.previousValue conditions
  // (e.g. "this went up since last poll"). Reset alongside everything else
  // in [stopWatching] so a new game never sees a stale delta baseline.
  Map<String, int> _previousSnapshot = {};

  static const _pollInterval = Duration(milliseconds: 500);

  /// Starts watching [console]/[game]'s achievements (previously-unlocked
  /// progress is restored first) against the RetroArch instance already
  /// running with `network_cmd_enable = "true"`.
  Future<void> startWatching(String console, String game) async {
    await stopWatching();
    _currentConsole = console;
    _currentGame = game;
    DebugLogger.log('[AchievementService] startWatching($console, $game)');

    _achievements = await _loadDefinitions(console, game);
    if (_achievements.isEmpty) {
      DebugLogger.log(
        '[AchievementService] no achievement definitions for $console/$game '
        '(expected at ${getGameAchievementsPath(console, game)})',
      );
      return;
    }

    final unlockedIds = await _loadUnlockedIds(console, game);
    _evaluator.restoreUnlocked(unlockedIds);
    await _ramReader.connect();

    _pollCount = 0;
    _schedulePoll();
    DebugLogger.log(
      '[AchievementService] watching ${_achievements.length} achievement(s) for $console/$game '
      '(${unlockedIds.length} already unlocked): ${_achievements.map((a) => a.title).join(', ')}',
    );
  }

  void _schedulePoll() {
    _pollTimer = Timer(_pollInterval, () async {
      await _poll();
      if (_pollTimer != null) _schedulePoll();
    });
  }

  Future<void> stopWatching() async {
    if (_pollTimer != null) {
      DebugLogger.log(
        '[AchievementService] stopWatching($_currentConsole, $_currentGame) after $_pollCount poll(s), '
        '${_evaluator.unlockedCount}/${_achievements.length} unlocked this session',
      );
    }
    _pollTimer?.cancel();
    _pollTimer = null;
    _ramReader.dispose();
    _achievements = [];
    _currentConsole = null;
    _currentGame = null;
    _previousSnapshot = {};
    // _lastDebugStarCount = null;
  }

  void dispose() {
    _pollTimer?.cancel();
    _ramReader.dispose();
    _unlockedController.close();
  }

  void debugTriggerUnlock(Achievement achievement) {
    _unlockedController.add(achievement);
  }

  Future<void> _poll() async {
    _pollCount++;

    // Sequential UDP round-trips are fine at this cadence for a handful of
    // conditions — deduped by memory key so achievements sharing a memory
    // address only cost one read per poll instead of one per condition.
    final currentSnapshot = <String, int>{};
    var attemptedReads = 0;
    var failedReads = 0;
    // N64 MIPS pointers are 4-byte big-endian values like 0x80HHMMLL, where
    // the high byte is always 0x80 (RDRAM prefix) and the RDRAM offset is the
    // lower 3 bytes (HHMMLL). RetroAchievements' tribyte AddAddress convention
    // reads from address+1 to skip that 0x80 byte and get the 3-byte RDRAM
    // offset directly. storeKey lets the caller separate the read address from
    // the snapshot key so the evaluator (which uses condition.address as the
    // key) still finds the correct value.
    Future<void> readIfNeeded(int address, MemorySize size, {String? storeKey}) async {
      final key = storeKey ?? memoryKey(address, size);
      if (currentSnapshot.containsKey(key)) return;
      attemptedReads++;
      final bytes = await _ramReader.readBytes(address, size.bytes);
      if (bytes != null) {
        currentSnapshot[key] = extractValue(size, bytes);
      } else {
        failedReads++;
      }
    }

    // For tribyte AddAddress conditions (N64 pointer reads): read from
    // address+1 to get the lower 3 bytes of the 4-byte MIPS pointer, but
    // store under the original address key so the evaluator finds it normally.
    Future<void> readPointerOrValue(int address, MemorySize size, {required bool isAddAddress}) async {
      if (isAddAddress && size == MemorySize.tribyte) {
        await readIfNeeded(address + 1, size, storeKey: memoryKey(address, size));
      } else {
        await readIfNeeded(address, size);
      }
    }

    // Pass 1: every condition's own literal address/size - this alone
    // resolves everything except AddAddress-indirected reads, since an
    // AddAddress condition's *own* address is always literal (it's what it
    // points to that's dynamic).
    for (final achievement in _achievements) {
      for (final condition in achievement.allConditions) {
        await readPointerOrValue(condition.address, condition.size, isAddAddress: condition.isAddAddress);
        if (condition.compareTarget == CompareTarget.otherAddress) {
          await readIfNeeded(condition.compareAddress!, condition.compareSize!);
        }
      }
    }

    // Pass 2: AddAddress indirection (RetroAchievements' "I:" flag) - the
    // condition right after an AddAddress reads from (pointer base + its own
    // configured address), and that base is only known after pass 1's read
    // of the AddAddress condition's own address. Mirrors the indirect-base
    // walk AchievementEvaluator does independently over the completed
    // snapshot; kept in sync with it, see achievement_evaluator.dart.
    for (final achievement in _achievements) {
      for (final group in achievement.conditionGroups) {
        int? indirectBase;
        for (final condition in group) {
          final address = condition.address + (indirectBase ?? 0);
          if (indirectBase != null) {
            await readPointerOrValue(address, condition.size, isAddAddress: condition.isAddAddress);
            if (condition.compareTarget == CompareTarget.otherAddress) {
              await readIfNeeded(condition.compareAddress! + indirectBase, condition.compareSize!);
            }
          }
          if (condition.isAddAddress) {
            final key = memoryKey(address, condition.size);
            indirectBase = (condition.readPrevious ? _previousSnapshot[key] : currentSnapshot[key]) ?? 0;
          } else {
            indirectBase = null;
          }
        }
      }
    }

    // A one-line heartbeat on the first poll (fast confirmation the loop and
    // RAM reads are alive at all) and every ~5s after (10 polls @ 500ms) -
    // loud enough to catch "nothing is happening" during manual testing
    // without flooding the log every 500ms.
    if (_pollCount == 1 || _pollCount % 10 == 0) {
      final String readStatus;
      if (attemptedReads == 0) {
        readStatus = 'no addresses to read';
      } else if (failedReads == attemptedReads) {
        readStatus = 'ALL $attemptedReads READ(S) FAILED - is RetroArch running with the ROM loaded '
            'and network_cmd_enable="true"?';
      } else if (failedReads > 0) {
        readStatus = '$failedReads/$attemptedReads read(s) failed';
      } else {
        readStatus = '$attemptedReads/$attemptedReads read(s) ok';
      }
      DebugLogger.log(
        '[AchievementService] poll #$_pollCount: $readStatus, '
        '${_evaluator.unlockedCount}/${_achievements.length} unlocked',
      );
    }

    // // DEBUG: force-read 0x33b21e alongside 0x33b266 to compare both star count addresses.
    // await readIfNeeded(0x33b21e, MemorySize.byte);

    // // DEBUG: log a_new_journey condition results only when the star count changes.
    // final debugAchievement = _achievements.where((a) => a.id == 'a_new_journey').firstOrNull;
    // if (debugAchievement != null) {
    //   final starCur = currentSnapshot[memoryKey(0x33b266, MemorySize.byte)];
    //   if (starCur != _lastDebugStarCount) {
    //     _lastDebugStarCount = starCur;
    //     final parts = <String>[];
    //     var allPass = true;
    //     for (var i = 0; i < debugAchievement.conditions.length; i++) {
    //       final c = debugAchievement.conditions[i];
    //       final cur = currentSnapshot[memoryKey(c.address, c.size)];
    //       final prev = _previousSnapshot[memoryKey(c.address, c.size)];
    //       final reading = c.readPrevious ? prev : cur;
    //       final bool? passes = (reading != null && c.op != null && c.value != null)
    //           ? satisfiesComparison(reading, c.op!, c.value!)
    //           : null;
    //       if (passes != true) allPass = false;
    //       final label = c.readPrevious ? 'd0x${c.address.toRadixString(16)}' : '0x${c.address.toRadixString(16)}';
    //       parts.add('#$i ${passes == null ? '?' : passes ? 'OK' : 'FAIL'} $label=${reading ?? 'null'}');
    //     }
    //     final knownStarCur = currentSnapshot[memoryKey(0x33b21e, MemorySize.byte)];
    //     DebugLogger.log(
    //       '[Achievement:a_new_journey] star changed → 0x33b266=$starCur | '
    //       '${parts.join(' | ')} | ${allPass ? '→ SHOULD UNLOCK' : '→ blocked'} '
    //       '| 0x33b21e=$knownStarCur',
    //     );
    //   }
    // }

    final newlyUnlocked = _evaluator.tick(
      _achievements,
      (address, size) => currentSnapshot[memoryKey(address, size)],
      (address, size) => _previousSnapshot[memoryKey(address, size)],
      onProgress: (achievement, progress) =>
          DebugLogger.log('[AchievementService] progress: ${achievement.title} $progress'),
    );
    _previousSnapshot = currentSnapshot;

    for (final achievement in newlyUnlocked) {
      DebugLogger.log('[AchievementService] unlocked: ${achievement.title} (+${achievement.points})');
      _unlockedController.add(achievement);
      await _persistUnlocked(achievement.id);
    }
  }

  // ── Persistence ───────────────────────────────────────────────────────────
  // Definitions live next to the game's own assets (see getGameAchievementsPath);
  // only unlocked progress lives in the app's data dir, mirroring the
  // Consoles/<console>/Games/<game> hierarchy so IDs never collide across consoles.

  String _progressDir() {
    if (Platform.isLinux) {
      final xdgDataHome = Platform.environment['XDG_DATA_HOME'] ?? '${Platform.environment['HOME']}/.local/share';
      return '$xdgDataHome/retro_os/achievements/progress';
    } else if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ?? '${Platform.environment['USERPROFILE']}\\AppData\\Roaming';
      return '$appData\\retro_os\\achievements\\progress';
    }
    return '${File(Platform.resolvedExecutable).parent.path}/achievements/progress';
  }

  String _progressFilePath(String console, String game) => '${_progressDir()}/$console/$game.json';

  Future<List<Achievement>> _loadDefinitions(String console, String game) async {
    final file = File(getGameAchievementsPath(console, game));
    if (!await file.exists()) return [];
    try {
      final list = json.decode(await file.readAsString()) as List;
      return list.map((e) => Achievement.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      DebugLogger.log('[AchievementService] failed to parse definitions for $console/$game: $e');
      return [];
    }
  }

  Future<Set<String>> _loadUnlockedIds(String console, String game) async {
    final file = File(_progressFilePath(console, game));
    if (!await file.exists()) return {};
    try {
      final list = json.decode(await file.readAsString()) as List;
      return list.cast<String>().toSet();
    } catch (e) {
      DebugLogger.log('[AchievementService] failed to parse progress for $console/$game: $e');
      return {};
    }
  }

  Future<void> _persistUnlocked(String achievementId) async {
    final console = _currentConsole;
    final game = _currentGame;
    if (console == null || game == null) return;
    final file = File(_progressFilePath(console, game));
    await file.parent.create(recursive: true);
    final current = await _loadUnlockedIds(console, game);
    current.add(achievementId);
    await file.writeAsString(json.encode(current.toList()));
  }
}
