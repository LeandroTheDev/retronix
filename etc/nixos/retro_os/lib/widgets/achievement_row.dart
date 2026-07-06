import 'package:flutter/material.dart';
import '../services/achievements/achievement.dart';
import '../utils/app_localizations.dart';

class AchievementRow extends StatelessWidget {
  const AchievementRow({
    super.key,
    required this.achievement,
    required this.unlocked,
    required this.l,
    this.isNew = false,
  });

  final Achievement achievement;
  final bool unlocked;
  final AppLocalizations l;
  // Highlighted in amber when unlocked during the current session
  final bool isNew;

  static const _gold    = Color(0xFFFFB300);
  static const _goldDim = Color(0x33FFB300);

  @override
  Widget build(BuildContext context) {
    final Color trophyColor;
    final Color badgeColor;
    final Color badgeBg;
    if (isNew) {
      trophyColor = _gold;
      badgeColor  = _gold;
      badgeBg     = _goldDim;
    } else if (unlocked) {
      trophyColor = _gold;
      badgeColor  = _gold;
      badgeBg     = _goldDim;
    } else {
      trophyColor = Colors.white30;
      badgeColor  = Colors.white54;
      badgeBg     = Colors.white10;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: unlocked ? const Color(0x14FFB300) : Colors.white10,
        borderRadius: BorderRadius.circular(8),
        border: unlocked ? Border.all(color: _goldDim) : null,
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
            child: Icon(Icons.emoji_events, color: trophyColor, size: 26),
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
            decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (unlocked) ...[
                  Icon(Icons.check, color: badgeColor, size: 12),
                  const SizedBox(width: 4),
                ],
                Text(
                  l.achievementPoints(achievement.points),
                  style: TextStyle(color: badgeColor, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
