import 'dart:async';
import 'package:flutter/material.dart';
import '../services/gamepad_service.dart';
import '../utils/app_localizations.dart';
import '../utils/locale_service.dart';

class SystemSettingsPage extends StatefulWidget {
  const SystemSettingsPage({super.key});

  @override
  State<SystemSettingsPage> createState() => _SystemSettingsPageState();
}

class _SystemSettingsPageState extends State<SystemSettingsPage> {
  late final StreamSubscription<GamepadAction> _sub;
  int _selectedIndex = 0;

  final _langOptions = const ['en_us', 'pt_br'];

  int _langIdx = 0;

  @override
  void initState() {
    super.initState();
    _langIdx = _langOptions.indexOf(LocaleService.instance.locale).clamp(0, _langOptions.length - 1);
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
      case GamepadAction.up:
        setState(() => _selectedIndex = (_selectedIndex - 1).clamp(0, 0));
      case GamepadAction.down:
        setState(() => _selectedIndex = (_selectedIndex + 1).clamp(0, 0));
      case GamepadAction.left:
        _cycleValue(-1);
      case GamepadAction.right:
        _cycleValue(1);
      case GamepadAction.back:
        Navigator.pop(context);
      default:
        break;
    }
  }

  void _cycleValue(int dir) {
    if (_selectedIndex == 0) {
      final next = (_langIdx + dir).clamp(0, _langOptions.length - 1);
      if (next == _langIdx) return;
      setState(() => _langIdx = next);
      LocaleService.instance.setLocale(_langOptions[next]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final langLabels = [l.languageEnglish, l.languagePortuguese];
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 80),
            child: Text(
              l.systemSettingsTitle,
              style: const TextStyle(color: Colors.white54, fontSize: 16, letterSpacing: 2),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                _OptionRow(
                  icon: Icons.language,
                  label: l.language,
                  value: langLabels[_langIdx],
                  selected: _selectedIndex == 0,
                  canLeft:  _langIdx > 0,
                  canRight: _langIdx < _langOptions.length - 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.selected,
    required this.canLeft,
    required this.canRight,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool selected;
  final bool canLeft;
  final bool canRight;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.black : Colors.white;
    final fgDim = selected ? Colors.black45 : Colors.white38;

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
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 18,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          if (selected) ...[
            Icon(Icons.chevron_left, color: canLeft ? fg : fgDim, size: 20),
            const SizedBox(width: 8),
          ],
          Text(
            value,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white60,
              fontSize: 16,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          if (selected) ...[
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: canRight ? fg : fgDim, size: 20),
          ],
        ],
      ),
    );
  }
}
