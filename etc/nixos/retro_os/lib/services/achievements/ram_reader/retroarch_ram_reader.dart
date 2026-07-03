import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import '../../../utils/debug_logger.dart';

/// Reads emulated console RAM straight out of a running RetroArch process
/// via its built-in Network Command Interface (UDP) — the same interface
/// speedrun autosplitters use to read game memory without a custom core.
/// RetroArch must be launched with `network_cmd_enable = "true"` (see
/// SettingsService.applyRetroarchOverrides).
///
/// Addresses are the same 0-based offsets RetroArch's own cheat/memory
/// search uses (i.e. an offset into RDRAM), not the MIPS virtual address
/// (0x80000000+) games use internally.
class RetroarchRamReader {
  RetroarchRamReader({this.host = '127.0.0.1', this.port = 55355});

  final String host;
  final int port;

  RawDatagramSocket? _socket;
  Completer<String?>? _pending;
  Timer? _timeoutTimer;

  // Logged on the false->true and true->false edges only (see [readBytes]) -
  // a broken connection means every condition's read times out every poll,
  // and logging that per-address would flood the log instead of helping.
  bool _lastReadTimedOut = false;

  static const _requestTimeout = Duration(milliseconds: 500);

  Future<void> connect() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket!.listen(_onEvent);
    DebugLogger.log('[RetroarchRamReader] bound on port ${_socket!.port}, target $host:$port');
  }

  void dispose() {
    _timeoutTimer?.cancel();
    _pending?.complete(null);
    _pending = null;
    _socket?.close();
    _socket = null;
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _socket?.receive();
    if (datagram == null || _pending == null) return;
    _timeoutTimer?.cancel();
    _pending!.complete(String.fromCharCodes(datagram.data).trim());
    _pending = null;
  }

  // RetroArch's replies carry no request ID, so a second command can't be
  // sent until the first one's reply (or timeout) has been consumed —
  // otherwise there'd be no way to tell which reply belongs to which request.
  Future<String?> _send(String command) async {
    final socket = _socket;
    if (socket == null) throw StateError('RetroarchRamReader.connect() was not called');
    while (_pending != null) {
      await _pending!.future;
    }
    final completer = Completer<String?>();
    _pending = completer;
    socket.send(command.codeUnits, InternetAddress(host), port);
    _timeoutTimer = Timer(_requestTimeout, () {
      if (_pending == completer) {
        _pending = null;
        completer.complete(null);
      }
    });
    return completer.future;
  }

  /// Reads [length] bytes starting at [address]. Returns null on timeout or
  /// if RetroArch reports the read as invalid (`-1` reply).
  Future<Uint8List?> readBytes(int address, int length) async {
    final addressHex = address.toRadixString(16);
    final reply = await _send('READ_CORE_RAM $addressHex $length');
    if (reply == null || reply.isEmpty) {
      if (!_lastReadTimedOut) {
        _lastReadTimedOut = true;
        DebugLogger.log(
          '[RetroarchRamReader] no reply reading 0x$addressHex (timed out after $_requestTimeout) - '
          'is RetroArch running with network_cmd_enable="true" and reachable at $host:$port? '
          '(further timeouts logged again only once reads start succeeding, to avoid log spam)',
        );
      }
      return null;
    }
    if (_lastReadTimedOut) {
      _lastReadTimedOut = false;
      DebugLogger.log('[RetroarchRamReader] reads recovered (0x$addressHex replied)');
    }

    // Expected: "READ_CORE_RAM <addr> <byte> <byte> ..." or
    // "READ_CORE_RAM <addr> -1" when the core/address doesn't support it.
    final parts = reply.split(' ');
    if (parts.length < 3 || parts[2] == '-1') {
      DebugLogger.log('[RetroarchRamReader] read failed at 0x$addressHex: "$reply"');
      return null;
    }

    final bytes = Uint8List(parts.length - 2);
    for (var i = 2; i < parts.length; i++) {
      bytes[i - 2] = int.parse(parts[i], radix: 16);
    }
    return bytes;
  }
}
