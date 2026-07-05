import '../achievement.dart';
import 'achievement_condition.dart';

class _ConditionState {
  int hits = 0;
  bool wasSatisfied = false;
}

/// How close an achievement is to unlocking, reported via [AchievementEvaluator.tick]'s
/// `onProgress` callback. [doneUnits]/[totalUnits] cover the core
/// [Achievement.conditions]; [bestAltDoneUnits]/[bestAltTotalUnits] cover
/// whichever of [Achievement.altGroups] is currently furthest along (null if
/// the achievement has no alt groups) - the achievement still also needs
/// that alt group fully done, not just the core, to unlock.
class AchievementProgress {
  const AchievementProgress({
    required this.doneUnits,
    required this.totalUnits,
    this.bestAltDoneUnits,
    this.bestAltTotalUnits,
  });

  final int doneUnits;
  final int totalUnits;
  final int? bestAltDoneUnits;
  final int? bestAltTotalUnits;

  @override
  String toString() {
    final core = '$doneUnits/$totalUnits';
    if (bestAltDoneUnits == null) return core;
    return '$core (best alt group: $bestAltDoneUnits/$bestAltTotalUnits)';
  }
}

/// Per-achievement hit-count state: one slot per condition in the core
/// [Achievement.conditions] list, plus one slot per condition in each of
/// [Achievement.altGroups] (same shape, indexed the same way).
/// [AchievementCondition.isAddAddress]/[AchievementCondition.isAddSource]/
/// [AchievementCondition.isSubSource] conditions never use their slot -
/// they don't have their own hit count. [AchievementCondition.isAddHits]/
/// [AchievementCondition.isSubHits] conditions do use theirs, but only as a
/// tally feeding the next unit's hit count - see [AchievementEvaluator].
class _AchievementState {
  _AchievementState(int coreLength, List<int> altGroupLengths)
    : core = List.generate(coreLength, (_) => _ConditionState()),
      altGroups = altGroupLengths.map((length) => List.generate(length, (_) => _ConditionState())).toList();

  final List<_ConditionState> core;
  final List<List<_ConditionState>> altGroups;

  // Last progress reported through the onProgress callback, so AchievementService
  // only logs when something actually changed instead of every poll.
  int lastLoggedDone = 0;
  int? lastLoggedAltDone;

  void reset() {
    for (final state in core) {
      state.hits = 0;
      state.wasSatisfied = false;
    }
    for (final group in altGroups) {
      for (final state in group) {
        state.hits = 0;
        state.wasSatisfied = false;
      }
    }
  }
}

/// A 32-bit two's-complement wraparound add, matching rcheevos' AddSource/
/// SubSource accumulator arithmetic (`rc_typed_value_add` on an unsigned
/// 32-bit value - no overflow checking or saturation).
int _wrappingAdd32(int a, int b) => (a + b) & 0xFFFFFFFF;

/// Tracks per-achievement hit counts and change-detection across polls, and
/// decides which achievements just unlocked on a given poll. Pure logic —
/// knows nothing about how memory values were obtained (see
/// RetroarchRamReader for that).
class AchievementEvaluator {
  final Map<String, _AchievementState> _state = {};
  final Set<String> _unlocked = {};

  bool isUnlocked(String achievementId) => _unlocked.contains(achievementId);

  /// How many achievements are unlocked so far this session (including ones
  /// restored via [restoreUnlocked]) - handy for a one-line poll heartbeat
  /// log, see [AchievementService].
  int get unlockedCount => _unlocked.length;

  /// Restores previously-unlocked achievement IDs (e.g. loaded from disk) so
  /// they don't fire again this session.
  void restoreUnlocked(Iterable<String> achievementIds) => _unlocked.addAll(achievementIds);

