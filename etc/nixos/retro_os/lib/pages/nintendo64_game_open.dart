import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/achievements/achievement.dart';
import '../services/achievements/achievement_service.dart';
import '../services/achievement_window_service.dart';
import '../services/gamepad_service.dart';
import '../utils/debug_logger.dart';
import '../utils/devices.dart';
import '../utils/settings_service.dart';
import '../utils/app_localizations.dart';
import '../utils/locale_service.dart';

const _windowChannel = MethodChannel('app/window');

class Nintendo64GameOpen extends StatefulWidget {
  const Nintendo64GameOpen({super.key, required this.gameName});

  final String gameName;

  @override
  State<Nintendo64GameOpen> createState() => _Nintendo64GameOpenState();
}

class _Nintendo64GameOpenState extends State<Nintendo64GameOpen> {
  bool _showLoadingUi = true;

  // ── HUD state ──────────────────────────────────────────────────────────────
  DateTime? _sessionStart;
  int _savedPlaytimeSecs = 0;
  String _clockString = '';
  Duration _sessionDuration = Duration.zero;
  double? _cpuPercent;
  double? _gpuPercent;
  final List<Achievement> _sessionUnlocked = [];
  StreamSubscription<Achievement>? _achievementSub;
  Timer? _clockTimer;
  Timer? _statsTimer;

  // ── Input ──────────────────────────────────────────────────────────────────
  int? _retroarchPid;
  Timer? _exitHoldTimer;
  bool _windowFocused = false;
  bool _lHeld = false;
  bool _rHeld = false;

  @override
  void initState() {
    super.initState();
    _openGame();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _statsTimer?.cancel();
    _achievementSub?.cancel();
    super.dispose();
  }

