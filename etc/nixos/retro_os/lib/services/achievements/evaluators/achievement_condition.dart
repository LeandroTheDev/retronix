/// Console-native word size an [AchievementCondition] reads. [bytes] is how
/// many raw bytes to request over the wire; bit/nibble sizes still request a
/// single byte and mask it down in [extractValue].
enum MemorySize {
  bit0(1),
  bit1(1),
  bit2(1),
  bit3(1),
  bit4(1),
  bit5(1),
  bit6(1),
  bit7(1),
  nibbleLow(1),
  nibbleHigh(1),
  byte(1),
  word(2),
  tribyte(3),
  dword(4);

  const MemorySize(this.bytes);
  final int bytes;
}

/// A `${address}:${size.name}` key uniquely identifying one memory read,
/// shared between [AchievementService]'s polling snapshot and
/// [AchievementEvaluator]'s current/previous-value lookups so both sides
/// agree on what counts as "the same" read.
String memoryKey(int address, MemorySize size) => '$address:${size.name}';

/// Pulls the actual condition value out of the raw bytes RetroarchRamReader
/// returned — a plain byte/word/dword read just combines them big-endian,
/// but bit and nibble sizes need to mask/shift a single byte down first.
int extractValue(MemorySize size, List<int> rawBytes) => switch (size) {
  MemorySize.bit0 => rawBytes[0] & 0x1,
  MemorySize.bit1 => (rawBytes[0] >> 1) & 0x1,
  MemorySize.bit2 => (rawBytes[0] >> 2) & 0x1,
  MemorySize.bit3 => (rawBytes[0] >> 3) & 0x1,
  MemorySize.bit4 => (rawBytes[0] >> 4) & 0x1,
  MemorySize.bit5 => (rawBytes[0] >> 5) & 0x1,
  MemorySize.bit6 => (rawBytes[0] >> 6) & 0x1,
  MemorySize.bit7 => (rawBytes[0] >> 7) & 0x1,
  MemorySize.nibbleLow => rawBytes[0] & 0xF,
  MemorySize.nibbleHigh => (rawBytes[0] >> 4) & 0xF,
  MemorySize.byte ||
  MemorySize.word ||
  MemorySize.tribyte ||
  MemorySize.dword => rawBytes.fold(0, (acc, b) => (acc << 8) | b),
};

enum ComparisonOp { equals, notEquals, greaterThan, lessThan, greaterOrEqual, lessOrEqual }

bool satisfiesComparison(int value, ComparisonOp op, int target) => switch (op) {
  ComparisonOp.equals => value == target,
  ComparisonOp.notEquals => value != target,
  ComparisonOp.greaterThan => value > target,
  ComparisonOp.lessThan => value < target,
  ComparisonOp.greaterOrEqual => value >= target,
  ComparisonOp.lessOrEqual => value <= target,
};

/// What an [AchievementCondition] compares its reading against.
enum CompareTarget {
  /// A fixed number ([AchievementCondition.value]).
  literal,

  /// This same address/size's own value from the previous poll — e.g.
  /// "greaterThan + previousValue" means "this went up since last poll".
  previousValue,

  /// A *different* address/size's value ([AchievementCondition.compareAddress]
  /// / [AchievementCondition.compareSize]) — e.g. "current lives == current
  /// lives-at-last-checkpoint". Reads that address's current value, or its
  /// previous-poll value if [AchievementCondition.compareReadPrevious] is set.
  otherAddress,
}

/// How consecutive [AchievementCondition]s combine into one hit-counted unit.
/// Mirrors RetroAchievements' AndNext/OrNext flags: a run of [and]/[or]
/// conditions folds left-to-right into a single boolean, which then must
/// also hold alongside the next [none] ("terminal") condition for *that*
/// condition's hit count to advance. See [AchievementEvaluator] for the fold.
enum ChainType { none, and, or }

