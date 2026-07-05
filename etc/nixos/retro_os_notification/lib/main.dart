import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
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

class NotificationWindow extends StatefulWidget {
  const NotificationWindow({super.key});

  @override
  State<NotificationWindow> createState() => _NotificationWindowState();
}

class _NotificationWindowState extends State<NotificationWindow> {
  static const _channel = MethodChannel('notification_window');
  static const _gold = Color(0xFFFFB300);

  String _header = '';
  String _title = '';
  int _points = 0;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    stdin.transform(utf8.decoder).transform(const LineSplitter()).listen(_onMessage);
  }

  void _onMessage(String line) {
    final data = jsonDecode(line) as Map<String, dynamic>;
    _hideTimer?.cancel();
    setState(() {
      _header = data['header'] as String? ?? '';
      _title = data['title'] as String? ?? '';
      _points = data['points'] as int? ?? 0;
    });
    _channel.invokeMethod('show');
    _hideTimer = Timer(
      Duration(seconds: data['seconds'] as int? ?? 4),
      () => _channel.invokeMethod('hide'),
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.black,
        border: Border.fromBorderSide(BorderSide(color: Color(0x55FFB300))),
      ),
      child: Column(
        children: [
          const SizedBox(height: 2, child: ColoredBox(color: _gold)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                      _header,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'PressStart',
                        color: _gold,
                        fontSize: 6,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Row(
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1200),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const SizedBox(
                            width: 34,
                            height: 34,
                            child: Icon(Icons.emoji_events, color: _gold, size: 20),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _title,
                            style: const TextStyle(
                              fontFamily: 'PressStart',
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      '+$_points pts',
                      style: const TextStyle(
                        fontFamily: 'PressStart',
                        color: _gold,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