  /// Feeds one poll round of memory values in — [currentValue] and
  /// [previousValue] return this/last poll's value for a given address/size,
  /// or null if it hasn't been read. Reads needed because of
  /// [AchievementCondition.isAddAddress] indirection must already be present
  /// too (see [AchievementService]'s two-pass poll) - this class does no I/O
  /// itself. [onProgress], if given, fires once per achievement whose
  /// [AchievementProgress] changed this poll (including drops back to zero
  /// from an isResetIf) - already-unlocked achievements are never reported.
  /// Returns the achievements that transitioned from locked to unlocked on
  /// this call; already-unlocked achievements are skipped entirely.
  List<Achievement> tick(
    List<Achievement> achievements,
    int? Function(int address, MemorySize size) currentValue,
    int? Function(int address, MemorySize size) previousValue, {
    void Function(Achievement achievement, AchievementProgress progress)? onProgress,
  }) {
    final newlyUnlocked = <Achievement>[];

    int? read(int address, MemorySize size, {required bool previous}) =>
        previous ? previousValue(address, size) : currentValue(address, size);

    // First pass over a group: resolves RetroAchievements' AddAddress
    // (pointer indirection - this condition's value becomes an address
    // *offset* added to the next condition's address) and AddSource/
    // SubSource (this condition's value folds into a running accumulator
    // that's added to the *left* operand of the next "real" condition, then
    // reset) — see achievement_evaluator's module docs / the RetroArch
    // rcheevos source this was ported from (condition.c, operand.c,
    // memref.c). Returns one satisfied-or-not bool per "real" condition;
    // AddAddress/AddSource/SubSource slots are left null since they don't
    // compare anything themselves.
    List<bool?> resolveGroup(List<AchievementCondition> conditions) {
      final resolved = List<bool?>.filled(conditions.length, null);
      int? indirectBase;
      var accumulator = 0;

      for (var i = 0; i < conditions.length; i++) {
        final condition = conditions[i];
        final address = condition.address + (indirectBase ?? 0);

        if (condition.isAddAddress) {
          indirectBase = read(address, condition.size, previous: condition.readPrevious) ?? 0;
          continue;
        }

        if (condition.isAddSource || condition.isSubSource) {
          final value = read(address, condition.size, previous: condition.readPrevious) ?? 0;
          accumulator = _wrappingAdd32(accumulator, condition.isSubSource ? -value : value);
          indirectBase = null;
          continue;
        }

        final rawLeft = read(address, condition.size, previous: condition.readPrevious);
        if (rawLeft == null) {
          resolved[i] = false;
        } else {
          final left = _wrappingAdd32(rawLeft, accumulator);
          final int? target;
          switch (condition.compareTarget) {
            case CompareTarget.literal:
              target = condition.value;
            case CompareTarget.previousValue:
              target = previousValue(address, condition.size);
            case CompareTarget.otherAddress:
              final compareAddress = condition.compareAddress! + (indirectBase ?? 0);
              target = read(compareAddress, condition.compareSize!, previous: condition.compareReadPrevious);
          }
          resolved[i] = target != null && satisfiesComparison(left, condition.op!, target);
        }

        accumulator = 0;
        indirectBase = null;
      }
      return resolved;
    }

    // Advances `state`'s hit tally for one poll and returns whether its unit
    // counts as satisfied *this poll*, applying RetroAchievements' hit-count
    // rule: with targetHits == null (no `.N.` suffix in the source), a
    // condition has no memory at all - it's satisfied only on polls where
    // rawSatisfied is true, full stop. With an explicit targetHits, hits
    // accumulate (capped at targetHits) while rawSatisfied holds, and once
    // the target is reached the unit stays satisfied forever after (until an
    // isResetIf wipes state.hits) even on polls where rawSatisfied is false.
    bool applyHitTracking(AchievementCondition condition, _ConditionState state, bool rawSatisfied) {
      final target = condition.targetHits;
      if (target == null) {
        state.wasSatisfied = rawSatisfied;
        return rawSatisfied;
      }
      final countsAsHit = condition.onlyOnChange ? (rawSatisfied && !state.wasSatisfied) : rawSatisfied;
      state.wasSatisfied = rawSatisfied;
      if (countsAsHit && state.hits < target) state.hits++;
      return state.hits >= target;
    }

    // AddHits/SubHits conditions don't report a unit satisfaction of their
    // own - only their tally matters (fed into the next real condition's hit
    // count, see below). Unlike applyHitTracking, an uncapped (target ==
    // null) tally still grows every poll rawSatisfied holds - that's the
    // "just keep counting, no threshold of its own" case, not "no memory".
    int tallyForAccumulator(AchievementCondition condition, _ConditionState state, bool rawSatisfied) {
      final target = condition.targetHits;
      if (rawSatisfied && (target == null || state.hits < target)) state.hits++;
      return state.hits;
    }

    // A group (the core condition list, or one alt group) is satisfied when
    // every hit-counted unit in it is satisfied. A unit is either one plain
    // condition, or a run of chain=and/or conditions folded left-to-right
    // into a single boolean that gates the next chain=none ("terminal")
    // condition - RetroAchievements' AndNext/OrNext. isResetIf/isPauseIf
    // conditions aren't part of any unit - they're watchdogs evaluated
    // separately below. isAddAddress/isAddSource/isSubSource conditions are
    // folded into [resolved] by [resolveGroup] instead of appearing here.
    // isAddHits/isSubHits conditions *do* have their own tally (see
    // tallyForAccumulator) but, like AddSource, fold into the next unit
    // rather than being one themselves - RetroAchievements' AddHits/SubHits.
    // Returns done/total unit counts alongside allDone for progress
    // reporting - see [AchievementProgress].
    ({bool allDone, int done, int total}) evaluateGroup(
      List<AchievementCondition> conditions,
      List<_ConditionState> states,
      List<bool?> resolved,
    ) {
      var allDone = true;
      var done = 0;
      var total = 0;
      var addHitsAccumulator = 0;
      var i = 0;
      while (i < conditions.length) {
        final condition = conditions[i];
        if (condition.isResetIf || condition.isPauseIf || condition.isTrigger || resolved[i] == null) {
          i++;
          continue;
        }

        if (condition.isResetNextIf) {
          if (resolved[i]!) {
            for (var j = i + 1; j < conditions.length; j++) {
              final next = conditions[j];
              if (!next.isResetIf && !next.isPauseIf && !next.isTrigger &&
                  !next.isResetNextIf && !next.isAddAddress &&
                  !next.isAddSource && !next.isSubSource &&
                  next.chain == ChainType.none && resolved[j] != null) {
                states[j].hits = 0;
                break;
              }
            }
          }
          i++;
          continue;
        }

        if (condition.isAddHits || condition.isSubHits) {
          final tally = tallyForAccumulator(condition, states[i], resolved[i]!);
          addHitsAccumulator += condition.isSubHits ? -tally : tally;
          i++;
          continue;
        }

        bool rawSatisfied;
        if (condition.chain == ChainType.none) {
          rawSatisfied = resolved[i]!;
        } else {
          var chainResult = true;
          while (i < conditions.length && conditions[i].chain != ChainType.none) {
            final linked = conditions[i];
            final linkedSatisfied = resolved[i] ?? false;
            chainResult = linked.chain == ChainType.and ? (chainResult && linkedSatisfied) : (chainResult || linkedSatisfied);
            i++;
          }
          if (i >= conditions.length) {
            // Malformed chain (no terminal condition to attach to) - can't
            // be satisfied.
            allDone = false;
            break;
          }
          rawSatisfied = chainResult && (resolved[i] ?? false);
        }

        final terminal = conditions[i];
        final state = states[i];
        var unitSatisfied = applyHitTracking(terminal, state, rawSatisfied);

        // AddHits/SubHits only combines with a condition that itself has an
        // explicit hit target - a target-less (transient) condition can't
        // absorb a hit total, so the accumulator carries forward untouched
        // to whatever consumes it next.
        if (addHitsAccumulator != 0 && terminal.targetHits != null) {
          final combined = state.hits + addHitsAccumulator;
          unitSatisfied = combined >= terminal.targetHits!;
          addHitsAccumulator = 0;
        }

        total++;
        if (unitSatisfied) {
          done++;
        } else {
          allDone = false;
        }
        i++;
      }
      return (allDone: allDone, done: done, total: total);
    }

    // Unlike isResetIf/onlyOnChange conditions, isPauseIf freezes every hit
    // count in the group for this poll instead of advancing or wiping them -
    // same as rcheevos' PauseIf flag.
    bool groupPaused(List<AchievementCondition> conditions, List<bool?> resolved) {
      for (var i = 0; i < conditions.length; i++) {
        if (conditions[i].isPauseIf && (resolved[i] ?? false)) return true;
      }
      return false;
    }

    bool groupResetTriggered(List<AchievementCondition> conditions, List<bool?> resolved) {
      for (var i = 0; i < conditions.length; i++) {
        if (conditions[i].isResetIf && (resolved[i] ?? false)) return true;
      }
      return false;
    }

    // All isTrigger conditions in a group must be currently satisfied at the
    // moment the achievement would fire, or the unlock is blocked. Unlike
    // regular conditions, Trigger conditions don't contribute to done/total.
    bool allTriggersActive(List<AchievementCondition> conditions, List<bool?> resolved) {
      for (var i = 0; i < conditions.length; i++) {
        if (conditions[i].isTrigger && !(resolved[i] ?? false)) return false;
      }
      return true;
    }

    ({bool allDone, int done, int total}) evaluateGroupOrFrozen(
      List<AchievementCondition> conditions,
      List<_ConditionState> states,
      List<bool?> resolved,
    ) {
      if (!groupPaused(conditions, resolved)) return evaluateGroup(conditions, states, resolved);
      var done = 0;
      var total = 0;
      var allDone = true;
      for (var i = 0; i < conditions.length; i++) {
        final condition = conditions[i];
        if (condition.isResetIf ||
            condition.isPauseIf ||
            condition.isTrigger ||
            condition.isResetNextIf ||
            condition.isAddHits ||
            condition.isSubHits ||
            condition.chain != ChainType.none ||
            resolved[i] == null) {
          continue;
        }
        total++;
        final target = condition.targetHits;
        final satisfied = target == null || states[i].hits >= target;
        if (satisfied) {
          done++;
        } else {
          allDone = false;
        }
      }
      return (allDone: allDone, done: done, total: total);
    }

    for (final achievement in achievements) {
      if (_unlocked.contains(achievement.id)) continue;

      final state = _state.putIfAbsent(
        achievement.id,
        () => _AchievementState(achievement.conditions.length, achievement.altGroups.map((g) => g.length).toList()),
      );

      final resolvedCore = resolveGroup(achievement.conditions);
      final resolvedAlts = achievement.altGroups.map(resolveGroup).toList();

      // ResetIf is a global watchdog regardless of which group it's in: if
      // any is satisfied this poll, every hit count in the achievement
      // (core and every alt group) is wiped and it can't unlock this poll -
      // same as rcheevos' ResetIf flag.
      var resetTriggered = groupResetTriggered(achievement.conditions, resolvedCore);
      for (var g = 0; g < achievement.altGroups.length; g++) {
        if (groupResetTriggered(achievement.altGroups[g], resolvedAlts[g])) resetTriggered = true;
      }
      if (resetTriggered) {
        state.reset();
        if (onProgress != null && (state.lastLoggedDone != 0 || (state.lastLoggedAltDone ?? 0) != 0)) {
          state.lastLoggedDone = 0;
          state.lastLoggedAltDone = achievement.altGroups.isEmpty ? null : 0;
          onProgress(achievement, AchievementProgress(doneUnits: 0, totalUnits: state.core.length));
        }
        continue;
      }

      final coreResult = evaluateGroupOrFrozen(achievement.conditions, state.core, resolvedCore);

      var altDone = achievement.altGroups.isEmpty;
      var bestAltDone = -1;
      var bestAltTotal = 0;
      final completedAltIndices = <int>[];
      for (var g = 0; g < achievement.altGroups.length; g++) {
        final altResult = evaluateGroupOrFrozen(achievement.altGroups[g], state.altGroups[g], resolvedAlts[g]);
        if (altResult.allDone) {
          altDone = true;
          completedAltIndices.add(g);
        }
        if (altResult.done > bestAltDone) {
          bestAltDone = altResult.done;
          bestAltTotal = altResult.total;
        }
      }

      if (onProgress != null &&
          (coreResult.done != state.lastLoggedDone || (achievement.altGroups.isNotEmpty && bestAltDone != state.lastLoggedAltDone))) {
        state.lastLoggedDone = coreResult.done;
        state.lastLoggedAltDone = achievement.altGroups.isEmpty ? null : bestAltDone;
        onProgress(
          achievement,
          AchievementProgress(
            doneUnits: coreResult.done,
            totalUnits: coreResult.total,
            bestAltDoneUnits: achievement.altGroups.isEmpty ? null : bestAltDone,
            bestAltTotalUnits: achievement.altGroups.isEmpty ? null : bestAltTotal,
          ),
        );
      }

      if (coreResult.allDone && altDone) {
        var triggersOk = allTriggersActive(achievement.conditions, resolvedCore);
        if (triggersOk && achievement.altGroups.isNotEmpty) {
          // At least one completing alt group must also have its Triggers active.
          triggersOk = completedAltIndices.any(
            (g) => allTriggersActive(achievement.altGroups[g], resolvedAlts[g]),
          );
        }
        if (triggersOk) {
          _unlocked.add(achievement.id);
          newlyUnlocked.add(achievement);
        }
      }
    }

    return newlyUnlocked;
  }
}
