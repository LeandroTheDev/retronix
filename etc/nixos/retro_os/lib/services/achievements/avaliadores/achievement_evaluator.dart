import '../achievement.dart';
import 'achievement_condition.dart';

class _ConditionState {
  int hits = 0;
  bool wasSatisfied = false;
}

/// Tracks per-achievement hit counts and change-detection across polls, and
/// decides which achievements just unlocked on a given poll. Pure logic —
/// knows nothing about how memory values were obtained (see
/// RetroarchRamReader for that).
class AchievementEvaluator {
  final Map<String, List<_ConditionState>> _conditionState = {};
  final Set<String> _unlocked = {};

  bool isUnlocked(String achievementId) => _unlocked.contains(achievementId);

  /// Restores previously-unlocked achievement IDs (e.g. loaded from disk) so
  /// they don't fire again this session.
  void restoreUnlocked(Iterable<String> achievementIds) => _unlocked.addAll(achievementIds);

  /// Feeds one poll round of memory values in ([readValue] must return the
  /// value already read for that condition — this class does no I/O) and
  /// returns the achievements that transitioned from locked to unlocked on
  /// this call. Already-unlocked achievements are skipped entirely.
  List<Achievement> tick(
    List<Achievement> achievements,
    int? Function(AchievementCondition condition) readValue,
  ) {
    final newlyUnlocked = <Achievement>[];

    for (final achievement in achievements) {
      if (_unlocked.contains(achievement.id)) continue;

      final states = _conditionState.putIfAbsent(
        achievement.id,
        () => List.generate(achievement.conditions.length, (_) => _ConditionState()),
      );

      var allDone = true;
      for (var i = 0; i < achievement.conditions.length; i++) {
        final condition = achievement.conditions[i];
        final state = states[i];
        final value = readValue(condition);

        final satisfiedNow = value != null && satisfiesComparison(value, condition.op, condition.value);
        final countsAsHit = condition.onlyOnChange ? (satisfiedNow && !state.wasSatisfied) : satisfiedNow;
        state.wasSatisfied = satisfiedNow;

        if (countsAsHit && state.hits < condition.targetHits) state.hits++;
        if (state.hits < condition.targetHits) allDone = false;
      }

      if (allDone) {
        _unlocked.add(achievement.id);
        newlyUnlocked.add(achievement);
      }
    }

    return newlyUnlocked;
  }
}
