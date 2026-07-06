import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  // Once retroarch's dynarec is up, the emulator owns the screen — keeping
  // our own spinner animating underneath just burns CPU/GPU for nothing.
  bool _showLoadingUi = true;

  @override
  void initState() {
    super.initState();
    _openGame();
  }

  Future<void> _openGame() async {
    DebugLogger.log('[Nintendo64GameOpen] opening game: ${widget.gameName}');

    final romPath = await getGameFilePath('Nintendo 64', widget.gameName);
    // Safe to build localized strings after the first await (widget is mounted)
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
      GamepadService.instance.setGameRunning(true);

      // Started right after the process launches rather than waiting for
      // dynarec-ready: the RAM reader just times out harmlessly (see
      // RetroarchRamReader's logging) until RetroArch's network command
      // interface comes up, so there's no race to worry about here.
      await AchievementService.instance.startWatching('Nintendo 64', widget.gameName);
      AchievementWindowService.instance.startSession(process.pid);

      void onRetroarchLine(String line, String src) {
        DebugLogger.log('[retroarch:$src] $line');
        if (_showLoadingUi && line.contains('Init new dynarec')) {
          DebugLogger.log('[Nintendo64GameOpen] dynarec ready — dropping loading UI');
          if (mounted) setState(() => _showLoadingUi = false);
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
      for (final s in exitSubs) {
        s.cancel();
      }
      _exitHoldTimer?.cancel();
      GamepadService.instance.setGameRunning(false);
      DebugLogger.log('[Nintendo64GameOpen] retroarch exited with code: $exitCode');
      await AchievementService.instance.stopWatching();
      AchievementWindowService.instance.stopSession();

      if (!mounted) return;
      if (exitCode != 0 && exitCode != -15) {
        // -15 = SIGTERM (normal kill), not an error
        Navigator.pop(context, l.retroarchExitError(exitCode));
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      DebugLogger.log('[Nintendo64GameOpen] failed to launch retroarch: $e');
      GamepadService.instance.setGameRunning(false);
      await AchievementService.instance.stopWatching();
      AchievementWindowService.instance.stopSession();
      if (mounted) Navigator.pop(context, l.retroarchLaunchError(e));
    }
  }

  // Holding Start for 5s kills the process — Select isn't required since some
  // controllers don't have one.
  Timer? _exitHoldTimer;

  // L+R toggles window focus between the Flutter UI and RetroArch.
  bool _windowFocused = false;
  bool _lHeld = false;
  bool _rHeld = false;

  Future<void> _toggleWindowFocus() async {
    _windowFocused = !_windowFocused;
    DebugLogger.log('[Nintendo64GameOpen] L+R — windowFocused: $_windowFocused');
    if (_windowFocused) {
      await _windowChannel.invokeMethod('forceFocus');
    } else {
      await _windowChannel.invokeMethod('lowerWindow');
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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (!_showLoadingUi) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            l.gameRunning,
            style: const TextStyle(color: Colors.white54, fontSize: 20, letterSpacing: 3),
          ),
        ),
      );
    }
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
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 20,
                letterSpacing: 3,
              ),
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
}
