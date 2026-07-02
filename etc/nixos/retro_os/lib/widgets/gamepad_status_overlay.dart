import 'dart:async';
import 'package:flutter/material.dart';
import '../services/gamepad_service.dart';
import '../utils/app_localizations.dart';

/// Persistent top-left indicator showing which of the 4 player slots
/// currently have a gamepad assigned. Meant to be layered on top of every
/// screen via MaterialApp's `builder`, not embedded per-page.
class GamepadStatusOverlay extends StatefulWidget {
  const GamepadStatusOverlay({super.key});

  @override
  State<GamepadStatusOverlay> createState() => _GamepadStatusOverlayState();
}

class _GamepadStatusOverlayState extends State<GamepadStatusOverlay> {
  late final StreamSubscription<List<String?>> _sub;
  List<String?> _slots = GamepadService.instance.currentPlayerSlots;

  @override
  void initState() {
    super.initState();
    _sub = GamepadService.instance.playerSlots.listen((slots) {
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      for (var i = 0; i < slots.length; i++) {
        final newId = slots[i];
        if (newId != null && _slots[i] == null) {
          final name = GamepadService.instance.nameForId(newId) ?? 'Controller';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.controllerConnected(i + 1, name))),
          );
        }
      }
      setState(() => _slots = slots);
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = MediaQuery.sizeOf(context).height * 0.05;
    return Positioned(
      top: 16,
      left: 16,
      child: IgnorePointer(
        child: Row(
          children: List.generate(_slots.length, (i) {
            final connected = _slots[i] != null;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(
                Icons.sports_esports,
                size: iconSize,
                color: connected ? Colors.greenAccent : Colors.white24,
              ),
            );
          }),
        ),
      ),
    );
  }
}
