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

enum _StepStatus { pending, running, success, error }

class _Step {
  const _Step({required this.label, required this.command});

  final String Function(AppLocalizations) label;
  final String command;
}

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

  static final _steps = [_Step(label: (l) => l.updateStepCleanTmp, command: 'rm -rf $_tmpDir'), _Step(label: (l) => l.updateStepClone, command: 'git clone $_repoUrl $_tmpDir'), _Step(label: (l) => l.updateStepRemoveOld, command: 'sudo rm -rf /etc/nixos'), _Step(label: (l) => l.updateStepCopyNew, command: 'sudo cp -r $_tmpDir/etc/nixos /etc/nixos && rm -rf $_tmpDir'), _Step(label: (l) => l.updateStepRebuild, command: 'sudo nixos-rebuild boot')];

  late List<_StepStatus> _stepStatuses = List.filled(_steps.length, _StepStatus.pending);

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
  static const _tmpDir = '/tmp/retronix_update';

  Future<void> _startUpdate() async {
    DebugLogger.log('[UpdateSystemPage] starting update from $_repoUrl');
    final l = AppLocalizations(LocaleService.instance.locale);
    setState(() {
      _state = _UpdateState.running;
      _outputLines.clear();
      _stepStatuses = List.filled(_steps.length, _StepStatus.pending);
    });

    for (var i = 0; i < _steps.length; i++) {
      if (!mounted) return;
      final step = _steps[i];
      setState(() => _stepStatuses[i] = _StepStatus.running);
      _appendLine('\$ ${step.label(l)}');

      int exitCode;
      try {
        exitCode = await _runStep(step.command);
      } catch (e) {
        DebugLogger.log('[UpdateSystemPage] step "${step.label(l)}" failed to start: $e');
        if (!mounted) return;
        setState(() {
          _outputLines.add('$e');
          _stepStatuses[i] = _StepStatus.error;
          _state = _UpdateState.error;
        });
        _scrollToBottom();
        return;
      }

      DebugLogger.log('[UpdateSystemPage] step "${step.label(l)}" exited with code: $exitCode');
      if (!mounted) return;

      if (exitCode == -15) {
        // -15 = SIGTERM, user pressed Back — page already popped, nothing to do
        return;
      } else if (exitCode != 0) {
        setState(() {
          _stepStatuses[i] = _StepStatus.error;
          _state = _UpdateState.error;
        });
        _scrollToBottom();
        return;
      }

      setState(() => _stepStatuses[i] = _StepStatus.success);
    }

    if (!mounted) return;
    setState(() => _state = _UpdateState.success);
    _scrollToBottom();
    final reboot = await showConfirmDialog(context, message: l.updateRebootQuestion, labelYes: l.yes, labelNo: l.no);
    if (!mounted) return;
    if (reboot) {
      DebugLogger.log('[UpdateSystemPage] rebooting system');
      await Process.run('systemctl', ['reboot']);
    } else {
      Navigator.pop(context);
    }
  }

  Future<int> _runStep(String command) async {
    _process = await Process.start('sh', ['-c', command]);

    _process!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(_appendLine);

    _process!.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(_appendLine);

    return _process!.exitCode;
  }

  void _appendLine(String line) {
    if (!mounted) return;
    setState(() => _outputLines.add(line));
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
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
            child: Text(l.updateTitle, style: const TextStyle(color: Colors.white54, fontSize: 16, letterSpacing: 2)),
          ),
          Expanded(
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 80), child: _buildBody(l)),
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
        const SizedBox(height: 20),
        _StepList(steps: _steps, statuses: _stepStatuses, l: l),
        const SizedBox(height: 20),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _outputLines.length,
              itemBuilder: (_, i) => Text(
                _outputLines[i],
                style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Montserrat', height: 1.5),
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
      child: Text(l.updateBackHint, style: const TextStyle(color: Colors.white24, fontSize: 13)),
    );
  }
}

class _StepList extends StatelessWidget {
  const _StepList({required this.steps, required this.statuses, required this.l});

  final List<_Step> steps;
  final List<_StepStatus> statuses;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (var i = 0; i < steps.length; i++) _StepRow(step: steps[i], status: statuses[i], l: l)],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.status, required this.l});

  final _Step step;
  final _StepStatus status;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final Widget icon;
    final Color textColor;
    switch (status) {
      case _StepStatus.pending:
        icon = const Icon(Icons.radio_button_unchecked, color: Colors.white24, size: 16);
        textColor = Colors.white38;
      case _StepStatus.running:
        icon = const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue));
        textColor = Colors.white;
      case _StepStatus.success:
        icon = const Icon(Icons.check_circle, color: Colors.green, size: 18);
        textColor = Colors.white70;
      case _StepStatus.error:
        icon = const Icon(Icons.cancel, color: Colors.red, size: 18);
        textColor = Colors.red;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 12),
          Text(step.label(l), style: TextStyle(color: textColor, fontSize: 14)),
        ],
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
      _UpdateState.error => (Icons.error_outline, Colors.red, l.updateError),
      _UpdateState.idle => (Icons.info_outline, Colors.white54, ''),
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
