import 'dart:async';
import 'package:flutter/material.dart';
import '../services/gamepad_service.dart';

// ── Key model ────────────────────────────────────────────────────────────────

sealed class _Key {
  const _Key();
}

class _CharKey extends _Key {
  const _CharKey(this.char);
  final String char;
}

enum _Action { backspace, space, done, switchMode }

class _ActionKey extends _Key {
  const _ActionKey(this.action, this.label);
  final _Action action;
  final String label;
}

class _ShortcutKey extends _Key {
  const _ShortcutKey(this.text, {this.append = false});
  final String text;
  final bool append;
}

// ── Layouts ──────────────────────────────────────────────────────────────────

const _lettersRows = <List<_Key>>[
  [
    _ShortcutKey('http://'),
    _ShortcutKey('https://'),
  ],
  [
    _CharKey('q'), _CharKey('w'), _CharKey('e'), _CharKey('r'), _CharKey('t'),
    _CharKey('y'), _CharKey('u'), _CharKey('i'), _CharKey('o'), _CharKey('p'),
  ],
  [
    _CharKey('a'), _CharKey('s'), _CharKey('d'), _CharKey('f'), _CharKey('g'),
    _CharKey('h'), _CharKey('j'), _CharKey('k'), _CharKey('l'),
    _ActionKey(_Action.backspace, '⌫'),
  ],
  [
    _CharKey('z'), _CharKey('x'), _CharKey('c'), _CharKey('v'), _CharKey('b'),
    _CharKey('n'), _CharKey('m'), _CharKey('.'), _CharKey('-'), _CharKey('_'),
  ],
  [
    _ActionKey(_Action.switchMode, '123'),
    _ActionKey(_Action.space, 'SPACE'),
    _ActionKey(_Action.done, 'DONE'),
  ],
];

const _numbersRows = <List<_Key>>[
  [
    _ShortcutKey('192.168.', append: true),
    _ShortcutKey('127.0.0.1', append: true),
  ],
  [
    _CharKey('1'), _CharKey('2'), _CharKey('3'), _CharKey('4'), _CharKey('5'),
    _CharKey('6'), _CharKey('7'), _CharKey('8'), _CharKey('9'), _CharKey('0'),
  ],
  [
    _CharKey('-'), _CharKey('_'), _CharKey('.'), _CharKey(':'), _CharKey('/'),
    _CharKey('@'), _CharKey('#'), _CharKey('!'), _CharKey('?'),
    _ActionKey(_Action.backspace, '⌫'),
  ],
  [
    _CharKey('('), _CharKey(')'), _CharKey('['), _CharKey(']'), _CharKey('{'),
    _CharKey('}'), _CharKey('+'), _CharKey('='), _CharKey('~'), _CharKey('%'),
  ],
  [
    _ActionKey(_Action.switchMode, 'ABC'),
    _ActionKey(_Action.space, 'SPACE'),
    _ActionKey(_Action.done, 'DONE'),
  ],
];

// ── Public API ───────────────────────────────────────────────────────────────

/// Shows the gamepad keyboard overlay.
/// Returns the typed string on DONE, or null if the user cancelled with Back.
Future<String?> showGamepadKeyboard(
  BuildContext context, {
  String initialValue = '',
  String? hint,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _GamepadKeyboardDialog(initialValue: initialValue, hint: hint),
  );
}

// ── Dialog widget ─────────────────────────────────────────────────────────────

class _GamepadKeyboardDialog extends StatefulWidget {
  const _GamepadKeyboardDialog({required this.initialValue, this.hint});

  final String initialValue;
  final String? hint;

  @override
  State<_GamepadKeyboardDialog> createState() => _GamepadKeyboardDialogState();
}

class _GamepadKeyboardDialogState extends State<_GamepadKeyboardDialog> {
  late String _text;
  int _row = 0;
  int _col = 0;
  bool _lettersMode = true;

  late final StreamSubscription<GamepadAction> _sub;

  List<List<_Key>> get _layout => _lettersMode ? _lettersRows : _numbersRows;

