import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

void main(List<String> args) {
  final seconds = args.isNotEmpty ? int.tryParse(args[0]) ?? 2 : 2;
  Timer(Duration(seconds: seconds), () => exit(0));
  runApp(const NotificationApp());
}

class NotificationApp extends StatelessWidget {
  const NotificationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: NotificationWindow(),
    );
  }
}

class NotificationWindow extends StatelessWidget {
  const NotificationWindow({super.key});

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
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'CONQUISTA DESBLOQUEADA',
                            style: TextStyle(
                              color: _gold,
                              fontSize: 6,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Conquista de Teste',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 2),
                          Text(
                            '+25 pts',
                            style: TextStyle(
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
