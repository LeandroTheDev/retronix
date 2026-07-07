import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/achievements/achievement.dart';
import '../services/gamepad_service.dart';
import '../utils/app_localizations.dart';
import '../utils/debug_logger.dart';
import '../utils/dialogs.dart';
import '../utils/devices.dart';
import '../widgets/achievement_row.dart';
import 'pc_game_open.dart';

class PcGameDetailsPage extends StatefulWidget {
  const PcGameDetailsPage({super.key, required this.gameName});

  final String gameName;

  @override
  State<PcGameDetailsPage> createState() => _PcGameDetailsPageState();
}

class _PcGameDetailsPageState extends State<PcGameDetailsPage> {
  static const _console = 'PC';

  List<Achievement> _achievements = [];
  Set<String> _unlockedIds = {};
  int _totalPlaytimeSecs = 0;
  bool _loading = true;
  late final StreamSubscription<GamepadAction> _sub;
  final _scrollController = ScrollController();

  // 0 = Play, 1 = Reset Achievements
  int _focusedButton = 0;

  @override
  void initState() {
    super.initState();
    _sub = GamepadService.instance.actions.listen(_handleAction);
    DebugLogger.log('[PcGameDetailsPage] initState — subscribed to gamepad stream');
    _load();
  }

  @override
  void dispose() {
    _sub.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final defFile = File(getGameAchievementsPath(_console, widget.gameName));
    var achievements = <Achievement>[];
    if (await defFile.exists()) {
      try {
        final list = json.decode(await defFile.readAsString()) as List;
        achievements = list.map((e) => Achievement.fromJson(e as Map<String, dynamic>)).toList();
      } catch (e) {
        DebugLogger.log('[PcGameDetailsPage] failed to parse achievements: $e');
      }
    }

    var unlockedIds = <String>{};
    final progressFile = File(getGameProgressPath(_console, widget.gameName));
    if (await progressFile.exists()) {
      try {
        final list = json.decode(await progressFile.readAsString()) as List;
        unlockedIds = list.cast<String>().toSet();
      } catch (e) {
        DebugLogger.log('[PcGameDetailsPage] failed to parse progress: $e');
      }
    }

    var totalPlaytimeSecs = 0;
    final playtimeFile = File(getGamePlaytimePath(_console, widget.gameName));
    if (await playtimeFile.exists()) {
      try {
        final data = json.decode(await playtimeFile.readAsString()) as Map<String, dynamic>;
        totalPlaytimeSecs = (data['total_playtime_seconds'] as int?) ?? 0;
      } catch (e) {
        DebugLogger.log('[PcGameDetailsPage] failed to parse playtime: $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _achievements = achievements;
      _unlockedIds = unlockedIds;
      _totalPlaytimeSecs = totalPlaytimeSecs;
      _loading = false;
    });
  }

  void _handleAction(GamepadAction action) {
    DebugLogger.log('[PcGameDetailsPage] _handleAction: $action isCurrent=${ModalRoute.of(context)?.isCurrent}');
    if (ModalRoute.of(context)?.isCurrent != true) return;
    final hasReset = _unlockedIds.isNotEmpty;
    switch (action) {
      case GamepadAction.back:
        Navigator.pop(context);
      case GamepadAction.confirm:
        if (_focusedButton == 1 && hasReset) {
          _confirmResetAchievements(AppLocalizations.of(context));
        } else {
          _playGame();
        }
      case GamepadAction.left:
        if (hasReset && _focusedButton == 1) setState(() => _focusedButton = 0);
      case GamepadAction.right:
        if (hasReset && _focusedButton == 0) setState(() => _focusedButton = 1);
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
      MaterialPageRoute(builder: (_) => PcGameOpen(gameName: widget.gameName)),
    );
    if (!mounted) return;
    if (error != null) {
      Navigator.pop(context, error);
      return;
    }
    setState(() => _focusedButton = 0);
    _load();
  }

  Future<void> _confirmResetAchievements(AppLocalizations l) async {
    final confirmed = await showConfirmDialog(
      context,
      message: l.resetAchievementsConfirm,
      labelYes: l.resetAchievementsButton,
      labelNo: l.cancel,
    );
    if (!confirmed || !mounted) return;

    final progressFile = File(getGameProgressPath(_console, widget.gameName));
    if (await progressFile.exists()) await progressFile.delete();
    DebugLogger.log('[PcGameDetailsPage] achievements reset for ${widget.gameName}');
    if (mounted) setState(() => _unlockedIds = {});
  }

  String _fmtPlaytime(AppLocalizations l) {
    if (_totalPlaytimeSecs == 0) return l.neverPlayed;
    final d = Duration(seconds: _totalPlaytimeSecs);
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
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
                            child: const Icon(Icons.computer, color: Colors.white30, size: 40),
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
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.timer_outlined, color: Colors.white38, size: 14),
                            const SizedBox(width: 6),
                            Text(
                              '${l.totalPlaytime}: ${_fmtPlaytime(l)}',
                              style: const TextStyle(color: Colors.white38, fontSize: 13, letterSpacing: 1),
                            ),
                          ],
                        ),
                        if (!_loading && _achievements.isNotEmpty) ...[
                          const SizedBox(height: 4),
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
                        Row(
                          children: [
                            _PlayButton(
                              label: l.play,
                              onTap: _playGame,
                              focused: _focusedButton == 0,
                            ),
                            if (!_loading && _unlockedIds.isNotEmpty) ...[
                              const SizedBox(width: 12),
                              _ResetButton(
                                label: l.resetAchievements,
                                onTap: () => _confirmResetAchievements(l),
                                focused: _focusedButton == 1,
                              ),
                            ],
                          ],
                        ),
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
        return AchievementRow(achievement: a, unlocked: _unlockedIds.contains(a.id), l: l);
      },
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.label, required this.onTap, required this.focused});

  final String label;
  final VoidCallback onTap;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        decoration: BoxDecoration(
          color: focused ? Colors.white : Colors.white24,
          borderRadius: BorderRadius.circular(8),
          boxShadow: focused
              ? [BoxShadow(color: Colors.white.withValues(alpha: 0.3), blurRadius: 12, spreadRadius: 1)]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_arrow, color: focused ? Colors.black : Colors.white70),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: focused ? Colors.black : Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResetButton extends StatelessWidget {
  const _ResetButton({required this.label, required this.onTap, required this.focused});

  final String label;
  final VoidCallback onTap;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: focused ? Colors.redAccent.withValues(alpha: 0.15) : Colors.transparent,
          border: Border.all(
            color: focused ? Colors.redAccent : Colors.redAccent.withValues(alpha: 0.4),
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: focused
              ? [BoxShadow(color: Colors.redAccent.withValues(alpha: 0.25), blurRadius: 12, spreadRadius: 1)]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.restart_alt, color: Colors.redAccent, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
          ],
        ),
      ),
    );
  }
}
