import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

void main(List<String> args) {
  final title = args.isNotEmpty ? args[0] : 'Conquista Desbloqueada';
  final points = args.length > 1 ? int.tryParse(args[1]) ?? 0 : 0;
  final seconds = args.length > 2 ? int.tryParse(args[2]) ?? 4 : 4;

  Timer(Duration(seconds: seconds), () => exit(0));
  runApp(NotificationApp(title: title, points: points));
}

class NotificationApp extends StatelessWidget {
  const NotificationApp({super.key, required this.title, required this.points});

  final String title;
  final int points;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'PressStart'),
      home: NotificationWindow(title: title, points: points),
    );
  }
}

class NotificationWindow extends StatelessWidget {
  const NotificationWindow({super.key, required this.title, required this.points});

  final String title;
  final int points;

  static const _gold = Color(0xFFFFB300);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      body: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0x55FFB300), width: 1),
        ),
        child: Column(
          children: [
            Container(height: 2, color: _gold),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'CONQUISTA DESBLOQUEADA',
                            style: TextStyle(
                              color: _gold,
                              fontSize: 6,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '+$points pts',
                            style: const TextStyle(
                              color: _gold,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
