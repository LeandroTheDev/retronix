import 'dart:async';
import 'package:flutter/material.dart';
import '../services/gamepad_service.dart';
import '../utils/app_localizations.dart';

// Placeholder in-game menu, shown over retro_os when the player presses L+R
// during gameplay. Popping this route hands focus back to RetroArch — see
// Nintendo64GameOpen._showOverlay, which awaits the push and does that.
class GameOverlayPage extends StatefulWidget {
  const GameOverlayPage({super.key});

  @override
  State<GameOverlayPage> createState() => _GameOverlayPageState();
}

class _GameOverlayPageState extends State<GameOverlayPage> {
  late final StreamSubscription<GamepadAction> _comboSub;

  @override
  void initState() {
    super.initState();
    _comboSub = GamepadService.instance.watchCombo(
      {GamepadAction.l, GamepadAction.r},
      () {
        if (mounted) Navigator.of(context).pop();
      },
    );
  }

  @override
  void dispose() {
    _comboSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black87,
      body: Center(
        child: Text(
          l.pressLrToContinue,
          style: const TextStyle(color: Colors.white70, fontSize: 20, letterSpacing: 2),
        ),
      ),
    );
  }
}
