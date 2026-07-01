import 'dart:async';
import 'package:flutter/material.dart';
import '../services/gamepad_service.dart';
import '../utils/app_localizations.dart';
import '../utils/locale_service.dart';
import '../utils/settings_service.dart';
import '../utils/system_info.dart';

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

  List<DisplayMode> _resolutionOptions = [];
  int _resIdx = 0;
  bool _loadingResolutions = true;

  @override
  void initState() {
    super.initState();
    _langIdx = _langOptions.indexOf(LocaleService.instance.locale).clamp(0, _langOptions.length - 1);
    _sub = GamepadService.instance.actions.listen(_handleAction);
    _loadResolutions();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  Future<void> _loadResolutions() async {
    final options = await getAvailableDisplayModes();
    final current = await getCurrentDisplayMode();
    if (!mounted) return;
    setState(() {
      _resolutionOptions = options;
      _resIdx = current == null
          ? 0
          : options.indexWhere((m) => m.resolution == current.resolution).clamp(0, options.length - 1);
      _loadingResolutions = false;
    });
  }

  void _handleAction(GamepadAction action) {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    switch (action) {
      case GamepadAction.up:
        setState(() => _selectedIndex = (_selectedIndex - 1).clamp(0, 1));
      case GamepadAction.down:
        setState(() => _selectedIndex = (_selectedIndex + 1).clamp(0, 1));
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
    switch (_selectedIndex) {
      case 0:
        final next = (_langIdx + dir).clamp(0, _langOptions.length - 1);
        if (next == _langIdx) return;
        setState(() => _langIdx = next);
        LocaleService.instance.setLocale(_langOptions[next]);
      case 1:
        if (_loadingResolutions || _resolutionOptions.isEmpty) return;
        final next = (_resIdx + dir).clamp(0, _resolutionOptions.length - 1);
        if (next == _resIdx) return;
        setState(() => _resIdx = next);
        final mode = _resolutionOptions[next];
        applyDisplayMode(mode);
        SettingsService.instance.setSystemDisplayMode(mode.resolution, mode.rate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final langLabels = [l.languageEnglish, l.languagePortuguese];

    final String resolutionValue;
    if (_loadingResolutions) {
      resolutionValue = '...';
    } else if (_resolutionOptions.isEmpty) {
      resolutionValue = l.noResolutionsFound;
    } else {
      resolutionValue = _resolutionOptions[_resIdx].label;
    }

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
                _OptionRow(
                  icon: Icons.aspect_ratio,
                  label: l.screenResolution,
                  value: resolutionValue,
                  selected: _selectedIndex == 1,
                  canLeft:  !_loadingResolutions && _resIdx > 0,
                  canRight: !_loadingResolutions && _resIdx < _resolutionOptions.length - 1,
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
