import 'dart:async';
import 'package:flutter/material.dart';
import '../services/gamepad_service.dart';
import '../utils/app_localizations.dart';

class PcSettingsPage extends StatefulWidget {
  const PcSettingsPage({super.key});

  @override
  State<PcSettingsPage> createState() => _PcSettingsPageState();
}

class _PcSettingsPageState extends State<PcSettingsPage> {
  late final StreamSubscription<GamepadAction> _sub;

  // 0 = restore defaults
  final int _selectedIndex = 0;
  final _rowKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _sub = GamepadService.instance.actions.listen(_handleAction);
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  void _handleAction(GamepadAction action) {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    switch (action) {
      case GamepadAction.confirm:
        if (_selectedIndex == 0) _resetAll();
      case GamepadAction.back:
        Navigator.pop(context);
      default:
        break;
    }
  }

  Future<void> _resetAll() async {
    // no persistent settings yet — placeholder
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(80, 80, 80, 48),
            child: Text(
              l.pcSettingsTitle,
              style: const TextStyle(color: Colors.white54, fontSize: 16, letterSpacing: 5),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                KeyedSubtree(
                  key: _rowKey,
                  child: _ActionRow(
                    icon: Icons.restore,
                    label: l.restoreDefaults,
                    selected: _selectedIndex == 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.icon, required this.label, required this.selected});

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      margin: const EdgeInsets.symmetric(horizontal: 80, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        color: selected ? Colors.white : Colors.white10,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: selected ? Colors.black : Colors.white54, size: 22),
          const SizedBox(width: 20),
          Text(
            label,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white,
              fontSize: 18,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
