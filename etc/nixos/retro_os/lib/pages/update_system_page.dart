import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/gamepad_service.dart';
import '../utils/debug_logger.dart';
import '../utils/app_localizations.dart';
import '../utils/dialogs.dart';
import '../utils/locale_service.dart';

enum _UpdateState { idle, running, success, error }

class UpdateSystemPage extends StatefulWidget {
  const UpdateSystemPage({super.key});

  @override
  State<UpdateSystemPage> createState() => _UpdateSystemPageState();
}

class _UpdateSystemPageState extends State<UpdateSystemPage> {
  late final StreamSubscription<GamepadAction> _sub;
  final _scrollController = ScrollController();

  _UpdateState _state = _UpdateState.idle;
  final _outputLines = <String>[];
  Process? _process;

  @override
  void initState() {
    super.initState();
    _sub = GamepadService.instance.actions.listen(_handleAction);
  }

  @override
  void dispose() {
    _sub.cancel();
    _process?.kill();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleAction(GamepadAction action) {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    switch (action) {
      case GamepadAction.confirm:
        if (_state == _UpdateState.idle) _startUpdate();
      case GamepadAction.back:
        _process?.kill();
        Navigator.pop(context);
      default:
        break;
    }
  }

  static const _repoUrl = 'https://github.com/LeandroTheDev/retronix';
  static const _tmpDir  = '/tmp/retronix_update';

  Future<void> _startUpdate() async {
    DebugLogger.log('[UpdateSystemPage] starting update from $_repoUrl');
    setState(() {
      _state = _UpdateState.running;
      _outputLines.clear();
    });

    // Chain all steps in a single shell invocation so stdout/stderr are unified
    final script = [
      'rm -rf $_tmpDir',
      'git clone $_repoUrl $_tmpDir',
      'sudo rm -rf /etc/nixos',
      'sudo cp -r $_tmpDir/etc/nixos /etc/nixos',
      'rm -rf $_tmpDir',
      'sudo nixos-rebuild switch',
    ].join(' && ');

    try {
      _process = await Process.start('sh', ['-c', script]);

      _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_appendLine);

      _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_appendLine);

      final exitCode = await _process!.exitCode;
      DebugLogger.log('[UpdateSystemPage] script exited with code: $exitCode');

      if (!mounted) return;

      if (exitCode == 0) {
        setState(() => _state = _UpdateState.success);
        _scrollToBottom();
        final l = AppLocalizations(LocaleService.instance.locale);
        final reboot = await showConfirmDialog(
          context,
          message: l.updateRebootQuestion,
          labelYes: l.yes,
          labelNo: l.no,
        );
        if (!mounted) return;
        if (reboot) {
          DebugLogger.log('[UpdateSystemPage] rebooting system');
          await Process.run('systemctl', ['reboot']);
        } else {
          Navigator.pop(context);
        }
      } else if (exitCode == -15) {
        // -15 = SIGTERM, user pressed Back — page already popped, nothing to do
      } else {
        setState(() => _state = _UpdateState.error);
        _scrollToBottom();
      }
    } catch (e) {
      DebugLogger.log('[UpdateSystemPage] failed to start script: $e');
      if (!mounted) return;
      setState(() {
        _outputLines.add('$e');
        _state = _UpdateState.error;
      });
    }
  }

  void _appendLine(String line) {
    if (!mounted) return;
    setState(() => _outputLines.add(line));
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 80),
            child: Text(
              l.updateTitle,
              style: const TextStyle(color: Colors.white54, fontSize: 16, letterSpacing: 2),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 80),
              child: _buildBody(l),
            ),
          ),
          _buildFooter(l),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations l) {
    if (_state == _UpdateState.idle) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.system_update_alt, color: Colors.white24, size: 64),
            const SizedBox(height: 24),
            Text(
              l.updateIdle,
              style: const TextStyle(color: Colors.white54, fontSize: 18),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusBadge(state: _state, l: l),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _outputLines.length,
              itemBuilder: (_, i) => Text(
                _outputLines[i],
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontFamily: 'monospace',
                  height: 1.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(AppLocalizations l) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 24),
      child: Text(
        l.updateBackHint,
        style: const TextStyle(color: Colors.white24, fontSize: 13),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.state, required this.l});

  final _UpdateState state;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (state) {
      _UpdateState.running => (Icons.sync, Colors.blue, l.updateRunning),
      _UpdateState.success => (Icons.check_circle_outline, Colors.green, l.updateSuccess),
      _UpdateState.error   => (Icons.error_outline, Colors.red, l.updateError),
      _UpdateState.idle    => (Icons.info_outline, Colors.white54, ''),
    };

    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: color, fontSize: 15)),
      ],
    );
  }
}
