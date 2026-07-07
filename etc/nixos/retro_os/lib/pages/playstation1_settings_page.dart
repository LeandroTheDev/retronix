import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/gamepad_service.dart';
import '../utils/debug_logger.dart';
import '../utils/settings_service.dart';
import '../utils/app_localizations.dart';
import '../utils/sound.dart';

class Playstation1SettingsPage extends StatefulWidget {
  const Playstation1SettingsPage({super.key});

  @override
  State<Playstation1SettingsPage> createState() => _Playstation1SettingsPageState();
}

class _Playstation1SettingsPageState extends State<Playstation1SettingsPage> {
  late final StreamSubscription<GamepadAction> _sub;
  int _selectedIndex = 0;
  bool _loading = true;

  final _ditheringOptions   = const ['enabled', 'disabled'];
  final _smoothOptions      = const ['disabled', 'enabled'];
  final _hiResOptions       = const ['disabled', 'enabled'];
  final _frameskipOptions   = const ['disabled', 'auto'];
  final _aspectOptions      = const ['4:3', 'fill'];
  final _fpsShowOptions     = const ['false', 'true'];
  final _audioVolumeOptions = const ['0', '3', '6', '9', '12', '15', '18'];

  int _ditheringIdx   = 0;
  int _smoothIdx      = 0;
  int _hiResIdx       = 0;
  int _frameskipIdx   = 0;
  int _aspectIdx      = 0;
  int _fpsShowIdx     = 0;
  int _audioVolumeIdx = 0;

  String _corePath   = '';
  bool   _coreExists = true;

