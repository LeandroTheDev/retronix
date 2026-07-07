class GameInfo {
  const GameInfo({
    required this.executable,
    this.launcher = const [],
    this.env = const {},
    this.args = const [],
  });

  /// Relative path to the executable from the game root directory.
  final String executable;

  /// Command(s) prepended before the executable, e.g. ["wine"] or ["box64", "wine"].
  final List<String> launcher;

  /// Environment variables injected into the process before launch.
  final Map<String, String> env;

  /// Arguments appended after the executable.
  final List<String> args;

  factory GameInfo.fromJson(Map<String, dynamic> json) => GameInfo(
        executable: json['executable'] as String,
        launcher: (json['launcher'] as List<dynamic>?)?.cast<String>() ?? const [],
        env: (json['env'] as Map<String, dynamic>?)?.cast<String, String>() ?? const {},
        args: (json['args'] as List<dynamic>?)?.cast<String>() ?? const [],
      );

  /// Full command list ready for [Process.start]: [launcher..., executable, args...]
  List<String> buildCommand() => [...launcher, executable, ...args];
}
