import 'dart:io';
import 'package:flutter/material.dart';
import '../utils/debug_logger.dart';
import '../utils/app_localizations.dart';

class RestartPage extends StatefulWidget {
  const RestartPage({super.key});

  @override
  State<RestartPage> createState() => _RestartPageState();
}

class _RestartPageState extends State<RestartPage> {
  @override
  void initState() {
    super.initState();
    _restart();
  }

  Future<void> _restart() async {
    DebugLogger.log('[RestartPage] running: systemctl reboot');
    final result = await Process.run('systemctl', ['reboot']);
    DebugLogger.log('[RestartPage] systemctl exit code: ${result.exitCode}');
    if (result.stderr.toString().isNotEmpty) {
      DebugLogger.log('[RestartPage] systemctl stderr: ${result.stderr}');
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
              l.restarting,
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
