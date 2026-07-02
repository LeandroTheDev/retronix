import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../utils/app_localizations.dart';
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
  static const _assemblyDuration = Duration(milliseconds: 3600);
  static const _fallbackHold = Duration(milliseconds: 500);
  static const _maxHold = Duration(seconds: 10);

  late final AnimationController _assembly;
  late final AnimationController _cursorBlink;
  late final Animation<double> _textOpacity;
  final _player = AudioPlayer();

  StreamSubscription<void>? _soundCompleteSub;
  Timer? _safetyTimer;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    _assembly = AnimationController(vsync: this, duration: _assemblyDuration)..forward();

    _textOpacity = CurvedAnimation(
      parent: _assembly,
      curve: const Interval(0.8, 1.0, curve: Curves.easeIn),
    );

    _cursorBlink = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);

    _playBootSound();
  }

  Future<void> _playBootSound() async {
    try {
      _soundCompleteSub = _player.onPlayerComplete.listen((_) => _goToConsoleSelector());
      await _player.play(AssetSource(_bootSound));
      // Safety net in case the audio backend never fires onPlayerComplete
      // (e.g. missing driver on the device) — don't strand the boot screen.
      _safetyTimer = Timer(_maxHold, _goToConsoleSelector);
    } catch (_) {
      Future.delayed(_fallbackHold, _goToConsoleSelector);
    }
  }

  void _goToConsoleSelector() {
    if (_navigated || !mounted) return;
    _navigated = true;
    _safetyTimer?.cancel();
    _soundCompleteSub?.cancel();
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
    _soundCompleteSub?.cancel();
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
                    l.initializingSystem,
                    style: const TextStyle(color: Colors.white54, fontSize: 14, letterSpacing: 4),
                  ),
                  FadeTransition(
                    opacity: _cursorBlink,
                    child: const Text(
                      '_',
                      style: TextStyle(color: Colors.white54, fontSize: 14, letterSpacing: 4),
                    ),
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
