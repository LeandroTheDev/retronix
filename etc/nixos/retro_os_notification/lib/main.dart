import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

void main(List<String> args) {
  runApp(const NotificationApp());
}

class NotificationApp extends StatelessWidget {
  const NotificationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'PressStart'),
      home: const NotificationWindow(),
    );
  }
}

class NotificationWindow extends StatefulWidget {
  const NotificationWindow({super.key});

  @override
  State<NotificationWindow> createState() => _NotificationWindowState();
}

class _NotificationWindowState extends State<NotificationWindow> with SingleTickerProviderStateMixin {
  String _title = '';
  int _points = 0;
  Timer? _hideTimer;
  late final AnimationController _controller;
  late final Animation<Offset> _slide;

  static const _gold = Color(0xFFFFB300);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slide = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    stdin.transform(utf8.decoder).transform(const LineSplitter()).listen(_onMessage);
  }

  void _onMessage(String line) {
    final data = jsonDecode(line) as Map<String, dynamic>;
    final title = data['title'] as String? ?? '';
    final points = data['points'] as int? ?? 0;
    final seconds = data['seconds'] as int? ?? 4;

    _hideTimer?.cancel();
    setState(() {
      _title = title;
      _points = points;
    });
    _controller.forward(from: 0.0);
    _hideTimer = Timer(Duration(seconds: seconds), () {
      _controller.reverse();
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slide,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: BoxDecoration(border: Border.all(color: const Color(0x55FFB300), width: 1)),
          child: Column(
            children: [
              Container(height: 2, color: _gold),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: const Color(0x22FFB300),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(Icons.emoji_events, color: _gold, size: 20),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 220,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'CONQUISTA DESBLOQUEADA',
                                style: TextStyle(color: _gold, fontSize: 6, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _title,
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '+$_points pts',
                                style: const TextStyle(color: _gold, fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
