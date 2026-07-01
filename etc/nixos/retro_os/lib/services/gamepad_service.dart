import 'dart:async';
import 'package:flutter/services.dart';
import 'package:gamepads/gamepads.dart';
import '../utils/debug_logger.dart';

enum GamepadAction { up, down, left, right, confirm, back, start, select }

class GamepadService {
  GamepadService._();
  static final instance = GamepadService._();

  final _controller = StreamController<GamepadAction>.broadcast();
  Stream<GamepadAction> get actions => _controller.stream;

  StreamSubscription? _subscription;
  final Map<String, double> _analogState = {};
  final Map<String, Timer?> _repeatTimers = {};

  static const _repeatDelay = Duration(milliseconds: 400);
  static const _repeatInterval = Duration(milliseconds: 120);

  void init() {
    _subscription = Gamepads.events.listen(_handleEvent);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  void dispose() {
    for (final t in _repeatTimers.values) {
      t?.cancel();
    }
    _subscription?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _controller.close();
  }

  bool _handleKeyEvent(KeyEvent event) {
    // KeyRepeatEvent is what the platform sends while a key is held down
    // (OS-level keyboard auto-repeat) — without it, holding a key only
    // ever fires the initial press.
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    DebugLogger.log('[GamepadService] key event: ${event.logicalKey}');
    final action = switch (event.logicalKey) {
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
    if (action != null) _controller.add(action);
    return action != null;
  }

  static const _repeatableActions = {
    GamepadAction.up,
    GamepadAction.down,
    GamepadAction.left,
    GamepadAction.right,
  };

  void _handleEvent(GamepadEvent event) {
    if (event.type == KeyType.button) {
      final action = _mapButton(event.key);
      if (action == null) return;
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
      if (value < -_analogThreshold && prev >= -_analogThreshold) _startRepeat('${key}_neg', GamepadAction.left);
      else if (value > _analogThreshold && prev <= _analogThreshold) _startRepeat('${key}_pos', GamepadAction.right);
      else if (value.abs() <= _analogThreshold) { _stopRepeat('${key}_neg'); _stopRepeat('${key}_pos'); }
    } else if (key == 'left_stick_y' || key == 'hat_y' || key == '1' || key == '5') {
      if (value < -_analogThreshold && prev >= -_analogThreshold) _startRepeat('${key}_neg', GamepadAction.up);
      else if (value > _analogThreshold && prev <= _analogThreshold) _startRepeat('${key}_pos', GamepadAction.down);
      else if (value.abs() <= _analogThreshold) { _stopRepeat('${key}_neg'); _stopRepeat('${key}_pos'); }
    }
  }
}
