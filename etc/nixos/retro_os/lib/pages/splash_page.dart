import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../utils/app_localizations.dart';
import '../utils/debug_logger.dart';
import '../utils/sound.dart';
import '../widgets/snowflake_logo.dart';
import 'console_selector_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  // Matches the ~7s runtime of the boot jingle — the logo assembly and the
  // idle hold below are both timed against it so they land on the last note.
  static const _bootSound = 'sounds/startup-sound-variation-6-freesounds-community.wav';
  static const _assemblyDuration = Duration(milliseconds: 4500);
  static const _fallbackHold = Duration(milliseconds: 500);
  // The clip is ~7.5s but everything past 5s is just reverb tail — cut the
  // boot screen short instead of waiting for onPlayerComplete.
  static const _playbackHold = Duration(milliseconds: 5500);

  static const _soundStartDelay = Duration(seconds: 1);

  late final AnimationController _assembly;
  late final AnimationController _cursorBlink;
  late final Animation<double> _textOpacity;
  final _player = AudioPlayer();

  Timer? _safetyTimer;
  bool _navigated = false;
  late final Future<void> _soundReady;

  @override
  void initState() {
    super.initState();

    _assembly = AnimationController(vsync: this, duration: _assemblyDuration);

    // Fraction of _assemblyDuration (4.5s) — text only starts fading in at
    // 4.0s, with a gentle 500ms settle to the very end.
    _textOpacity = CurvedAnimation(
      parent: _assembly,
      curve: const Interval(0.8889, 1.0, curve: Curves.easeOutCubic),
    );

    _cursorBlink = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);

    // Loads/decodes the asset right away so it's ready by the time the sound
    // delay elapses, instead of paying that cost inside _playBootSound.
    _soundReady = _player.setSource(AssetSource(_bootSound)).catchError((e) {
      DebugLogger.log('[splash] boot sound preload failed: $e');
    });

    // Warm up every other UI sound effect while the boot jingle plays, so
    // the first swap/connect/error sound in the app doesn't stutter.
    preloadAllSounds();

    Future.delayed(_soundStartDelay, _playBootSound);
  }

  Future<void> _playBootSound() async {
    if (!mounted) return;
    try {
      DebugLogger.log('[splash] starting boot sound playback');
      await _soundReady;
      // Kick off the logo assembly right before resume() so both start from
      // the same instant — two independent timers would drift because
      // resume() has its own native audio-backend startup latency.
      _assembly.forward();
      await _player.resume();
      DebugLogger.log('[splash] audioplayers.resume() returned — moving on after $_playbackHold');
      _safetyTimer = Timer(_playbackHold, _goToConsoleSelector);
    } catch (e) {
      DebugLogger.log('[splash] _playBootSound exception: $e');
      Future.delayed(_fallbackHold, _goToConsoleSelector);
    }
  }

  void _goToConsoleSelector() {
    if (_navigated || !mounted) return;
    _navigated = true;
    _safetyTimer?.cancel();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, _, _) => const ConsoleSelectorPage(),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _assembly.dispose();
    _cursorBlink.dispose();
    _safetyTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SnowflakeLogo(progress: _assembly, size: 220),
            const SizedBox(height: 40),
            FadeTransition(
              opacity: _textOpacity,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l.welcomeSystem,
                    style: const TextStyle(color: Colors.white54, fontSize: 14, letterSpacing: 4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
