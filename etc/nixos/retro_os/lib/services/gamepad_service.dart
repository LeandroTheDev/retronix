import 'dart:async';
import 'package:flutter/services.dart';
import 'package:gamepads/gamepads.dart';
import '../utils/debug_logger.dart';
import '../utils/sound.dart';

enum GamepadAction { up, down, left, right, confirm, back, start, select, l, r }

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

// Which original console a pad/adapter was built for. Unlike [ControllerType]
// (brand, guessed from a free-text name), this is keyed off the USB
// vendorId/productId — a real hardware identifier read from the OS (sysfs on
// Linux) rather than a string that can come back empty or unreliable (see
// the "Microntek USB Joystick" pad, whose reported name is blank at connect
// time on some boots, but whose vendorId/productId are always present).
enum KnownConsolePad { nintendo64, xbox360 }

// Add an entry here for every adapter/pad we've confirmed by hand — check
// the "[GamepadService] controller ... identified" debug log for the
// vendorId/productId of a new device, then verify it's actually the console
// it claims to be before adding it.
const _knownConsolePadsByVidPid = <(int, int), KnownConsolePad>{
  (0x0079, 0x0006): KnownConsolePad.nintendo64, // "Microntek USB Joystick" N64 adapter
  (0x045e, 0x028e): KnownConsolePad.xbox360, // Xbox 360 Wired Controller (Microsoft's official VID/PID)
};

KnownConsolePad? knownConsolePadFromVidPid(int vendorId, int productId) =>
    _knownConsolePadsByVidPid[(vendorId, productId)];

// A raw-input → [GamepadAction] mapping for one specific piece of hardware.
// Raw button/axis codes are NOT standardized across controllers — on Linux
// every pad reports plain numeric indices whose meaning is entirely
// device-specific (see the comment on [KnownConsolePad]), so two different
// pads can use the exact same code for two different buttons. Each
// recognized device gets its own layout instead of sharing one global table.
class GamepadLayout {
  const GamepadLayout({
    required this.buttons,
    this.xAxisKeys = const {'left_stick_x', 'hat_x'},
    this.yAxisKeys = const {'left_stick_y', 'hat_y'},
  });

  final Map<String, GamepadAction> buttons;
  final Set<String> xAxisKeys;
  final Set<String> yAxisKeys;

  GamepadAction? mapButton(String key) => buttons[key];
}

// Fallback layout for any controller we haven't identified yet (VID/PID not
// in [_knownConsolePadsByVidPid]). Only covers *named* button/axis strings,
// which are safe to assume mean the same thing everywhere — they only show
// up on backends that translate them for us (e.g. Windows XInput). Numeric
// codes are device-specific and belong in that device's own layout below,
// added once confirmed via the "unmapped button" debug log.
const _genericLayout = GamepadLayout(
  buttons: {
    'a': GamepadAction.confirm,
    'button_0': GamepadAction.confirm,
    'b': GamepadAction.back,
    'button_1': GamepadAction.back,
    'start': GamepadAction.start,
    'button_9': GamepadAction.start,
    'select': GamepadAction.select,
    'button_8': GamepadAction.select,
    'tl': GamepadAction.l,
    'l1': GamepadAction.l,
    'left_shoulder': GamepadAction.l,
    'tr': GamepadAction.r,
    'r1': GamepadAction.r,
    'right_shoulder': GamepadAction.r,
    'dpad_up': GamepadAction.up,
    'dpad_down': GamepadAction.down,
    'dpad_left': GamepadAction.left,
    'dpad_right': GamepadAction.right,
  },
);

// "Microntek USB Joystick" N64 adapter — Linux joydev reports every button
// as a plain numeric index; these were confirmed one at a time via the
// unmapped-button debug log. Axis 0/1 is the real analog stick; 4/5 is the
// D-pad hat (the "right stick" seen in the RetroArch autoconfig is actually
// the C-button diamond emulated as 4 discrete buttons, not a real axis).
const _nintendo64Layout = GamepadLayout(
  buttons: {
    '4': GamepadAction.back,
    '5': GamepadAction.confirm,
    '6': GamepadAction.l,
    '7': GamepadAction.r,
    '8': GamepadAction.select,
    '9': GamepadAction.start,
  },
  xAxisKeys: {'0', '4'},
  yAxisKeys: {'1', '5'},
);

// Xbox 360 Wired Controller — not yet mapped. Connect it, press each button,
// and check the "unmapped button" debug log for its raw codes (they won't
// match the N64 pad's numbering — see the class doc above), then fill this
// in the same way [_nintendo64Layout] was built.
const _xbox360Layout = GamepadLayout(buttons: {});

