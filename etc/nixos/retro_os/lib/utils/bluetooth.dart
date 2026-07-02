import 'dart:io';
import 'debug_logger.dart';

class BluetoothDevice {
  const BluetoothDevice({
    required this.address,
    required this.name,
    this.paired = false,
    this.connected = false,
  });

  final String address; // e.g. "AA:BB:CC:DD:EE:FF"
  final String name;
  final bool paired;
  final bool connected;
}

Future<ProcessResult> _bluetoothctl(List<String> args) => Process.run('bluetoothctl', args);

Future<bool> setBluetoothPowered(bool on) async {
  try {
    final result = await _bluetoothctl(['power', on ? 'on' : 'off']);
    return result.exitCode == 0;
  } catch (e) {
    DebugLogger.log('[bluetooth] setBluetoothPowered($on) failed: $e');
    return false;
  }
}

Future<void> setBluetoothScanning(bool on) async {
  try {
    await _bluetoothctl(['scan', on ? 'on' : 'off']);
  } catch (e) {
    DebugLogger.log('[bluetooth] setBluetoothScanning($on) failed: $e');
  }
}

final _deviceLineRegExp = RegExp(r'^Device\s+([0-9A-Fa-f:]{17})\s+(.+)$');

Set<String> _parseAddresses(String output) => output
    .split('\n')
    .map((line) => _deviceLineRegExp.firstMatch(line.trim())?.group(1))
    .whereType<String>()
    .toSet();

// Every device BlueZ knows about — previously paired devices plus anything
// seen while scanning. Merges in Paired/Connected status from separate
// `bluetoothctl devices <filter>` calls since the plain listing doesn't
// include that.
Future<List<BluetoothDevice>> getBluetoothDevices() async {
  try {
    final all = await _bluetoothctl(['devices']);
    final paired = await _bluetoothctl(['devices', 'Paired']);
    final connected = await _bluetoothctl(['devices', 'Connected']);

    final pairedAddresses = _parseAddresses(paired.stdout as String);
    final connectedAddresses = _parseAddresses(connected.stdout as String);

    final devices = <BluetoothDevice>[];
    for (final line in (all.stdout as String).split('\n')) {
      final match = _deviceLineRegExp.firstMatch(line.trim());
      if (match == null) continue;
      final address = match.group(1)!;
      devices.add(BluetoothDevice(
        address: address,
        name: match.group(2)!.trim(),
        paired: pairedAddresses.contains(address),
        connected: connectedAddresses.contains(address),
      ));
    }
    return devices;
  } catch (e) {
    DebugLogger.log('[bluetooth] getBluetoothDevices failed: $e');
    return [];
  }
}

// Pairs (if needed), trusts (so it auto-reconnects later without asking
// again) and connects to [address]. Only handles "Just Works" pairing (no
// PIN/passkey prompt) — fine for game controllers, which is what this
// screen exists for.
Future<bool> pairAndConnect(String address) async {
  try {
    await _bluetoothctl(['pair', address]);
    await _bluetoothctl(['trust', address]);
    final result = await _bluetoothctl(['connect', address]);
    DebugLogger.log(
      '[bluetooth] connect($address): exit=${result.exitCode} '
      'stdout="${(result.stdout as String).trim()}" stderr="${(result.stderr as String).trim()}"',
    );
    return result.exitCode == 0;
  } catch (e) {
    DebugLogger.log('[bluetooth] pairAndConnect($address) failed: $e');
    return false;
  }
}

Future<bool> disconnectBluetoothDevice(String address) async {
  try {
    final result = await _bluetoothctl(['disconnect', address]);
    return result.exitCode == 0;
  } catch (e) {
    DebugLogger.log('[bluetooth] disconnectBluetoothDevice($address) failed: $e');
    return false;
  }
}
