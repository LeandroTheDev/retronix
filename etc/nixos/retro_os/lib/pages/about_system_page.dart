import 'dart:async';
import 'package:flutter/material.dart';
import '../services/gamepad_service.dart';
import '../utils/app_localizations.dart';
import '../utils/system_info.dart';

class AboutSystemPage extends StatefulWidget {
  const AboutSystemPage({super.key});

  @override
  State<AboutSystemPage> createState() => _AboutSystemPageState();
}

class _AboutSystemPageState extends State<AboutSystemPage> {
  late final StreamSubscription<GamepadAction> _sub;
  final _scrollController = ScrollController();
  bool _loading = true;

  static const _scrollStep = 80.0;

  String _device = '';
  String _architecture = '';
  String _display = '';
  String _openGl = '';
  String _renderer = '';

  @override
  void initState() {
    super.initState();
    _sub = GamepadService.instance.actions.listen(_handleAction);
    _load();
  }

  @override
  void dispose() {
    _sub.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final device = await getDeviceModel();
    final architecture = await getCpuArchitecture();
    final display = await getDisplayMode();
    final openGl = await getOpenGlVersion();
    final renderer = await getOpenGlRenderer();
    if (!mounted) return;
    setState(() {
      _device = device;
      _architecture = architecture;
      _display = display;
      _openGl = openGl;
      _renderer = renderer;
      _loading = false;
    });
  }

  void _handleAction(GamepadAction action) {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    switch (action) {
      case GamepadAction.back:
        Navigator.pop(context);
      case GamepadAction.up:
        _scrollBy(-_scrollStep);
      case GamepadAction.down:
        _scrollBy(_scrollStep);
      default:
        break;
    }
  }

  void _scrollBy(double delta) {
    if (!_scrollController.hasClients) return;
    final offset = (_scrollController.offset + delta)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
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
              l.aboutSystemTitle,
              style: const TextStyle(color: Colors.white54, fontSize: 16, letterSpacing: 5),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : ListView(
                    controller: _scrollController,
                    children: [
                      _InfoRow(icon: Icons.developer_board, label: l.aboutDevice, value: _device),
                      _InfoRow(icon: Icons.memory, label: l.aboutArchitecture, value: _architecture),
                      _InfoRow(icon: Icons.desktop_windows, label: l.aboutDisplay, value: _display),
                      _InfoRow(icon: Icons.view_in_ar, label: l.aboutOpenGl, value: _openGl),
                      _InfoRow(icon: Icons.videogame_asset, label: l.aboutRenderer, value: _renderer),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 80, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white54, size: 22),
          const SizedBox(width: 20),
          Expanded(
            flex: 3,
            child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 18)),
          ),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.right,
              softWrap: true,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white60, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
