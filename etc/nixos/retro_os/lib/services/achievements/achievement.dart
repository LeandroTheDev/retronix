import 'avaliadores/achievement_condition.dart';

class Achievement {
  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.points,
    required this.conditions,
  });

  final String id;
  final String title;
  final String description;
  final int points;

  /// All must hold at once (AND) for the achievement to unlock.
  final List<AchievementCondition> conditions;

  factory Achievement.fromJson(Map<String, dynamic> json) => Achievement(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String,
    points: json['points'] as int? ?? 0,
    conditions: (json['conditions'] as List)
        .map((c) => AchievementCondition.fromJson(c as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'points': points,
    'conditions': conditions.map((c) => c.toJson()).toList(),
  };
}
