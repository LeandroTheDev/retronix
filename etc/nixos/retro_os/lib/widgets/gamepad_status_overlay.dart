import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/gamepad_service.dart';
import '../utils/app_localizations.dart';
import '../utils/debug_logger.dart';

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
          final name = GamepadService.instance.nameForId(newId) ?? l.controllerFallbackName;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l.controllerConnected(i + 1, name), style: const TextStyle(fontFamily: 'PressStart')),
            ),
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

  String? _svgAssetForSlot(int i) {
    final id = _slots[i];
    if (id == null) return null;
    final vp = GamepadService.instance.vendorProductForId(id);
    final pad = GamepadService.instance.knownConsolePadForId(id);
    DebugLogger.log('[GamepadOverlay] slot $i id=$id vp=$vp pad=$pad');
    if (pad == KnownConsolePad.nintendo64) return 'assets/images/n64-controller.svg';
    if (pad == KnownConsolePad.xbox360 || pad == KnownConsolePad.xboxSeries) {
      return 'assets/images/xbox-controller.svg';
    }
    DebugLogger.log('[GamepadOverlay] slot $i no svg matched — falling back to icon');
    return null;
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
            final svgAsset = _svgAssetForSlot(i);
            DebugLogger.log('[GamepadOverlay] build slot $i connected=$connected svgAsset=$svgAsset');
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: svgAsset != null
                  ? SvgPicture.asset(
                      svgAsset,
                      width: iconSize,
                      height: iconSize,
                      colorFilter: ColorFilter.mode(Colors.greenAccent, BlendMode.srcIn),
                      placeholderBuilder: (ctx) {
                        DebugLogger.log('[GamepadOverlay] slot $i svg still loading: $svgAsset');
                        return Icon(Icons.sports_esports, size: iconSize, color: Colors.greenAccent);
                      },
                    )
                  : Icon(Icons.sports_esports, size: iconSize, color: connected ? Colors.greenAccent : Colors.white24),
            );
          }),
        ),
      ),
    );
  }
}
