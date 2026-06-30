import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/gamepad_service.dart';
import '../utils/debug_logger.dart';
import '../utils/devices.dart';
import '../utils/app_localizations.dart';
import 'nintendo64_game_open.dart';

class Nintendo64GamesPage extends StatefulWidget {
  const Nintendo64GamesPage({super.key});

  @override
  State<Nintendo64GamesPage> createState() => _Nintendo64GamesPageState();
}

class _Nintendo64GamesPageState extends State<Nintendo64GamesPage> {
  List<String> _games = [];
  int _selectedIndex = 0;
  bool _loading = true;
  late final StreamSubscription<GamepadAction> _sub;
  final _scrollController = ScrollController();

  static const _itemHeight = 88.0;

  @override
  void initState() {
    super.initState();
    _sub = GamepadService.instance.actions.listen(_handleAction);
    _loadGames();
  }

  @override
  void dispose() {
    _sub.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadGames() async {
    final games = await getAvailableGames('Nintendo 64');
    if (!mounted) return;
    setState(() {
      _games = games;
      _loading = false;
    });
  }

  void _handleAction(GamepadAction action) {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    DebugLogger.log('[Nintendo64GamesPage] action: $action | loading: $_loading | games: ${_games.length}');
    if (action == GamepadAction.back) {
      DebugLogger.log('[Nintendo64GamesPage] popping');
      Navigator.pop(context);
      return;
    }
    if (_games.isEmpty) return;
    switch (action) {
      case GamepadAction.up:
        setState(() {
          _selectedIndex = (_selectedIndex - 1).clamp(0, _games.length - 1);
        });
        _scrollToSelected();
      case GamepadAction.down:
        setState(() {
          _selectedIndex = (_selectedIndex + 1).clamp(0, _games.length - 1);
        });
        _scrollToSelected();
      case GamepadAction.confirm:
        _launchGame();
      default:
        break;
    }
  }

  void _scrollToSelected() {
    final offset = (_selectedIndex * _itemHeight) -
        (_scrollController.position.viewportDimension / 2) +
        (_itemHeight / 2);
    _scrollController.animateTo(
      offset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  Future<void> _launchGame() async {
    final game = _games[_selectedIndex];
    final error = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => Nintendo64GameOpen(gameName: game)),
    );
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error, style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.red[900],
          duration: const Duration(seconds: 5),
        ),
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
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Text(
              'NINTENDO 64',
              style: TextStyle(
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
    if (_games.isEmpty) {
      return Center(
        child: Text(
          l.noGameFound,
          style: const TextStyle(color: Colors.white30, fontSize: 16),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      itemCount: _games.length,
      itemExtent: _itemHeight,
      itemBuilder: (context, index) => _GameItem(
        console: 'Nintendo 64',
        name: _games[index],
        selected: index == _selectedIndex,
      ),
    );
  }
}

class _GameItem extends StatelessWidget {
  const _GameItem({
    required this.console,
    required this.name,
    required this.selected,
  });

  final String console;
  final String name;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final imagePath = getGameImagePath(console, name);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.symmetric(horizontal: 80, vertical: 6),
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
                ? Image.file(
                    File(imagePath),
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 56,
                    height: 56,
                    color: selected ? Colors.black12 : Colors.white10,
                    child: Icon(
                      Icons.videogame_asset,
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
                fontSize: 20,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
