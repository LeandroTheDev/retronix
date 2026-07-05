import 'dart:async';
import 'package:flutter/material.dart';
import '../services/achievements/achievement.dart';
import '../services/achievements/achievement_service.dart';
import '../utils/app_localizations.dart';

/// Sits on top of every screen (added in MaterialApp.builder Stack) and shows
/// a Steam-style slide-in toast whenever an achievement is unlocked.
/// Notifications queue — if two arrive at once the second waits for the first.
class AchievementNotificationOverlay extends StatefulWidget {
  const AchievementNotificationOverlay({super.key});

  @override
  State<AchievementNotificationOverlay> createState() =>
      _AchievementNotificationOverlayState();
}

class _AchievementNotificationOverlayState
    extends State<AchievementNotificationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  StreamSubscription<Achievement>? _sub;
  final _queue = <Achievement>[];
  Achievement? _current;
  Timer? _dismissTimer;

  static const _duration = Duration(milliseconds: 380);
  static const _holdDuration = Duration(seconds: 4);
  static const _gold = Color(0xFFFFB300);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _duration);
    _slide = Tween<Offset>(begin: const Offset(1.4, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _sub = AchievementService.instance.unlocked.listen(_onUnlocked);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _dismissTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onUnlocked(Achievement a) {
    _queue.add(a);
    if (_current == null) _showNext();
  }

  void _showNext() {
    if (_queue.isEmpty) return;
    setState(() => _current = _queue.removeAt(0));
    _ctrl.forward(from: 0);
    _dismissTimer?.cancel();
    _dismissTimer = Timer(_holdDuration, _dismiss);
  }

  void _dismiss() {
    _ctrl.reverse().then((_) {
      if (!mounted) return;
      setState(() => _current = null);
      _showNext();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_current == null) return const SizedBox.shrink();
    return Positioned(
      bottom: 40,
      right: 32,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: _Toast(achievement: _current!, gold: _gold),
        ),
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({required this.achievement, required this.gold});

  final Achievement achievement;
  final Color gold;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xF0111111),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x55FFB300), width: 1),
          boxShadow: const [
            BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0x22FFB300),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.emoji_events, color: Color(0xFFFFB300), size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l.achievementUnlocked,
                    style: const TextStyle(
                      color: Color(0xFFFFB300),
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    achievement.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l.achievementPointsGain(achievement.points),
                    style: const TextStyle(
                      color: Color(0xFFFFB300),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
