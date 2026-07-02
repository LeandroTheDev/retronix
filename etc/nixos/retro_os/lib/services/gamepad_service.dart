import 'dart:async';
import 'package:flutter/services.dart';
import 'package:gamepads/gamepads.dart';
import '../utils/debug_logger.dart';

enum GamepadAction { up, down, left, right, confirm, back, start, select }

// Best-effort guess from GamepadController.name — a free-text, platform-
// dependant string, not a real hardware ID (see GamepadService docs).
enum ControllerType { xbox, playstation, nintendo, generic }

ControllerType controllerTypeFromName(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('xbox')) return ControllerType.xbox;
  if (lower.contains('playstation') || lower.contains('dualshock') || lower.contains('dualsense')) {
    return ControllerType.playstation;
  }
  if (lower.contains('nintendo') || lower.contains('switch') || lower.contains('n64')) {
    return ControllerType.nintendo;
  }
  return ControllerType.generic;
}

class GamepadService {
  GamepadService._();
  static final instance = GamepadService._();

  final _controller = StreamController<GamepadAction>.broadcast();
  Stream<GamepadAction> get actions => _controller.stream;

  // Raw press/release events (unlike [actions], these fire exactly once per
  // physical press and once per release, with no auto-repeat) — needed for
  // hold-to-confirm gestures like exiting a game.
  final _buttonDownController = StreamController<GamepadAction>.broadcast();
  final _buttonUpController = StreamController<GamepadAction>.broadcast();
  Stream<GamepadAction> get buttonDown => _buttonDownController.stream;
  Stream<GamepadAction> get buttonUp => _buttonUpController.stream;

  StreamSubscription? _subscription;
  final Map<String, double> _analogState = {};
  final Map<String, Timer?> _repeatTimers = {};

  static const _repeatDelay = Duration(milliseconds: 400);
  static const _repeatInterval = Duration(milliseconds: 120);

  // ── Player slots ─────────────────────────────────────────────────────────
  // Slot index 0..3 = player 1..4. Assigned by connection order: the first
  // controller detected keeps player 1 even if others come and go, and a
  // freed slot (device unplugged) is handed to the next new controller.
  // This is the mapping we'll eventually use to inject per-player controller
  // config into RetroArch.
  static const maxPlayers = 4;
  static const _deviceScanInterval = Duration(seconds: 2);

  final List<String?> _playerSlots = List.filled(maxPlayers, null);
  final _slotsController = StreamController<List<String?>>.broadcast();
  Stream<List<String?>> get playerSlots => _slotsController.stream;
  List<String?> get currentPlayerSlots => List.unmodifiable(_playerSlots);

  final Map<String, String> _controllerNames = {}; // id -> raw name

  Timer? _deviceScanTimer;

  int? playerNumberForId(String id) {
    final index = _playerSlots.indexOf(id);
    return index == -1 ? null : index + 1;
  }

  String? nameForId(String id) => _controllerNames[id];

  ControllerType? typeForId(String id) {
    final name = _controllerNames[id];
    return name == null ? null : controllerTypeFromName(name);
  }

  void init() {
    _subscription = Gamepads.events.listen(_handleEvent);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _scanDevices();
    _deviceScanTimer = Timer.periodic(_deviceScanInterval, (_) => _scanDevices());
  }

  void dispose() {
    for (final t in _repeatTimers.values) {
      t?.cancel();
    }
    _deviceScanTimer?.cancel();
    _subscription?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _controller.close();
    _slotsController.close();
    _buttonDownController.close();
    _buttonUpController.close();
  }

  Future<void> _scanDevices() async {
    final controllers = await Gamepads.list();
    for (final c in controllers) {
      _controllerNames[c.id] = c.name;
    }

    final connectedIds = controllers.map((c) => c.id).toSet();
    var changed = false;

    for (var i = 0; i < _playerSlots.length; i++) {
      if (_playerSlots[i] != null && !connectedIds.contains(_playerSlots[i])) {
        DebugLogger.log('[GamepadService] player ${i + 1} disconnected (${_playerSlots[i]})');
        _playerSlots[i] = null;
        changed = true;
      }
    }

    for (final controller in controllers) {
      if (_playerSlots.contains(controller.id)) continue;
      final freeIndex = _playerSlots.indexOf(null);
      if (freeIndex == -1) break; // all slots taken
      _playerSlots[freeIndex] = controller.id;
      changed = true;
      DebugLogger.log('[GamepadService] player ${freeIndex + 1} assigned: ${controller.id} (${controller.name})');
    }

    if (changed) _slotsController.add(currentPlayerSlots);
  }

