import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/gamepad_service.dart';
import '../utils/debug_logger.dart';
import '../utils/settings_service.dart';
import '../utils/app_localizations.dart';

class Nintendo64SettingsPage extends StatefulWidget {
  const Nintendo64SettingsPage({super.key});

  @override
  State<Nintendo64SettingsPage> createState() => _Nintendo64SettingsPageState();
}

class _Nintendo64SettingsPageState extends State<Nintendo64SettingsPage> {
  late final StreamSubscription<GamepadAction> _sub;
  int _selectedIndex = 0;
  bool _loading = true;

  final _resolutionOptions = const ['native', 'hd', 'fullhd', '4k'];
  final _msaaOptions       = const ['0', '2', '4', '8'];
  final _filterOptions     = const ['nearest', 'linear'];
  final _frameDupesOptions = const ['false', 'true'];

  int _resIdx        = 1;
  int _msaaIdx       = 0;
  int _filterIdx     = 1;
  int _frameDupesIdx = 0;

  String _corePath   = '';
  bool   _coreExists = true;

  @override
  void initState() {
    super.initState();
    _sub = GamepadService.instance.actions.listen(_handleAction);
    _load();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final res        = await SettingsService.instance.n64Resolution();
    final msaa       = await SettingsService.instance.n64Msaa();
    final filter     = await SettingsService.instance.n64TextureFilter();
    final frameDupes = await SettingsService.instance.n64FrameDupes();
    final core       = await SettingsService.instance.n64CorePath();
    if (!mounted) return;
    setState(() {
      _resIdx        = _resolutionOptions.indexOf(res).clamp(0, _resolutionOptions.length - 1);
      _msaaIdx       = _msaaOptions.indexOf(msaa).clamp(0, _msaaOptions.length - 1);
      _filterIdx     = _filterOptions.indexOf(filter).clamp(0, _filterOptions.length - 1);
      _frameDupesIdx = _frameDupesOptions.indexOf(frameDupes).clamp(0, _frameDupesOptions.length - 1);
      _corePath      = core;
      _coreExists    = File(core).existsSync();
      _loading       = false;
    });
  }

  void _handleAction(GamepadAction action) {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    switch (action) {
      case GamepadAction.up:
        setState(() => _selectedIndex = (_selectedIndex - 1).clamp(0, 4));
      case GamepadAction.down:
        setState(() => _selectedIndex = (_selectedIndex + 1).clamp(0, 4));
      case GamepadAction.left:
        _cycleValue(-1);
      case GamepadAction.right:
        _cycleValue(1);
      case GamepadAction.confirm:
        if (_selectedIndex == 4) _resetAll();
      case GamepadAction.back:
        Navigator.pop(context);
      default:
        break;
    }
  }

  void _cycleValue(int dir) {
    switch (_selectedIndex) {
      case 0:
        final next = (_resIdx + dir).clamp(0, _resolutionOptions.length - 1);
        if (next == _resIdx) return;
        setState(() => _resIdx = next);
        SettingsService.instance.setN64Resolution(_resolutionOptions[next]);
      case 1:
        final next = (_msaaIdx + dir).clamp(0, _msaaOptions.length - 1);
        if (next == _msaaIdx) return;
        setState(() => _msaaIdx = next);
        SettingsService.instance.setN64Msaa(_msaaOptions[next]);
      case 2:
        final next = (_filterIdx + dir).clamp(0, _filterOptions.length - 1);
        if (next == _filterIdx) return;
        setState(() => _filterIdx = next);
        SettingsService.instance.setN64TextureFilter(_filterOptions[next]);
      case 3:
        final next = (_frameDupesIdx + dir).clamp(0, _frameDupesOptions.length - 1);
        if (next == _frameDupesIdx) return;
        setState(() => _frameDupesIdx = next);
        SettingsService.instance.setN64FrameDupes(_frameDupesOptions[next]);
    }
  }

  Future<void> _resetAll() async {
    await SettingsService.instance.resetN64Graphics();
    DebugLogger.log('[Nintendo64SettingsPage] settings reset to defaults');
    await _load();
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
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 80),
            child: Text(
              l.nintendo64SettingsTitle,
              style: const TextStyle(color: Colors.white54, fontSize: 16, letterSpacing: 5),
            ),
          ),
          if (_loading)
            const Expanded(
              child: Center(child: CircularProgressIndicator(color: Colors.white)),
            )
          else
            Expanded(
              child: ListView(
                children: [
                  _OptionRow(
                    icon: Icons.tv,
                    label: l.internalResolution,
                    value: l.resolutionLabels[_resIdx],
                    selected: _selectedIndex == 0,
                    canLeft:  _resIdx > 0,
                    canRight: _resIdx < _resolutionOptions.length - 1,
                  ),
                  _OptionRow(
                    icon: Icons.blur_on,
                    label: l.antiAliasing,
                    value: l.msaaLabels[_msaaIdx],
                    selected: _selectedIndex == 1,
                    canLeft:  _msaaIdx > 0,
                    canRight: _msaaIdx < _msaaOptions.length - 1,
                  ),
                  _OptionRow(
                    icon: Icons.texture,
                    label: l.textureFilter,
                    value: l.filterLabels[_filterIdx],
                    selected: _selectedIndex == 2,
                    canLeft:  _filterIdx > 0,
                    canRight: _filterIdx < _filterOptions.length - 1,
                  ),
                  _OptionRow(
                    icon: Icons.speed,
                    label: l.frameDuplication,
                    value: l.frameDupesLabels[_frameDupesIdx],
                    selected: _selectedIndex == 3,
                    canLeft:  _frameDupesIdx > 0,
                    canRight: _frameDupesIdx < _frameDupesOptions.length - 1,
                  ),
                  _CoreInfoRow(
                    label: l.coreRetroArch,
                    notFoundMessage: l.coreFileNotFound,
                    path: _corePath,
                    exists: _coreExists,
                  ),
                  _ActionRow(
                    icon: Icons.restore,
                    label: l.restoreDefaults,
                    selected: _selectedIndex == 4,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Row widgets ──────────────────────────────────────────────────────────────

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

class _CoreInfoRow extends StatelessWidget {
  const _CoreInfoRow({
    required this.label,
    required this.notFoundMessage,
    required this.path,
    required this.exists,
  });

  final String label;
  final String notFoundMessage;
  final String path;
  final bool exists;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 80, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        color: exists ? Colors.white10 : Colors.red.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: exists ? null : Border.all(color: Colors.red.withOpacity(0.6)),
      ),
      child: Row(
        children: [
          Icon(Icons.memory, color: exists ? Colors.white54 : Colors.red, size: 22),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: exists ? Colors.white : Colors.red,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  path,
                  style: TextStyle(
                    color: exists ? Colors.white38 : Colors.red.withOpacity(0.7),
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (!exists) ...[
                  const SizedBox(height: 6),
                  Text(
                    notFoundMessage,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.selected,
  });

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