/// One memory check inside an achievement.
///
/// Non-[isResetIf], non-[isPauseIf] conditions are grouped into hit-counted
/// units by [chain] (see [ChainType]); all units must reach their target hit
/// count for the group (the achievement's core [Achievement.conditions], or
/// one of its [Achievement.altGroups]) to be satisfied.
class AchievementCondition {
  AchievementCondition({
    required this.address,
    required this.size,
    this.op,
    this.value,
    this.compareTarget = CompareTarget.literal,
    this.compareAddress,
    this.compareSize,
    this.compareReadPrevious = false,
    this.readPrevious = false,
    this.isResetIf = false,
    this.isPauseIf = false,
    this.isAddAddress = false,
    this.isAddSource = false,
    this.isSubSource = false,
    this.isAddHits = false,
    this.isSubHits = false,
    this.onlyOnChange = false,
    this.targetHits,
    this.chain = ChainType.none,
  }) : assert(
         isAddAddress || isAddSource || isSubSource || op != null,
         'op is required unless this condition is AddAddress/AddSource/SubSource '
         '(those contribute a value/pointer-offset rather than comparing anything)',
       ),
       assert(
         compareTarget != CompareTarget.literal || value != null || op == null,
         'value is required when compareTarget is literal',
       ),
       assert(
         compareTarget != CompareTarget.otherAddress || (compareAddress != null && compareSize != null),
         'compareAddress and compareSize are required when compareTarget is otherAddress',
       );

  /// 0-based RDRAM offset — same addressing RetroArch's own cheat/memory
  /// search uses, not the MIPS virtual address (0x80000000+).
  final int address;
  final MemorySize size;

  /// Null only for [isAddAddress]/[isAddSource]/[isSubSource] conditions -
  /// they contribute a pointer offset or accumulator value instead of
  /// comparing anything, so have no operator of their own.
  final ComparisonOp? op;

  /// The comparison target when [compareTarget] is [CompareTarget.literal].
  /// Ignored (and may be null) otherwise.
  final int? value;
  final CompareTarget compareTarget;

  /// The address/size read when [compareTarget] is [CompareTarget.otherAddress].
  final int? compareAddress;
  final MemorySize? compareSize;

  /// When [compareTarget] is [CompareTarget.otherAddress], read that
  /// address's previous-poll value instead of its current one.
  final bool compareReadPrevious;

  /// Read *this* condition's own address from the previous poll instead of
  /// the current one — e.g. "value-last-poll == 34" (RetroAchievements'
  /// delta-on-the-left-operand pattern), as opposed to [CompareTarget.previousValue]
  /// which puts the delta on the right (comparison target) side.
  final bool readPrevious;

  /// When true, this condition is a watchdog, not part of its group's hit
  /// units: if it's satisfied on a poll, every hit count in the *whole
  /// achievement* (core conditions and every alt group) is wiped that poll
  /// instead of counting toward unlocking.
  final bool isResetIf;

  /// When true, this condition is also a watchdog: if satisfied on a poll,
  /// no hit counts anywhere in the achievement advance *this poll*, but
  /// (unlike [isResetIf]) nothing already earned is lost.
  final bool isPauseIf;

  /// When true, this condition doesn't compare anything itself - it reads
  /// its own address/size as a pointer *base*, which [AchievementEvaluator]
  /// adds to the address (and, if set, [compareAddress]) of the very next
  /// condition in this group before that condition does its own read. Chains
  /// if that next condition is itself [isAddAddress] (double/triple pointer
  /// indirection) - see RetroAchievements' AddAddress flag.
  final bool isAddAddress;

  /// When true, this condition doesn't compare anything itself - its value
  /// is added into a running total ([AchievementEvaluator]'s per-poll
  /// accumulator) that gets folded into the *left* operand of the next
  /// non-[isAddAddress]/[isAddSource]/[isSubSource] condition in this group,
  /// then reset to zero. Chains with other [isAddSource]/[isSubSource]
  /// conditions in a row - see RetroAchievements' AddSource flag.
  final bool isAddSource;

  /// Same as [isAddSource] but subtracts from the running total instead of
  /// adding - RetroAchievements' SubSource flag.
  final bool isSubSource;

  /// When true, this condition's own hit tally (see [targetHits]) is folded
  /// into the *hit count* of the next non-[isAddHits]/[isSubHits] condition
  /// in this group that has an explicit [targetHits] - added on top of that
  /// condition's own tally before comparing to its target, then reset to
  /// zero. Unlike [isAddSource], this condition still evaluates and reports
  /// its own hit-counted unit *and* still contributes - RetroAchievements'
  /// AddHits flag. See [AchievementEvaluator] for the fold.
  final bool isAddHits;

  /// Same as [isAddHits] but subtracts from the running hit total instead of
  /// adding - RetroAchievements' SubHits flag.
  final bool isSubHits;