// Add an entry here once a new [KnownConsolePad] has a confirmed layout —
// devices recognized by VID/PID but missing from this table fall back to
// [_genericLayout].
const _layoutsByPad = <KnownConsolePad, GamepadLayout>{
  KnownConsolePad.nintendo64: _nintendo64Layout,
  KnownConsolePad.xbox360: _xbox360Layout,
};

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

  static const _connectSound    = 'sounds/connect-sound-effect-3045-freesounds-community.wav';
  static const _disconnectSound = 'sounds/disconnect-sound-effect-270300-freesounds-community.wav';

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

  // id -> (vendorId, productId), USB IDs read straight from the OS (sysfs on
  // Linux) by the gamepads plugin. Only populated once the first event from
  // that controller arrives — Gamepads.list() doesn't expose these.
  final Map<String, (int, int)> _controllerVendorProduct = {};

  Timer? _deviceScanTimer;

  int? playerNumberForId(String id) {
    final index = _playerSlots.indexOf(id);
    return index == -1 ? null : index + 1;
  }

  String? nameForId(String id) => _controllerNames[id];

  (int, int)? vendorProductForId(String id) => _controllerVendorProduct[id];

  KnownConsolePad? knownConsolePadForId(String id) {
    final vp = _controllerVendorProduct[id];
    return vp == null ? null : knownConsolePadFromVidPid(vp.$1, vp.$2);
  }

  GamepadLayout _layoutForId(String id) {
    final pad = knownConsolePadForId(id);
    if (pad == null) return _genericLayout;
    return _layoutsByPad[pad] ?? _genericLayout;
  }

  ControllerType? typeForId(String id) {
    final name = _controllerNames[id];
    return name == null ? null : controllerTypeFromName(name);
  }

  // Fires [onTrigger] once when every action in [combo] has been pressed
  // within [window] of each other (e.g. L+R to toggle the in-game overlay).
  StreamSubscription<GamepadAction> watchCombo(
    Set<GamepadAction> combo,
    void Function() onTrigger, {
    Duration window = const Duration(milliseconds: 400),
  }) {
    final recent = <GamepadAction>{};
    return actions.listen((action) {
      if (!combo.contains(action)) return;
      recent.add(action);
      Future.delayed(window, () => recent.remove(action));
      if (combo.every(recent.contains)) {
        recent.clear();
        onTrigger();
      }
    });
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
        playSound(_disconnectSound);
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
      playSound(_connectSound);
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
    LogicalKeyboardKey.f3 => GamepadAction.l,
    LogicalKeyboardKey.f4 => GamepadAction.r,
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

  // Captures vendorId/productId from the first event of each controller
  // (Gamepads.list() doesn't expose these — only available per-event, and
  // only on platforms whose native plugin reads them, e.g. Linux via sysfs).
  void _recordVendorProduct(GamepadEvent event) {
    if (_controllerVendorProduct.containsKey(event.gamepadId)) return;
    final vendorId = event.vendorId;
    final productId = event.productId;
    if (vendorId == null || productId == null) return;
    _controllerVendorProduct[event.gamepadId] = (vendorId, productId);
    DebugLogger.log(
      '[GamepadService] controller ${event.gamepadId} (${_controllerNames[event.gamepadId]}) '
      'identified: vendorId=$vendorId (0x${vendorId.toRadixString(16)}), '
      'productId=$productId (0x${productId.toRadixString(16)})',
    );
    final knownPad = knownConsolePadFromVidPid(vendorId, productId);
    if (knownPad != null) {
      DebugLogger.log('[GamepadService] controller ${event.gamepadId} recognized as: $knownPad');
    }
  }

  void _handleEvent(GamepadEvent event) {
    _recordVendorProduct(event);
    final layout = _layoutForId(event.gamepadId);
    if (event.type == KeyType.button) {
      if (event.value == 1.0) {
        final action = layout.mapButton(event.key);
        DebugLogger.log(
          '[GamepadService] button press: key=${event.key} action=${action ?? "unmapped"} '
          '(gamepad: ${event.gamepadId}, vendorId: ${event.vendorId}, productId: ${event.productId})',
        );
      }
      final action = layout.mapButton(event.key);
      if (action == null) {
        return;
      }
      if (event.value == 1.0) {
        _buttonDownController.add(action);
      } else if (event.value == 0.0) {
        _buttonUpController.add(action);
      }
      if (!_repeatableActions.contains(action)) {
        if (event.value == 1.0) {
          DebugLogger.log('[GamepadService] emitting to stream: $action');
          _controller.add(action);
        }
        return;
      }
      // D-pads reported as digital buttons (rather than a hat axis) need
      // their own press/release-driven repeat, same as the analog case below.
      // Namespaced by gamepadId so two connected pads can't share a timer
      // just because they happen to report the same raw button code.
      final timerKey = '${event.gamepadId}:btn_${event.key}';
      if (event.value == 1.0) {
        _startRepeat(timerKey, action);
      } else {
        _stopRepeat(timerKey);
      }
    } else if (event.type == KeyType.analog) {
      _handleAnalog(event.gamepadId, layout, event.key, event.value);
    }
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

  void _handleAnalog(String gamepadId, GamepadLayout layout, String key, double value) {
    // Namespaced by gamepadId so two connected pads can't clobber each
    // other's axis state just because they happen to report the same code.
    final stateKey = '$gamepadId:$key';
    final prev = _analogState[stateKey] ?? 0.0;
    _analogState[stateKey] = value;

    if (layout.xAxisKeys.contains(key)) {
      if (value < -_analogThreshold && prev >= -_analogThreshold) {
        _startRepeat('$stateKey:neg', GamepadAction.left);
      } else if (value > _analogThreshold && prev <= _analogThreshold) {
        _startRepeat('$stateKey:pos', GamepadAction.right);
      } else if (value.abs() <= _analogThreshold) {
        _stopRepeat('$stateKey:neg');
        _stopRepeat('$stateKey:pos');
      }
    } else if (layout.yAxisKeys.contains(key)) {
      if (value < -_analogThreshold && prev >= -_analogThreshold) {
        _startRepeat('$stateKey:neg', GamepadAction.up);
      } else if (value > _analogThreshold && prev <= _analogThreshold) {
        _startRepeat('$stateKey:pos', GamepadAction.down);
      } else if (value.abs() <= _analogThreshold) {
        _stopRepeat('$stateKey:neg');
        _stopRepeat('$stateKey:pos');
      }
    }
  }
}
