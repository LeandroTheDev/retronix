import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/achievements/achievement.dart';
import '../services/gamepad_service.dart';
import '../utils/app_localizations.dart';
import '../utils/debug_logger.dart';
import '../utils/devices.dart';
import 'nintendo64_game_open.dart';

/// Shows one Nintendo 64 game before launching it: cover art, a Play button,
/// and its achievement list (read straight from `game_achievements.json` -
/// this is a read-only display, not the live [AchievementService] poll, so
/// it works without RetroArch running).
class Nintendo64GameDetailsPage extends StatefulWidget {
  const Nintendo64GameDetailsPage({super.key, required this.gameName});

  final String gameName;

  @override
  State<Nintendo64GameDetailsPage> createState() => _Nintendo64GameDetailsPageState();
}

class _Nintendo64GameDetailsPageState extends State<Nintendo64GameDetailsPage> {
  static const _console = 'Nintendo 64';

  List<Achievement> _achievements = [];
  bool _loading = true;
  late final StreamSubscription<GamepadAction> _sub;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _sub = GamepadService.instance.actions.listen(_handleAction);
    _loadAchievements();
  }

  @override
  void dispose() {
    _sub.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAchievements() async {
    final file = File(getGameAchievementsPath(_console, widget.gameName));
    var achievements = <Achievement>[];
    if (await file.exists()) {
      try {
        final list = json.decode(await file.readAsString()) as List;
        achievements = list.map((e) => Achievement.fromJson(e as Map<String, dynamic>)).toList();
      } catch (e) {
        DebugLogger.log('[Nintendo64GameDetailsPage] failed to parse achievements for ${widget.gameName}: $e');
      }
    }
    if (!mounted) return;
    setState(() {
      _achievements = achievements;
      _loading = false;
    });
  }

  void _handleAction(GamepadAction action) {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    switch (action) {
      case GamepadAction.back:
        Navigator.pop(context);
      case GamepadAction.confirm:
        _playGame();
      case GamepadAction.up:
        _scrollController.animateTo(
          (_scrollController.offset - 176).clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      case GamepadAction.down:
        _scrollController.animateTo(
          (_scrollController.offset + 176).clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      default:
        break;
    }
  }

  Future<void> _playGame() async {
    final error = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => Nintendo64GameOpen(gameName: widget.gameName)),
    );
    if (!mounted) return;
    if (error != null) {
      // Propagate launch failures up to the games list, same as before this
      // page existed - the games list is what owns the error snackbar.
      Navigator.pop(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final imagePath = getGameImagePath(_console, widget.gameName);
    final totalPoints = _achievements.fold<int>(0, (sum, a) => sum + a.points);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(80, 48, 80, 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: imagePath != null
                        ? Image.file(File(imagePath), width: 96, height: 96, fit: BoxFit.cover)
                        : Container(
                            width: 96,
                            height: 96,
                            color: Colors.white10,
                            child: const Icon(Icons.videogame_asset, color: Colors.white30, size: 40),
                          ),
                  ),
                  const SizedBox(width: 28),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.gameName.toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 3, fontWeight: FontWeight.bold),
                        ),
                        if (!_loading && _achievements.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            l.achievementsSummary(_achievements.length, totalPoints),
                            style: const TextStyle(color: Colors.white38, fontSize: 14, letterSpacing: 1),
                          ),
                        ],
                        const SizedBox(height: 20),
                        _PlayButton(label: l.play, onTap: _playGame),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(80, 0, 80, 12),
              child: Divider(color: Colors.white12, height: 1),
            ),
            Expanded(child: _buildAchievementsList(l)),
          ],
        ),
      ),
    );
  }

  Widget _buildAchievementsList(AppLocalizations l) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_achievements.isEmpty) {
      return Center(
        child: Text(l.noAchievementsFound, style: const TextStyle(color: Colors.white30, fontSize: 16)),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 8),
      itemCount: _achievements.length,
      itemBuilder: (context, index) => _AchievementRow(achievement: _achievements[index], l: l),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_arrow, color: Colors.black),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2),
            ),
          ],
        ),
      ),
    );
  }
}

// Achievement icons aren't authored yet (see game_achievements.json - there's
// no image field on Achievement at all), so every row uses the same trophy
// placeholder rather than trying to guess a per-achievement asset.
class _AchievementRow extends StatelessWidget {
  const _AchievementRow({required this.achievement, required this.l});

  final Achievement achievement;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4)),
            child: const Icon(Icons.emoji_events, color: Colors.white30, size: 26),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  achievement.title,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                if (achievement.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    achievement.description,
                    style: const TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)),
            child: Text(
              l.achievementPoints(achievement.points),
              style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