  // 0-6 = option rows, 7 = restore defaults
  final _rowKeys = List.generate(8, (_) => GlobalKey());

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
    final dithering   = await SettingsService.instance.ps1Dithering();
    final smooth      = await SettingsService.instance.ps1NeonEnhancement();
    final hiRes       = await SettingsService.instance.ps1EnhanceResolution();
    final frameskip   = await SettingsService.instance.ps1FrameskipType();
    final aspect      = await SettingsService.instance.ps1Aspect();
    final fpsShow     = await SettingsService.instance.ps1FpsShow();
    final audioVol    = await SettingsService.instance.ps1AudioVolume();
    final core        = await SettingsService.instance.ps1CorePath();
    if (!mounted) return;
    setState(() {
      _ditheringIdx   = _ditheringOptions.indexOf(dithering).clamp(0, _ditheringOptions.length - 1);
      _smoothIdx      = _smoothOptions.indexOf(smooth).clamp(0, _smoothOptions.length - 1);
      _hiResIdx       = _hiResOptions.indexOf(hiRes).clamp(0, _hiResOptions.length - 1);
      _frameskipIdx   = _frameskipOptions.indexOf(frameskip).clamp(0, _frameskipOptions.length - 1);
      _aspectIdx      = _aspectOptions.indexOf(aspect).clamp(0, _aspectOptions.length - 1);
      _fpsShowIdx     = _fpsShowOptions.indexOf(fpsShow).clamp(0, _fpsShowOptions.length - 1);
      _audioVolumeIdx = _audioVolumeOptions.indexOf(audioVol).clamp(0, _audioVolumeOptions.length - 1);
      _corePath       = core;
      _coreExists     = File(core).existsSync();
      _loading        = false;
    });
  }

  void _handleAction(GamepadAction action) {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    switch (action) {
      case GamepadAction.up:
        setState(() => _selectedIndex = navigateIndex(_selectedIndex, -1, 7));
        _scrollToSelected();
      case GamepadAction.down:
        setState(() => _selectedIndex = navigateIndex(_selectedIndex, 1, 7));
        _scrollToSelected();
      case GamepadAction.left:
        _cycleValue(-1);
      case GamepadAction.right:
        _cycleValue(1);
      case GamepadAction.confirm:
        if (_selectedIndex == 7) _resetAll();
      case GamepadAction.back:
        Navigator.pop(context);
      default:
        break;
    }
  }

  void _cycleValue(int dir) {
    switch (_selectedIndex) {
      case 0:
        final next = (_ditheringIdx + dir).clamp(0, _ditheringOptions.length - 1);
        if (next == _ditheringIdx) return;
        setState(() => _ditheringIdx = next);
        SettingsService.instance.setPs1Dithering(_ditheringOptions[next]);
      case 1:
        final next = (_smoothIdx + dir).clamp(0, _smoothOptions.length - 1);
        if (next == _smoothIdx) return;
        setState(() => _smoothIdx = next);
        SettingsService.instance.setPs1NeonEnhancement(_smoothOptions[next]);
      case 2:
        final next = (_hiResIdx + dir).clamp(0, _hiResOptions.length - 1);
        if (next == _hiResIdx) return;
        setState(() => _hiResIdx = next);
        SettingsService.instance.setPs1EnhanceResolution(_hiResOptions[next]);
      case 3:
        final next = (_frameskipIdx + dir).clamp(0, _frameskipOptions.length - 1);
        if (next == _frameskipIdx) return;
        setState(() => _frameskipIdx = next);
        SettingsService.instance.setPs1FrameskipType(_frameskipOptions[next]);
      case 4:
        final next = (_aspectIdx + dir).clamp(0, _aspectOptions.length - 1);
        if (next == _aspectIdx) return;
        setState(() => _aspectIdx = next);
        SettingsService.instance.setPs1Aspect(_aspectOptions[next]);
      case 5:
        final next = (_fpsShowIdx + dir).clamp(0, _fpsShowOptions.length - 1);
        if (next == _fpsShowIdx) return;
        setState(() => _fpsShowIdx = next);
        SettingsService.instance.setPs1FpsShow(_fpsShowOptions[next]);
      case 6:
        final next = (_audioVolumeIdx + dir).clamp(0, _audioVolumeOptions.length - 1);
        if (next == _audioVolumeIdx) return;
        setState(() => _audioVolumeIdx = next);
        SettingsService.instance.setPs1AudioVolume(_audioVolumeOptions[next]);
    }
  }

  void _scrollToSelected() {
    final ctx = _rowKeys[_selectedIndex].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      alignment: 0.5,
    );
  }

  Future<void> _resetAll() async {
    await SettingsService.instance.resetPs1();
    DebugLogger.log('[Playstation1SettingsPage] settings reset to defaults');
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
            padding: const EdgeInsets.fromLTRB(80, 80, 80, 48),
            child: Text(
              l.playstation1SettingsTitle,
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
                  KeyedSubtree(
                    key: _rowKeys[0],
                    child: _OptionRow(
                      icon: Icons.grain,
                      label: l.ps1Dithering,
                      value: l.ps1DitheringLabels[_ditheringIdx],
                      selected: _selectedIndex == 0,
                      canLeft:  _ditheringIdx > 0,
                      canRight: _ditheringIdx < _ditheringOptions.length - 1,
                    ),
                  ),
                  KeyedSubtree(
                    key: _rowKeys[1],
                    child: _OptionRow(
                      icon: Icons.auto_fix_high,
                      label: l.ps1SmoothSprites,
                      value: l.ps1SmoothLabels[_smoothIdx],
                      selected: _selectedIndex == 1,
                      canLeft:  _smoothIdx > 0,
                      canRight: _smoothIdx < _smoothOptions.length - 1,
                    ),
                  ),
                  KeyedSubtree(
                    key: _rowKeys[2],
                    child: _OptionRow(
                      icon: Icons.hd,
                      label: l.ps1HiResSprites,
                      value: l.ps1HiResLabels[_hiResIdx],
                      selected: _selectedIndex == 2,
                      canLeft:  _hiResIdx > 0,
                      canRight: _hiResIdx < _hiResOptions.length - 1,
                    ),
                  ),
                  KeyedSubtree(
                    key: _rowKeys[3],
                    child: _OptionRow(
                      icon: Icons.skip_next,
                      label: l.ps1Frameskip,
                      value: l.ps1FrameskipLabels[_frameskipIdx],
                      selected: _selectedIndex == 3,
                      canLeft:  _frameskipIdx > 0,
                      canRight: _frameskipIdx < _frameskipOptions.length - 1,
                    ),
                  ),
                  KeyedSubtree(
                    key: _rowKeys[4],
                    child: _OptionRow(
                      icon: Icons.aspect_ratio,
                      label: l.aspectRatio,
                      value: l.ps1AspectLabels[_aspectIdx],
                      selected: _selectedIndex == 4,
                      canLeft:  _aspectIdx > 0,
                      canRight: _aspectIdx < _aspectOptions.length - 1,
                    ),
                  ),
                  KeyedSubtree(
                    key: _rowKeys[5],
                    child: _OptionRow(
                      icon: Icons.query_stats,
                      label: l.showFps,
                      value: l.fpsShowLabels[_fpsShowIdx],
                      selected: _selectedIndex == 5,
                      canLeft:  _fpsShowIdx > 0,
                      canRight: _fpsShowIdx < _fpsShowOptions.length - 1,
                    ),
                  ),
                  KeyedSubtree(
                    key: _rowKeys[6],
                    child: _OptionRow(
                      icon: Icons.volume_up,
                      label: l.audioGain,
                      value: l.audioGainValue(_audioVolumeOptions[_audioVolumeIdx]),
                      selected: _selectedIndex == 6,
                      canLeft:  _audioVolumeIdx > 0,
                      canRight: _audioVolumeIdx < _audioVolumeOptions.length - 1,
                    ),
                  ),
                  _CoreInfoRow(
                    label: l.coreRetroArch,
                    notFoundMessage: l.coreFileNotFound,
                    path: _corePath,
                    exists: _coreExists,
                  ),
                  KeyedSubtree(
                    key: _rowKeys[7],
                    child: _ActionRow(
                      icon: Icons.restore,
                      label: l.restoreDefaults,
                      selected: _selectedIndex == 7,
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
            flex: 3,
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
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.right,
              softWrap: true,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.black : Colors.white60,
                fontSize: 16,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
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
        color: exists ? Colors.white10 : Colors.red.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: exists ? null : Border.all(color: Colors.red.withValues(alpha: 0.6)),
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
                  style: TextStyle(color: exists ? Colors.white : Colors.red, fontSize: 18),
                ),
                const SizedBox(height: 4),
                Text(
                  path,
                  style: TextStyle(
                    color: exists ? Colors.white38 : Colors.red.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (!exists) ...[
                  const SizedBox(height: 6),
                  Text(notFoundMessage, style: const TextStyle(color: Colors.red, fontSize: 12)),
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