  @override
  void initState() {
    super.initState();
    _text = widget.initialValue;
    _sub = GamepadService.instance.actions.listen(_handleAction);
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  void _handleAction(GamepadAction action) {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    switch (action) {
      case GamepadAction.up:
        _move(-1, 0);
      case GamepadAction.down:
        _move(1, 0);
      case GamepadAction.left:
        _move(0, -1);
      case GamepadAction.right:
        _move(0, 1);
      case GamepadAction.confirm:
        _activateKey(_layout[_row][_col]);
      case GamepadAction.l:
        _deleteChar();
      case GamepadAction.back:
        Navigator.pop(context, null);
      default:
        break;
    }
  }

  void _move(int dRow, int dCol) {
    setState(() {
      final newRow = (_row + dRow).clamp(0, _layout.length - 1);
      if (dRow != 0) {
        final oldRowLen = _layout[_row].length;
        final newRowLen = _layout[newRow].length;
        final ratio = oldRowLen > 1 ? _col / (oldRowLen - 1) : 0.0;
        _col = (ratio * (newRowLen - 1)).round().clamp(0, newRowLen - 1);
        _row = newRow;
      } else {
        _col = (_col + dCol).clamp(0, _layout[newRow].length - 1);
      }
    });
  }

  void _activateKey(_Key key) {
    switch (key) {
      case _CharKey(:final char):
        setState(() => _text += char);
      case _ShortcutKey(:final text, :final append):
        setState(() => _text = append ? _text + text : text);
      case _ActionKey(:final action):
        switch (action) {
          case _Action.backspace:
            _deleteChar();
          case _Action.space:
            setState(() => _text += ' ');
          case _Action.done:
            Navigator.pop(context, _text);
          case _Action.switchMode:
            setState(() {
              final wasLastRow = _row == _layout.length - 1;
              _lettersMode = !_lettersMode;
              _row = wasLastRow ? _layout.length - 1 : _row.clamp(0, _layout.length - 1);
              _col = _col.clamp(0, _layout[_row].length - 1);
            });
        }
    }
  }

  void _deleteChar() {
    if (_text.isEmpty) return;
    setState(() => _text = _text.substring(0, _text.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TextBar(text: _text, hint: widget.hint),
              const SizedBox(height: 20),
              ..._layout.asMap().entries.map(
                (rowEntry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: rowEntry.value.asMap().entries.map((keyEntry) {
                      final selected = _row == rowEntry.key && _col == keyEntry.key;
                      return _KeyTile(
                        keyDef: keyEntry.value,
                        selected: selected,
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'L  →  backspace   •   B  →  cancel',
                style: const TextStyle(color: Colors.white24, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _TextBar extends StatelessWidget {
  const _TextBar({required this.text, this.hint});

  final String text;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          Expanded(
            child: text.isEmpty
                ? Text(
                    hint ?? '',
                    style: const TextStyle(color: Colors.white24, fontSize: 16),
                  )
                : Text(
                    text,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
          ),
          // blinking-style cursor block
          Container(width: 2, height: 18, color: Colors.white70),
        ],
      ),
    );
  }
}

class _KeyTile extends StatelessWidget {
  const _KeyTile({required this.keyDef, required this.selected});

  final _Key keyDef;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final label = switch (keyDef) {
      _CharKey(:final char) => char.toUpperCase(),
      _ActionKey(:final label) => label,
      _ShortcutKey(:final text) => text,
    };

    final isWide = keyDef is _ActionKey && (keyDef as _ActionKey).action == _Action.space;
    final isDone = keyDef is _ActionKey && (keyDef as _ActionKey).action == _Action.done;
    final isBackspace = keyDef is _ActionKey && (keyDef as _ActionKey).action == _Action.backspace;
    final isShortcut = keyDef is _ShortcutKey;

    Color bg;
    Color fg;
    if (selected) {
      bg = isDone ? Colors.greenAccent : isShortcut ? Colors.blueAccent : Colors.white;
      fg = Colors.black;
    } else if (isDone) {
      bg = Colors.green.withValues(alpha: 0.25);
      fg = Colors.greenAccent;
    } else if (isBackspace) {
      bg = Colors.white10;
      fg = Colors.redAccent;
    } else if (isShortcut) {
      bg = Colors.blueAccent.withValues(alpha: 0.15);
      fg = Colors.blueAccent;
    } else {
      bg = Colors.white10;
      fg = Colors.white70;
    }

    return Expanded(
      flex: isWide ? 4 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 13,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
