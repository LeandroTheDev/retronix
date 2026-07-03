/// Console-native word size an [AchievementCondition] reads, and how many
/// bytes that means over the wire.
enum MemorySize {
  byte(1),
  word(2),
  dword(4);

  const MemorySize(this.bytes);
  final int bytes;
}

enum ComparisonOp { equals, notEquals, greaterThan, lessThan, greaterOrEqual, lessOrEqual }

bool satisfiesComparison(int value, ComparisonOp op, int target) => switch (op) {
  ComparisonOp.equals => value == target,
  ComparisonOp.notEquals => value != target,
  ComparisonOp.greaterThan => value > target,
  ComparisonOp.lessThan => value < target,
  ComparisonOp.greaterOrEqual => value >= target,
  ComparisonOp.lessOrEqual => value <= target,
};

/// One memory check inside an achievement. All of an achievement's
/// conditions must hold at once (AND) for it to count as satisfied on a
/// given poll.
class AchievementCondition {
  const AchievementCondition({
    required this.address,
    required this.size,
    required this.op,
    required this.value,
    this.onlyOnChange = false,
    this.targetHits = 1,
  });

  /// 0-based RDRAM offset — same addressing RetroArch's own cheat/memory
  /// search uses, not the MIPS virtual address (0x80000000+).
  final int address;
  final MemorySize size;
  final ComparisonOp op;
  final int value;

  /// When true, this condition only counts as satisfied on the poll where
  /// the comparison flips from false to true (e.g. "just picked up the
  /// item"), not on every poll where it happens to still hold (e.g.
  /// "currently has the item").
  final bool onlyOnChange;

  /// How many separate polls this condition must be satisfied on before
  /// it's considered done (e.g. "defeat 50 enemies" — each poll where the
  /// enemy-counter condition holds adds a hit).
  final int targetHits;

  static int _parseAddress(String value) {
    final hex = value.startsWith('0x') ? value.substring(2) : value;
    return int.parse(hex, radix: 16);
  }

  factory AchievementCondition.fromJson(Map<String, dynamic> json) => AchievementCondition(
    address: _parseAddress(json['address'] as String),
    size: MemorySize.values.byName(json['size'] as String),
    op: ComparisonOp.values.byName(json['op'] as String),
    value: json['value'] as int,
    onlyOnChange: json['onlyOnChange'] as bool? ?? false,
    targetHits: json['targetHits'] as int? ?? 1,
  );

  Map<String, dynamic> toJson() => {
    'address': '0x${address.toRadixString(16)}',
    'size': size.name,
    'op': op.name,
    'value': value,
    if (onlyOnChange) 'onlyOnChange': onlyOnChange,
    if (targetHits != 1) 'targetHits': targetHits,
  };
}