  GamepadAction? _keyAction(LogicalKeyboardKey key) => switch (key) {
    LogicalKeyboardKey.arrowUp => GamepadAction.up,
    LogicalKeyboardKey.arrowDown => GamepadAction.down,
    LogicalKeyboardKey.arrowLeft => GamepadAction.left,
    LogicalKeyboardKey.arrowRight => GamepadAction.right,
    LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter => GamepadAction.confirm,
    LogicalKeyboardKey.escape || LogicalKeyboardKey.backspace => GamepadAction.back,
    LogicalKeyboardKey.f1 => GamepadAction.start,
    LogicalKeyboardKey.f2 => GamepadAction.select,
    _ => null,
  };

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyUpEvent) {
      final action = _keyAction(event.logicalKey);
      if (action != null) _buttonUpController.add(action);
      return action != null;
    }
    // KeyRepeatEvent is what the platform sends while a key is held down
    // (OS-level keyboard auto-repeat) — without it, holding a key only
    // ever fires the initial press.
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    DebugLogger.log('[GamepadService] key event: ${event.logicalKey}');
    final action = _keyAction(event.logicalKey);
    if (action != null) {
      _controller.add(action);
      if (event is KeyDownEvent) _buttonDownController.add(action);
    }
    return action != null;
  }

  static const _repeatableActions = {GamepadAction.up, GamepadAction.down, GamepadAction.left, GamepadAction.right};

  void _handleEvent(GamepadEvent event) {
    if (event.type == KeyType.button) {
      final action = _mapButton(event.key);
      if (action == null) return;
      if (event.value == 1.0) {
        _buttonDownController.add(action);
      } else if (event.value == 0.0) {
        _buttonUpController.add(action);
      }
      if (!_repeatableActions.contains(action)) {
        if (event.value == 1.0) _controller.add(action);
        return;
      }
      // D-pads reported as digital buttons (rather than a hat axis) need
      // their own press/release-driven repeat, same as the analog case below.
      if (event.value == 1.0) {
        _startRepeat('btn_${event.key}', action);
      } else {
        _stopRepeat('btn_${event.key}');
      }
    } else if (event.type == KeyType.analog) {
      _handleAnalog(event.key, event.value);
    }
  }

  GamepadAction? _mapButton(String key) {
    return switch (key) {
      'a' || 'button_0' || '5' => GamepadAction.confirm,
      'b' || 'button_1' || '4' => GamepadAction.back,
      'start' || 'button_9' || '9' => GamepadAction.start,
      'select' || 'button_8' || '8' => GamepadAction.select,
      'dpad_up' => GamepadAction.up,
      'dpad_down' => GamepadAction.down,
      'dpad_left' => GamepadAction.left,
      'dpad_right' => GamepadAction.right,
      _ => null,
    };
  }

  static const _analogThreshold = 16000.0;

  void _startRepeat(String timerKey, GamepadAction action) {
    _repeatTimers[timerKey]?.cancel();
    _controller.add(action);
    _repeatTimers[timerKey] = Timer(_repeatDelay, () {
      _repeatTimers[timerKey] = Timer.periodic(_repeatInterval, (_) {
        _controller.add(action);
      });
    });
  }

  void _stopRepeat(String timerKey) {
    _repeatTimers[timerKey]?.cancel();
    _repeatTimers[timerKey] = null;
  }

  void _handleAnalog(String key, double value) {
    final prev = _analogState[key] ?? 0.0;
    _analogState[key] = value;

    // key '0'/'4' = X axis (stick/hat), key '1'/'5' = Y axis (stick/hat)
    if (key == 'left_stick_x' || key == 'hat_x' || key == '0' || key == '4') {
      if (value < -_analogThreshold && prev >= -_analogThreshold) {
        _startRepeat('${key}_neg', GamepadAction.left);
      } else if (value > _analogThreshold && prev <= _analogThreshold)
        _startRepeat('${key}_pos', GamepadAction.right);
      else if (value.abs() <= _analogThreshold) {
        _stopRepeat('${key}_neg');
        _stopRepeat('${key}_pos');
      }
    } else if (key == 'left_stick_y' || key == 'hat_y' || key == '1' || key == '5') {
      if (value < -_analogThreshold && prev >= -_analogThreshold) {
        _startRepeat('${key}_neg', GamepadAction.up);
      } else if (value > _analogThreshold && prev <= _analogThreshold)
        _startRepeat('${key}_pos', GamepadAction.down);
      else if (value.abs() <= _analogThreshold) {
        _stopRepeat('${key}_neg');
        _stopRepeat('${key}_pos');
      }
    }
  }
}
