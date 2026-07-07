import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/gamepad_service.dart';
import '../utils/debug_logger.dart';
import '../utils/settings_service.dart';
import '../utils/app_localizations.dart';
import '../utils/sound.dart';

class Playstation2SettingsPage extends StatefulWidget {
  const Playstation2SettingsPage({super.key});

  @override
  State<Playstation2SettingsPage> createState() => _Playstation2SettingsPageState();
}

class _Playstation2SettingsPageState extends State<Playstation2SettingsPage> {
  late final StreamSubscription<GamepadAction> _sub;
  int _selectedIndex = 0;
  bool _loading = true;

  final _upscaleOptions   = const ['1', '2', '3', '4', '6', '8'];
  final _bilinearOptions  = const ['nearest', 'bilinear-ps2', 'bilinear-forced'];
  final _fxaaOptions      = const ['false', 'true'];
  final _rendererOptions  = const ['Auto', 'OpenGL', 'Vulkan', 'Software'];
  final _blendingOptions  = const ['Minimum', 'Basic', 'Medium', 'High', 'Full', 'Ultra'];
  final _aspectOptions    = const ['4:3', '16:9', 'fill'];
  final _fpsShowOptions   = const ['false', 'true'];
  final _audioVolumeOptions = const ['0', '3', '6', '9', '12', '15', '18'];

  int _upscaleIdx   = 0;
  int _bilinearIdx  = 0;
  int _fxaaIdx      = 0;
  int _rendererIdx  = 0;
  int _blendingIdx  = 1;
  int _aspectIdx    = 0;
  int _fpsShowIdx   = 0;
  int _audioVolumeIdx = 0;

  String _corePath   = '';
  bool   _coreExists = true;