  // ── Playtime persistence ───────────────────────────────────────────────────
  Future<int> _loadSavedPlaytime() async {
    final file = File(getGamePlaytimePath('Nintendo 64', widget.gameName));
    if (!await file.exists()) return 0;
    try {
      final data = json.decode(await file.readAsString()) as Map<String, dynamic>;
      return (data['total_playtime_seconds'] as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _savePlaytime() async {
    final start = _sessionStart;
    if (start == null) return;
    final sessionSecs = DateTime.now().difference(start).inSeconds;
    final total = _savedPlaytimeSecs + sessionSecs;
    final file = File(getGamePlaytimePath('Nintendo 64', widget.gameName));
    await file.parent.create(recursive: true);
    await file.writeAsString(json.encode({'total_playtime_seconds': total}));
    DebugLogger.log('[Nintendo64GameOpen] saved playtime: ${total}s total');
  }

  // ── System stats ───────────────────────────────────────────────────────────
  Future<double?> _readCpuPercent() async {
    List<int>? parse(String content) {
      try {
        final line = content.split('\n').first;
        return line.split(RegExp(r'\s+')).skip(1).take(10).map(int.parse).toList();
      } catch (_) {
        return null;
      }
    }

    try {
      final s1 = await File('/proc/stat').readAsString();
      await Future.delayed(const Duration(seconds: 1));
      final s2 = await File('/proc/stat').readAsString();
      final p1 = parse(s1);
      final p2 = parse(s2);
      if (p1 == null || p2 == null) return null;
      final totalDelta = p2.reduce((a, b) => a + b) - p1.reduce((a, b) => a + b);
      if (totalDelta == 0) return 0.0;
      return (1.0 - (p2[3] - p1[3]) / totalDelta) * 100;
    } catch (_) {
      return null;
    }
  }

  Future<double?> _readGpuPercent() async {
    // AMD
    try {
      final r = await Process.run(
        'sh', ['-c', 'cat /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | head -1'],
      );
      if (r.exitCode == 0) {
        final v = double.tryParse((r.stdout as String).trim());
        if (v != null) return v;
      }
    } catch (_) {}
    // NVIDIA
    try {
      final r = await Process.run(
        'nvidia-smi', ['--query-gpu=utilization.gpu', '--format=csv,noheader,nounits'],
      );
      if (r.exitCode == 0) {
        final v = double.tryParse((r.stdout as String).trim());
        if (v != null) return v;
      }
    } catch (_) {}
    // Raspberry Pi V3D — drm_fdinfo cumulative ns delta over 1s
    final pid = _retroarchPid;
    if (pid != null) return _readV3dPercent(pid);
    return null;
  }

  Future<double?> _readV3dPercent(int pid) async {
    Future<int?> readRenderNs() async {
      try {
        final fdinfoDir = Directory('/proc/$pid/fdinfo');
        if (!await fdinfoDir.exists()) return null;
        await for (final entry in fdinfoDir.list()) {
          try {
            final content = await File(entry.path).readAsString();
            if (!content.contains('drm-driver:') || !content.contains('v3d')) continue;
            for (final line in content.split('\n')) {
              final m = RegExp(r'^drm-engine-render:\s+(\d+) ns$').firstMatch(line);
              if (m != null) { return int.parse(m.group(1)!); }
            }
          } catch (_) {}
        }
      } catch (_) {}
      return null;
    }

    final t1 = DateTime.now();
    final ns1 = await readRenderNs();
    if (ns1 == null) return null;
    await Future.delayed(const Duration(seconds: 1));
    final t2 = DateTime.now();
    final ns2 = await readRenderNs();
    if (ns2 == null) return null;

    final elapsedNs = t2.difference(t1).inMicroseconds * 1000;
    if (elapsedNs <= 0) return null;
    return ((ns2 - ns1) / elapsedNs * 100).clamp(0.0, 100.0);
  }

  Future<void> _updateStats() async {
    final cpu = await _readCpuPercent();
    final gpu = await _readGpuPercent();
    if (mounted) setState(() { _cpuPercent = cpu; _gpuPercent = gpu; });
  }

  // ── HUD init ───────────────────────────────────────────────────────────────
  Future<void> _startHud() async {
    _savedPlaytimeSecs = await _loadSavedPlaytime();
    _sessionStart = DateTime.now();

    _achievementSub = AchievementService.instance.unlocked.listen((a) {
      if (mounted) setState(() => _sessionUnlocked.add(a));
    });

    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        _clockString = '${now.hour.toString().padLeft(2, '0')}:'
            '${now.minute.toString().padLeft(2, '0')}:'
            '${now.second.toString().padLeft(2, '0')}';
        _sessionDuration = now.difference(_sessionStart!);
      });
    });

    // CPU read takes ~1s internally, so 3s period avoids overlapping calls
    _statsTimer = Timer.periodic(const Duration(seconds: 3), (_) => _updateStats());
    _updateStats();

