import 'dart:io';
import 'package:flutter/material.dart';
import '../utils/debug_logger.dart';
import '../utils/app_localizations.dart';

class ShutdownPage extends StatefulWidget {
  const ShutdownPage({super.key});

  @override
  State<ShutdownPage> createState() => _ShutdownPageState();
}

class _ShutdownPageState extends State<ShutdownPage> {
  @override
  void initState() {
    super.initState();
    _shutdown();
  }

  Future<void> _shutdown() async {
    DebugLogger.log('[ShutdownPage] running: systemctl poweroff');
    final result = await Process.run('systemctl', ['poweroff']);
    DebugLogger.log('[ShutdownPage] systemctl exit code: ${result.exitCode}');
    if (result.stderr.toString().isNotEmpty) {
      DebugLogger.log('[ShutdownPage] systemctl stderr: ${result.stderr}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white54),
            const SizedBox(height: 32),
            Text(
              l.shuttingDown,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 20,
                letterSpacing: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