  // 0-7 = option rows, 8 = restore defaults
  final _rowKeys = List.generate(9, (_) => GlobalKey());

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
    final upscale   = await SettingsService.instance.ps2UpscaleMultiplier();
    final bilinear  = await SettingsService.instance.ps2BilinearFiltering();
    final fxaa      = await SettingsService.instance.ps2Fxaa();
    final renderer  = await SettingsService.instance.ps2Renderer();
    final blending  = await SettingsService.instance.ps2BlendingAccuracy();
    final aspect    = await SettingsService.instance.ps2Aspect();
    final fpsShow   = await SettingsService.instance.ps2FpsShow();
    final audioVol  = await SettingsService.instance.ps2AudioVolume();
    final core      = await SettingsService.instance.ps2CorePath();
    if (!mounted) return;
    setState(() {
      _upscaleIdx   = _upscaleOptions.indexOf(upscale).clamp(0, _upscaleOptions.length - 1);
      _bilinearIdx  = _bilinearOptions.indexOf(bilinear).clamp(0, _bilinearOptions.length - 1);
      _fxaaIdx      = _fxaaOptions.indexOf(fxaa).clamp(0, _fxaaOptions.length - 1);
      _rendererIdx  = _rendererOptions.indexOf(renderer).clamp(0, _rendererOptions.length - 1);
      _blendingIdx  = _blendingOptions.indexOf(blending).clamp(0, _blendingOptions.length - 1);
      _aspectIdx    = _aspectOptions.indexOf(aspect).clamp(0, _aspectOptions.length - 1);
      _fpsShowIdx   = _fpsShowOptions.indexOf(fpsShow).clamp(0, _fpsShowOptions.length - 1);
      _audioVolumeIdx = _audioVolumeOptions.indexOf(audioVol).clamp(0, _audioVolumeOptions.length - 1);
      _corePath     = core;
      _coreExists   = File(core).existsSync();
      _loading      = false;
    });
  }

  void _handleAction(GamepadAction action) {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    switch (action) {
      case GamepadAction.up:
        setState(() => _selectedIndex = navigateIndex(_selectedIndex, -1, 8));
        _scrollToSelected();
      case GamepadAction.down:
        setState(() => _selectedIndex = navigateIndex(_selectedIndex, 1, 8));
        _scrollToSelected();
      case GamepadAction.left:
        _cycleValue(-1);
      case GamepadAction.right:
        _cycleValue(1);
      case GamepadAction.confirm:
        if (_selectedIndex == 8) _resetAll();
      case GamepadAction.back:
        Navigator.pop(context);
      default:
        break;
    }
  }

  void _cycleValue(int dir) {
    switch (_selectedIndex) {
      case 0:
        final next = (_upscaleIdx + dir).clamp(0, _upscaleOptions.length - 1);
        if (next == _upscaleIdx) return;
        setState(() => _upscaleIdx = next);
        SettingsService.instance.setPs2UpscaleMultiplier(_upscaleOptions[next]);
      case 1:
        final next = (_bilinearIdx + dir).clamp(0, _bilinearOptions.length - 1);
        if (next == _bilinearIdx) return;
        setState(() => _bilinearIdx = next);
        SettingsService.instance.setPs2BilinearFiltering(_bilinearOptions[next]);
      case 2:
        final next = (_fxaaIdx + dir).clamp(0, _fxaaOptions.length - 1);
        if (next == _fxaaIdx) return;
        setState(() => _fxaaIdx = next);
        SettingsService.instance.setPs2Fxaa(_fxaaOptions[next]);
      case 3:
        final next = (_rendererIdx + dir).clamp(0, _rendererOptions.length - 1);
        if (next == _rendererIdx) return;
        setState(() => _rendererIdx = next);
        SettingsService.instance.setPs2Renderer(_rendererOptions[next]);
      case 4:
        final next = (_blendingIdx + dir).clamp(0, _blendingOptions.length - 1);
        if (next == _blendingIdx) return;
        setState(() => _blendingIdx = next);
        SettingsService.instance.setPs2BlendingAccuracy(_blendingOptions[next]);
      case 5:
        final next = (_aspectIdx + dir).clamp(0, _aspectOptions.length - 1);
        if (next == _aspectIdx) return;
        setState(() => _aspectIdx = next);
        SettingsService.instance.setPs2Aspect(_aspectOptions[next]);
      case 6:
        final next = (_fpsShowIdx + dir).clamp(0, _fpsShowOptions.length - 1);
        if (next == _fpsShowIdx) return;
        setState(() => _fpsShowIdx = next);
        SettingsService.instance.setPs2FpsShow(_fpsShowOptions[next]);
      case 7:
        final next = (_audioVolumeIdx + dir).clamp(0, _audioVolumeOptions.length - 1);
        if (next == _audioVolumeIdx) return;
        setState(() => _audioVolumeIdx = next);
        SettingsService.instance.setPs2AudioVolume(_audioVolumeOptions[next]);
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
    await SettingsService.instance.resetPs2();
    DebugLogger.log('[Playstation2SettingsPage] settings reset to defaults');
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
              l.playstation2SettingsTitle,
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
                      icon: Icons.tv,
                      label: l.ps2UpscaleMultiplier,
                      value: l.ps2UpscaleLabels[_upscaleIdx],
                      selected: _selectedIndex == 0,
                      canLeft:  _upscaleIdx > 0,
                      canRight: _upscaleIdx < _upscaleOptions.length - 1,
                    ),
                  ),
                  KeyedSubtree(
                    key: _rowKeys[1],
                    child: _OptionRow(
                      icon: Icons.texture,
                      label: l.ps2BilinearFilter,
                      value: l.ps2BilinearLabels[_bilinearIdx],
                      selected: _selectedIndex == 1,
                      canLeft:  _bilinearIdx > 0,
                      canRight: _bilinearIdx < _bilinearOptions.length - 1,
                    ),
                  ),
                  KeyedSubtree(
                    key: _rowKeys[2],
                    child: _OptionRow(
                      icon: Icons.blur_on,
                      label: l.ps2Fxaa,
                      value: l.ps2FxaaLabels[_fxaaIdx],
                      selected: _selectedIndex == 2,
                      canLeft:  _fxaaIdx > 0,
                      canRight: _fxaaIdx < _fxaaOptions.length - 1,
                    ),
                  ),
                  KeyedSubtree(
                    key: _rowKeys[3],
                    child: _OptionRow(
                      icon: Icons.developer_board,
                      label: l.ps2Renderer,
                      value: l.ps2RendererLabels[_rendererIdx],
                      selected: _selectedIndex == 3,
                      canLeft:  _rendererIdx > 0,
                      canRight: _rendererIdx < _rendererOptions.length - 1,
                    ),
                  ),
                  KeyedSubtree(
                    key: _rowKeys[4],
                    child: _OptionRow(
                      icon: Icons.layers,
                      label: l.ps2BlendingAccuracy,
                      value: l.ps2BlendingLabels[_blendingIdx],
                      selected: _selectedIndex == 4,
                      canLeft:  _blendingIdx > 0,
                      canRight: _blendingIdx < _blendingOptions.length - 1,
                    ),
                  ),
                  KeyedSubtree(
                    key: _rowKeys[5],
                    child: _OptionRow(
                      icon: Icons.aspect_ratio,
                      label: l.aspectRatio,
                      value: l.ps2AspectLabels[_aspectIdx],
                      selected: _selectedIndex == 5,
                      canLeft:  _aspectIdx > 0,
                      canRight: _aspectIdx < _aspectOptions.length - 1,
                    ),
                  ),
                  KeyedSubtree(
                    key: _rowKeys[6],
                    child: _OptionRow(
                      icon: Icons.query_stats,
                      label: l.showFps,
                      value: l.fpsShowLabels[_fpsShowIdx],
                      selected: _selectedIndex == 6,
                      canLeft:  _fpsShowIdx > 0,
                      canRight: _fpsShowIdx < _fpsShowOptions.length - 1,
                    ),
                  ),
                  KeyedSubtree(
                    key: _rowKeys[7],
                    child: _OptionRow(
                      icon: Icons.volume_up,
                      label: l.audioGain,
                      value: l.audioGainValue(_audioVolumeOptions[_audioVolumeIdx]),
                      selected: _selectedIndex == 7,
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
                    key: _rowKeys[8],
                    child: _ActionRow(
                      icon: Icons.restore,
                      label: l.restoreDefaults,
                      selected: _selectedIndex == 8,
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
