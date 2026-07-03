import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../utils/debug_logger.dart';
import '../../utils/devices.dart';
import 'achievement.dart';
import 'avaliadores/achievement_evaluator.dart';
import 'leitor_ram/retroarch_ram_reader.dart';

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

  static const _pollInterval = Duration(milliseconds: 500);

  /// Starts watching [console]/[game]'s achievements (previously-unlocked
  /// progress is restored first) against the RetroArch instance already
  /// running with `network_cmd_enable = "true"`.
  Future<void> startWatching(String console, String game) async {
    await stopWatching();
    _currentConsole = console;
    _currentGame = game;

    _achievements = await _loadDefinitions(console, game);
    if (_achievements.isEmpty) {
      DebugLogger.log('[AchievementService] no achievement definitions for $console/$game');
      return;
    }

    _evaluator.restoreUnlocked(await _loadUnlockedIds(console, game));
    await _ramReader.connect();

    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
    DebugLogger.log('[AchievementService] watching ${_achievements.length} achievement(s) for $console/$game');
  }

  Future<void> stopWatching() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _ramReader.dispose();
    _achievements = [];
    _currentConsole = null;
    _currentGame = null;
  }

  void dispose() {
    _pollTimer?.cancel();
    _ramReader.dispose();
    _unlockedController.close();
  }

  Future<void> _poll() async {
    // Sequential UDP round-trips are fine at this cadence for a handful of
    // conditions — keyed by "address:size" so achievements sharing a memory
    // address (e.g. two conditions both watching the same counter) only cost
    // one read per poll instead of one per condition.
    final valuesByKey = <String, int?>{};
    for (final achievement in _achievements) {
      for (final condition in achievement.conditions) {
        final key = '${condition.address}:${condition.size.bytes}';
        if (valuesByKey.containsKey(key)) continue;
        final bytes = await _ramReader.readBytes(condition.address, condition.size.bytes);
        valuesByKey[key] = bytes == null ? null : _bigEndianValue(bytes);
      }
    }

    final newlyUnlocked = _evaluator.tick(
      _achievements,
      (condition) => valuesByKey['${condition.address}:${condition.size.bytes}'],
    );

    for (final achievement in newlyUnlocked) {
      DebugLogger.log('[AchievementService] unlocked: ${achievement.title} (+${achievement.points})');
      _unlockedController.add(achievement);
      await _persistUnlocked(achievement.id);
    }
  }

  int _bigEndianValue(List<int> bytes) {
    var value = 0;
    for (final byte in bytes) {
      value = (value << 8) | byte;
    }
    return value;
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