  /// When true, this condition only counts as satisfied on the poll where
  /// the comparison flips from false to true (e.g. "just picked up the
  /// item"), not on every poll where it happens to still hold (e.g.
  /// "currently has the item"). Only meaningful on a chain's terminal
  /// condition - see [chain].
  final bool onlyOnChange;

  /// How many separate polls this condition's unit must be satisfied on
  /// before it's considered done (e.g. "defeat 50 enemies" — each poll where
  /// the enemy-counter condition holds adds a hit). Once reached, it stays
  /// done (doesn't need to hold on every subsequent poll) unless reset by an
  /// [isResetIf] condition.
  ///
  /// Null (RetroAchievements' "no `.N.` suffix", *not* the same as 1) means
  /// this condition has no memory at all: it must hold on the *same* poll as
  /// every other condition in its unit, and stops counting as satisfied the
  /// instant it goes false again. This is the common case - most conditions
  /// (e.g. a level-ID check) aren't meant to latch in forever the first time
  /// they're incidentally true. Only meaningful on a chain's terminal
  /// condition - see [chain] - and for [isAddHits]/[isSubHits], where it
  /// still caps that condition's own tally (uncapped when null).
  final int? targetHits;

  /// How this condition combines with the next one - see [ChainType].
  final ChainType chain;

  static int _parseAddress(String value) {
    final hex = value.startsWith('0x') ? value.substring(2) : value;
    return int.parse(hex, radix: 16);
  }

  static String _formatAddress(int address) => '0x${address.toRadixString(16)}';

  factory AchievementCondition.fromJson(Map<String, dynamic> json) => AchievementCondition(
    address: _parseAddress(json['address'] as String),
    size: MemorySize.values.byName(json['size'] as String),
    op: json['op'] == null ? null : ComparisonOp.values.byName(json['op'] as String),
    value: json['value'] as int?,
    compareTarget: json['compareTarget'] == null
        ? CompareTarget.literal
        : CompareTarget.values.byName(json['compareTarget'] as String),
    compareAddress: json['compareAddress'] == null ? null : _parseAddress(json['compareAddress'] as String),
    compareSize: json['compareSize'] == null ? null : MemorySize.values.byName(json['compareSize'] as String),
    compareReadPrevious: json['compareReadPrevious'] as bool? ?? false,
    readPrevious: json['readPrevious'] as bool? ?? false,
    isResetIf: json['isResetIf'] as bool? ?? false,
    isPauseIf: json['isPauseIf'] as bool? ?? false,
    isAddAddress: json['isAddAddress'] as bool? ?? false,
    isAddSource: json['isAddSource'] as bool? ?? false,
    isSubSource: json['isSubSource'] as bool? ?? false,
    isAddHits: json['isAddHits'] as bool? ?? false,
    isSubHits: json['isSubHits'] as bool? ?? false,
    onlyOnChange: json['onlyOnChange'] as bool? ?? false,
    targetHits: json['targetHits'] as int?,
    chain: json['chain'] == null ? ChainType.none : ChainType.values.byName(json['chain'] as String),
  );

  Map<String, dynamic> toJson() => {
    'address': _formatAddress(address),
    'size': size.name,
    if (op != null) 'op': op!.name,
    if (value != null) 'value': value,
    if (compareTarget != CompareTarget.literal) 'compareTarget': compareTarget.name,
    if (compareAddress != null) 'compareAddress': _formatAddress(compareAddress!),
    if (compareSize != null) 'compareSize': compareSize!.name,
    if (compareReadPrevious) 'compareReadPrevious': compareReadPrevious,
    if (readPrevious) 'readPrevious': readPrevious,
    if (isResetIf) 'isResetIf': isResetIf,
    if (isPauseIf) 'isPauseIf': isPauseIf,
    if (isAddAddress) 'isAddAddress': isAddAddress,
    if (isAddSource) 'isAddSource': isAddSource,
    if (isSubSource) 'isSubSource': isSubSource,
    if (isAddHits) 'isAddHits': isAddHits,
    if (isSubHits) 'isSubHits': isSubHits,
    if (onlyOnChange) 'onlyOnChange': onlyOnChange,
    if (targetHits != null) 'targetHits': targetHits,
    if (chain != ChainType.none) 'chain': chain.name,
  };
}
