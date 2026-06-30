import 'dart:async';
import 'package:flutter/services.dart';
import 'package:gamepads/gamepads.dart';

enum GamepadAction { up, down, left, right, confirm, back, start, select }

class GamepadService {
  GamepadService._();
  static final instance = GamepadService._();

  final _controller = StreamController<GamepadAction>.broadcast();
  Stream<GamepadAction> get actions => _controller.stream;

  StreamSubscription? _subscription;
  final Map<String, double> _analogState = {};

  void init() {
    _subscription = Gamepads.events.listen(_handleEvent);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  void dispose() {
    _subscription?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _controller.close();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
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

  void _handleEvent(GamepadEvent event) {
    if (event.type == KeyType.button && event.value == 1.0) {
      final action = _mapButton(event.key);
      if (action != null) _controller.add(action);
    } else if (event.type == KeyType.analog) {
      _handleAnalog(event.key, event.value);
    }
  }

  GamepadAction? _mapButton(String key) {
    return switch (key) {
      'a' || 'button_0' => GamepadAction.confirm,
      'b' || 'button_1' => GamepadAction.back,
      'start' || 'button_9' => GamepadAction.start,
      'select' || 'button_8' => GamepadAction.select,
      'dpad_up' => GamepadAction.up,
      'dpad_down' => GamepadAction.down,
      'dpad_left' => GamepadAction.left,
      'dpad_right' => GamepadAction.right,
      _ => null,
    };
  }

  // Fires once per direction cross (avoids continuous events while stick is held)
  void _handleAnalog(String key, double value) {
    final prev = _analogState[key] ?? 0.0;
    _analogState[key] = value;

    if (key == 'left_stick_x' || key == 'hat_x') {
      if (value < -0.5 && prev >= -0.5) _controller.add(GamepadAction.left);
      if (value > 0.5 && prev <= 0.5) _controller.add(GamepadAction.right);
    } else if (key == 'left_stick_y' || key == 'hat_y') {
      if (value < -0.5 && prev >= -0.5) _controller.add(GamepadAction.up);
      if (value > 0.5 && prev <= 0.5) _controller.add(GamepadAction.down);
    }
  }
}
