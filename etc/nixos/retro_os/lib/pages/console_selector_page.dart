import 'dart:async';
import 'package:flutter/material.dart';
import '../services/gamepad_service.dart';
import 'dart:io';
import '../utils/debug_logger.dart';
import '../utils/devices.dart';
import '../utils/dialogs.dart';
import '../utils/app_localizations.dart';
import 'nintendo64_games_page.dart';
import 'system_settings_page.dart';
import 'update_system_page.dart';
import 'nintendo64_settings_page.dart';
import 'shutdown_page.dart';

class ConsoleSelectorPage extends StatefulWidget {
  const ConsoleSelectorPage({super.key});

  @override
  State<ConsoleSelectorPage> createState() => _ConsoleSelectorPageState();
}

class _ConsoleSelectorPageState extends State<ConsoleSelectorPage> {
  List<String> _consoles = [];
  int _selectedIndex = 0;
  bool _loading = true;
  late final StreamSubscription<GamepadAction> _sub;

  @override
  void initState() {
    super.initState();
    _sub = GamepadService.instance.actions.listen(_handleAction);
    _loadConsoles();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  Future<void> _loadConsoles() async {
    final consoles = await getAvailableConsoles();
    setState(() {
      _consoles = consoles;
      _loading = false;
    });
  }

  void _handleAction(GamepadAction action) {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    if (action == GamepadAction.back) {
      _showExitDialog();
      return;
    }
    if (action == GamepadAction.start) {
      _showSettingsDialog();
      return;
    }
    if (_consoles.isEmpty) return;
    switch (action) {
      case GamepadAction.up:
        setState(() {
          _selectedIndex = (_selectedIndex - 1).clamp(0, _consoles.length - 1);
        });
      case GamepadAction.down:
        setState(() {
          _selectedIndex = (_selectedIndex + 1).clamp(0, _consoles.length - 1);
        });
      case GamepadAction.confirm:
        _navigate();
      default:
        break;
    }
  }

  void _navigate() {
    final console = _consoles[_selectedIndex];
    if (console == 'Nintendo 64') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const Nintendo64GamesPage()),
      );
    }
  }

  void _showSettingsDialog() {
    DebugLogger.log('[ConsoleSelectorPage] settings dialog opened');
    final l = AppLocalizations.of(context);
    showSettingsDialog(
      context,
      title: l.settingsDialogTitle,
      options: [
        SettingsOption(
          label: l.settingsNintendo64,
          icon: Icons.sports_esports,
          onSelect: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const Nintendo64SettingsPage()),
          ),
        ),
        SettingsOption(
          label: l.systemSettingsTitle,
          icon: Icons.settings,
          onSelect: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SystemSettingsPage()),
          ),
        ),
        SettingsOption(
          label: l.updateSystem,
          icon: Icons.system_update_alt,
          onSelect: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const UpdateSystemPage()),
          ),
        ),
        SettingsOption(
          label: l.aboutSystem,
          icon: Icons.info_outline,
          onSelect: () {},
        ),
        SettingsOption(
          label: l.shutdown,
          icon: Icons.power_settings_new,
          onSelect: () {
            Navigator.pop(context); // fecha o settings dialog antes
            _showExitDialog();
          },
        ),
      ],
    );
  }

  Future<void> _showExitDialog() async {
    DebugLogger.log('[ConsoleSelectorPage] exit dialog opened');
    final l = AppLocalizations.of(context);

    final confirmed = await showConfirmDialog(
      context,
      message: l.shutdownConfirm,
      labelYes: l.yes,
      labelNo: l.no,
    );

    DebugLogger.log('[ConsoleSelectorPage] exit dialog closed — confirmed: $confirmed');

    if (!mounted) return;
    if (confirmed) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const ShutdownPage()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Text(
              l.selectConsole,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 18,
                letterSpacing: 6,
              ),
            ),
          ),
          Expanded(child: _buildBody(l)),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations l) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_consoles.isEmpty) {
      return Center(
        child: Text(
          l.noConsoleFound,
          style: const TextStyle(color: Colors.white30, fontSize: 16),
        ),
      );
    }
    return ListView.builder(
      itemCount: _consoles.length,
      itemBuilder: (context, index) => _ConsoleItem(
        name: _consoles[index],
        selected: index == _selectedIndex,
      ),
    );
  }
}

class _ConsoleItem extends StatelessWidget {
  const _ConsoleItem({required this.name, required this.selected});

  final String name;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final imagePath = getConsoleImagePath(name);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.symmetric(horizontal: 80, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: selected ? Colors.white : Colors.white10,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: imagePath != null
                ? Image.file(File(imagePath), width: 56, height: 56, fit: BoxFit.contain)
                : Container(
                    width: 56,
                    height: 56,
                    color: selected ? Colors.black12 : Colors.white10,
                    child: Icon(
                      Icons.sports_esports,
                      color: selected ? Colors.black38 : Colors.white30,
                    ),
                  ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color: selected ? Colors.black : Colors.white,
                fontSize: 24,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