    final now = DateTime.now();
    if (mounted) {
      setState(() {
        _clockString = '${now.hour.toString().padLeft(2, '0')}:'
            '${now.minute.toString().padLeft(2, '0')}:'
            '${now.second.toString().padLeft(2, '0')}';
      });
    }
  }

  // ── Game launch ────────────────────────────────────────────────────────────
  Future<void> _openGame() async {
    DebugLogger.log('[Nintendo64GameOpen] opening game: ${widget.gameName}');

    final romPath = await getGameFilePath('Nintendo 64', widget.gameName);
    final l = AppLocalizations(LocaleService.instance.locale);

    if (romPath == null) {
      DebugLogger.log('[Nintendo64GameOpen] ROM not found for: ${widget.gameName}');
      if (mounted) Navigator.pop(context, l.romNotFound(widget.gameName));
      return;
    }

    final corePath = await SettingsService.instance.n64CorePath();
    if (!File(corePath).existsSync()) {
      DebugLogger.log('[Nintendo64GameOpen] core not found: $corePath');
      if (mounted) Navigator.pop(context, l.coreNotFoundPath(corePath));
      return;
    }

    try {
      await SettingsService.instance.applyN64CoreOptions();
      final overridePath = await SettingsService.instance.applyRetroarchOverrides();

      DebugLogger.log('[Nintendo64GameOpen] core: $corePath');
      DebugLogger.log('[Nintendo64GameOpen] ROM: $romPath');

      final process = await Process.start(
        'retroarch',
        ['-L', corePath, '--appendconfig=$overridePath', '--verbose', romPath],
        environment: {
          ...Platform.environment,
          'MESA_GL_VERSION_OVERRIDE': '3.3COMPAT',
          'MESA_GLSL_VERSION_OVERRIDE': '330',
        },
      );
      DebugLogger.log('[Nintendo64GameOpen] retroarch launched (pid: ${process.pid})');
      _retroarchPid = process.pid;
      GamepadService.instance.setGameRunning(true);

      await AchievementService.instance.startWatching('Nintendo 64', widget.gameName);
      AchievementWindowService.instance.startSession(process.pid);

      void onRetroarchLine(String line, String src) {
        DebugLogger.log('[retroarch:$src] $line');
        if (_showLoadingUi && line.contains('Init new dynarec')) {
          DebugLogger.log('[Nintendo64GameOpen] dynarec ready — dropping loading UI');
          if (mounted) {
            setState(() => _showLoadingUi = false);
            _startHud();
          }
        }
      }

      process.stdout.transform(const SystemEncoding().decoder).listen(
        (line) => onRetroarchLine(line, 'stdout'),
      );
      process.stderr.transform(const SystemEncoding().decoder).listen(
        (line) => onRetroarchLine(line, 'stderr'),
      );

      final exitSubs = _watchExitHold(process);

      final exitCode = await process.exitCode;
      for (final s in exitSubs) s.cancel();
      _exitHoldTimer?.cancel();
      await _savePlaytime();
      GamepadService.instance.setGameRunning(false);
      DebugLogger.log('[Nintendo64GameOpen] retroarch exited with code: $exitCode');
      await AchievementService.instance.stopWatching();
      AchievementWindowService.instance.stopSession();

      if (!mounted) return;
      if (exitCode != 0 && exitCode != -15) {
        Navigator.pop(context, l.retroarchExitError(exitCode));
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      DebugLogger.log('[Nintendo64GameOpen] failed to launch retroarch: $e');
      await _savePlaytime();
      GamepadService.instance.setGameRunning(false);
      await AchievementService.instance.stopWatching();
      AchievementWindowService.instance.stopSession();
      if (mounted) Navigator.pop(context, l.retroarchLaunchError(e));
    }
  }

  // ── Input ──────────────────────────────────────────────────────────────────
  Future<void> _toggleWindowFocus() async {
    _windowFocused = !_windowFocused;
    DebugLogger.log('[Nintendo64GameOpen] L+R — windowFocused: $_windowFocused');
    if (_windowFocused) {
      await _windowChannel.invokeMethod('forceFocus');
    } else {
      await _windowChannel.invokeMethod('lowerWindow');
      final pid = _retroarchPid;
      if (pid != null) {
        await Process.run('xdotool', ['search', '--pid', '$pid', 'windowfocus', '--sync']);
        DebugLogger.log('[Nintendo64GameOpen] xdotool focused retroarch (pid: $pid)');
      }
    }
  }

  List<StreamSubscription<GamepadAction>> _watchExitHold(Process process) {
    final downSub = GamepadService.instance.buttonDown.listen((action) {
      if (action == GamepadAction.start) {
        _exitHoldTimer?.cancel();
        _exitHoldTimer = Timer(const Duration(seconds: 5), () {
          DebugLogger.log('[Nintendo64GameOpen] start held 5s — killing retroarch');
          process.kill();
        });
      } else if (action == GamepadAction.l) {
        _lHeld = true;
        DebugLogger.log('[Nintendo64GameOpen] L down (rHeld=$_rHeld)');
        if (_rHeld) _toggleWindowFocus();
      } else if (action == GamepadAction.r) {
        _rHeld = true;
        DebugLogger.log('[Nintendo64GameOpen] R down (lHeld=$_lHeld)');
        if (_lHeld) _toggleWindowFocus();
      }
    });
    final upSub = GamepadService.instance.buttonUp.listen((action) {
      if (action == GamepadAction.start) _exitHoldTimer?.cancel();
      if (action == GamepadAction.l) {
        _lHeld = false;
        DebugLogger.log('[Nintendo64GameOpen] L up');
      }
      if (action == GamepadAction.r) {
        _rHeld = false;
        DebugLogger.log('[Nintendo64GameOpen] R up');
      }
    });
    return [downSub, upSub];
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _fmt(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    if (_showLoadingUi) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white54),
              const SizedBox(height: 32),
              Text(
                l.openingGame(widget.gameName),
                style: const TextStyle(color: Colors.white54, fontSize: 20, letterSpacing: 3),
              ),
              const SizedBox(height: 16),
              Text(
                l.holdStartToExit,
                style: const TextStyle(color: Colors.white24, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final totalSecs = _savedPlaytimeSecs + _sessionDuration.inSeconds;
    final totalAch = AchievementService.instance.totalAchievements;
    final unlockedAch = AchievementService.instance.totalUnlocked;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Clock
            Text(
              _clockString,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 72,
                fontWeight: FontWeight.w200,
                letterSpacing: 8,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 24),

            // Session / Total playtime
            Row(
              children: [
                Expanded(child: _timeBox('SESSÃO', _fmt(_sessionDuration))),
                const SizedBox(width: 16),
                Expanded(child: _timeBox('TOTAL', _fmt(Duration(seconds: totalSecs)))),
              ],
            ),
            const SizedBox(height: 20),

            // Achievements
            if (totalAch > 0) _achievementsCard(unlockedAch, totalAch),

            const Spacer(),

            // CPU / GPU bars
            Row(
              children: [
                Expanded(child: _usageBar('CPU', _cpuPercent)),
                const SizedBox(width: 32),
                Expanded(child: _usageBar('GPU', _gpuPercent)),
              ],
            ),
            const SizedBox(height: 20),

            Text(
              l.holdStartToExit,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white24, fontSize: 12, letterSpacing: 2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 2)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 28,
              fontWeight: FontWeight.w300,
              letterSpacing: 3,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _achievementsCard(int unlocked, int total) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('CONQUISTAS', style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 2)),
              const Spacer(),
              Text(
                '$unlocked / $total',
                style: const TextStyle(color: Colors.white54, fontSize: 13, letterSpacing: 1),
              ),
            ],
          ),
          if (_sessionUnlocked.isNotEmpty) ...[
            const SizedBox(height: 12),
            ..._sessionUnlocked.take(4).map(
              (a) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: Colors.amber, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(a.title, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    ),
                    Text('+${a.points}pts', style: const TextStyle(color: Colors.amber, fontSize: 12)),
                  ],
                ),
              ),
            ),
            if (_sessionUnlocked.length > 4)
              Text(
                '+${_sessionUnlocked.length - 4} nesta sessão',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
          ] else ...[
            const SizedBox(height: 8),
            const Text(
              'Nenhuma conquistada nesta sessão',
              style: TextStyle(color: Colors.white24, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _usageBar(String label, double? percent) {
    final value = (percent ?? 0.0).clamp(0.0, 100.0) / 100.0;
    final Color barColor;
    if (percent == null) {
      barColor = Colors.white12;
    } else if (percent > 85) {
      barColor = Colors.redAccent;
    } else if (percent > 60) {
      barColor = Colors.orange;
    } else {
      barColor = Colors.white38;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 2)),
            const Spacer(),
            Text(
              percent == null ? '--' : '${percent.round()}%',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: value,
            backgroundColor: Colors.white10,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
            minHeight: 4,
          ),
        ),
      ],
    );
  }
}
