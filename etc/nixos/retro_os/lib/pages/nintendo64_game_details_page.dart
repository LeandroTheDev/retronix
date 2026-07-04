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
  Set<String> _unlockedIds = {};
  bool _loading = true;
  late final StreamSubscription<GamepadAction> _sub;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _sub = GamepadService.instance.actions.listen(_handleAction);
    DebugLogger.log('[Nintendo64GameDetailsPage] initState — subscribed to gamepad stream');
    _loadAchievements();
  }

  @override
  void dispose() {
    _sub.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAchievements() async {
    final defFile = File(getGameAchievementsPath(_console, widget.gameName));
    var achievements = <Achievement>[];
    if (await defFile.exists()) {
      try {
        final list = json.decode(await defFile.readAsString()) as List;
        achievements = list.map((e) => Achievement.fromJson(e as Map<String, dynamic>)).toList();
      } catch (e) {
        DebugLogger.log('[Nintendo64GameDetailsPage] failed to parse achievements for ${widget.gameName}: $e');
      }
    }

    var unlockedIds = <String>{};
    final progressFile = File(getGameProgressPath(_console, widget.gameName));
    if (await progressFile.exists()) {
      try {
        final list = json.decode(await progressFile.readAsString()) as List;
        unlockedIds = list.cast<String>().toSet();
      } catch (e) {
        DebugLogger.log('[Nintendo64GameDetailsPage] failed to parse progress for ${widget.gameName}: $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _achievements = achievements;
      _unlockedIds = unlockedIds;
      _loading = false;
    });
  }

  void _handleAction(GamepadAction action) {
    DebugLogger.log('[Nintendo64GameDetailsPage] _handleAction: $action isCurrent=${ModalRoute.of(context)?.isCurrent}');
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
    final unlockedCount = _achievements.where((a) => _unlockedIds.contains(a.id)).length;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(80, 80, 80, 24),
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
                          if (unlockedCount > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              l.achievementsUnlockedSummary(unlockedCount, _achievements.length),
                              style: const TextStyle(color: Color(0xFFFFB300), fontSize: 13, letterSpacing: 1),
                            ),
                          ],
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
      itemBuilder: (context, index) {
        final a = _achievements[index];
        return _AchievementRow(achievement: a, unlocked: _unlockedIds.contains(a.id), l: l);
      },
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

class _AchievementRow extends StatelessWidget {
  const _AchievementRow({required this.achievement, required this.unlocked, required this.l});

  final Achievement achievement;
  final bool unlocked;
  final AppLocalizations l;

  static const _gold = Color(0xFFFFB300);
  static const _goldDim = Color(0x33FFB300);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: unlocked ? const Color(0x14FFB300) : Colors.white10,
        borderRadius: BorderRadius.circular(8),
        border: unlocked ? Border.all(color: _goldDim, width: 1) : null,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: unlocked ? const Color(0x22FFB300) : Colors.white10,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              Icons.emoji_events,
              color: unlocked ? _gold : Colors.white30,
              size: 26,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  achievement.title,
                  style: TextStyle(
                    color: unlocked ? Colors.white : Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (achievement.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    achievement.description,
                    style: TextStyle(
                      color: unlocked ? Colors.white54 : Colors.white30,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: unlocked ? _goldDim : Colors.white10,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (unlocked) ...[
                  const Icon(Icons.check, color: _gold, size: 12),
                  const SizedBox(width: 4),
                ],
                Text(
                  l.achievementPoints(achievement.points),
                  style: TextStyle(
                    color: unlocked ? _gold : Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
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
