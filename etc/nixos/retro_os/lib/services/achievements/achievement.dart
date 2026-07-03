import 'evaluators/achievement_condition.dart';

class Achievement {
  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.points,
    required this.conditions,
    this.altGroups = const [],
  });

  final String id;
  final String title;
  final String description;
  final int points;

  /// All must hold at once (AND) for the achievement to unlock.
  final List<AchievementCondition> conditions;

  /// RetroAchievements-style alt groups: [conditions] must hold *and* at
  /// least one of these groups must also fully hold (OR across groups, AND
  /// within each). Empty for achievements that don't need one - the common
  /// case.
  final List<List<AchievementCondition>> altGroups;

  /// Every condition across [conditions] and [altGroups], e.g. for figuring
  /// out which memory addresses need polling.
  Iterable<AchievementCondition> get allConditions sync* {
    yield* conditions;
    for (final group in altGroups) {
      yield* group;
    }
  }

  /// [conditions] and each of [altGroups], as independent lists - each is
  /// its own hit-tracking/AddAddress-base/AddSource-accumulator scope (see
  /// [AchievementEvaluator]).
  List<List<AchievementCondition>> get conditionGroups => [conditions, ...altGroups];

  factory Achievement.fromJson(Map<String, dynamic> json) => Achievement(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String,
    points: json['points'] as int? ?? 0,
    conditions: (json['conditions'] as List)
        .map((c) => AchievementCondition.fromJson(c as Map<String, dynamic>))
        .toList(),
    altGroups: (json['altGroups'] as List?)?.map((group) =>
            (group as List).map((c) => AchievementCondition.fromJson(c as Map<String, dynamic>)).toList())
        .toList() ?? const [],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'points': points,
    'conditions': conditions.map((c) => c.toJson()).toList(),
    if (altGroups.isNotEmpty)
      'altGroups': altGroups.map((group) => group.map((c) => c.toJson()).toList()).toList(),
  };
}
