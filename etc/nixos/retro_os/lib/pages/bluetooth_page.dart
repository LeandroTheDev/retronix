import 'dart:async';
import 'package:flutter/material.dart';
import '../services/gamepad_service.dart';
import '../utils/app_localizations.dart';
import '../utils/bluetooth.dart';
import '../utils/debug_logger.dart';
import '../utils/snackbar.dart';
import '../utils/sound.dart';

class BluetoothPage extends StatefulWidget {
  const BluetoothPage({super.key});

  @override
  State<BluetoothPage> createState() => _BluetoothPageState();
}

class _BluetoothPageState extends State<BluetoothPage> {
  late final StreamSubscription<GamepadAction> _sub;
  Timer? _refreshTimer;

  static const _refreshInterval = Duration(seconds: 3);
  static const _itemHeight = 88.0;
  final _scrollController = ScrollController();

  List<BluetoothDevice> _devices = [];
  int _selectedIndex = 0;
  bool _loading = true;
  final _busyAddresses = <String>{};

  @override
  void initState() {
    super.initState();
    _sub = GamepadService.instance.actions.listen(_handleAction);
    _startScanning();
  }

  @override
  void dispose() {
    _sub.cancel();
    _refreshTimer?.cancel();
    _scrollController.dispose();
    setBluetoothScanning(false);
    super.dispose();
  }

  Future<void> _startScanning() async {
    await setBluetoothPowered(true);
    unawaited(setBluetoothScanning(true));
    await _refreshDevices();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => _refreshDevices());
  }

  Future<void> _refreshDevices() async {
    final devices = await getBluetoothDevices();
    if (!mounted) return;
    setState(() {
      _devices = devices;
      _selectedIndex = _devices.isEmpty ? 0 : _selectedIndex.clamp(0, _devices.length - 1);
      _loading = false;
    });
  }

  void _handleAction(GamepadAction action) {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    if (action == GamepadAction.back) {
      Navigator.pop(context);
      return;
    }
    if (_devices.isEmpty) return;
    switch (action) {
      case GamepadAction.up:
        setState(() => _selectedIndex = navigateIndex(_selectedIndex, -1, _devices.length - 1));
        _scrollToSelected();
      case GamepadAction.down:
        setState(() => _selectedIndex = navigateIndex(_selectedIndex, 1, _devices.length - 1));
        _scrollToSelected();
      case GamepadAction.confirm:
        _toggleConnection(_devices[_selectedIndex]);
      default:
        break;
    }
  }

  void _scrollToSelected() {
    final offset = (_selectedIndex * _itemHeight) -
        (_scrollController.position.viewportDimension / 2) +
        (_itemHeight / 2);
    _scrollController.animateTo(
      offset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  Future<void> _toggleConnection(BluetoothDevice device) async {
    if (_busyAddresses.contains(device.address)) return;
    setState(() => _busyAddresses.add(device.address));
    try {
      final success = device.connected
          ? await disconnectBluetoothDevice(device.address)
          : await pairAndConnect(device.address);
      if (!success && mounted) {
        final l = AppLocalizations.of(context);
        showErrorSnackBar(
          context,
          device.connected
              ? l.bluetoothDisconnectFailed(device.name)
              : l.bluetoothConnectFailed(device.name),
        );
      }
    } catch (e) {
      DebugLogger.log('[BluetoothPage] _toggleConnection(${device.address}) failed: $e');
    } finally {
      if (mounted) setState(() => _busyAddresses.remove(device.address));
      await _refreshDevices();
    }
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
            child: Row(
              children: [
                Text(
                  l.bluetoothTitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 16, letterSpacing: 5),
                ),
                const SizedBox(width: 16),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(color: Colors.white24, strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  l.bluetoothScanning,
                  style: const TextStyle(color: Colors.white24, fontSize: 13),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(l)),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations l) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_devices.isEmpty) {
      return Center(
        child: Text(
          l.bluetoothNoDevicesFound,
          style: const TextStyle(color: Colors.white30, fontSize: 16),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      itemCount: _devices.length,
      itemExtent: _itemHeight,
      itemBuilder: (context, index) {
        final device = _devices[index];
        return _BluetoothDeviceRow(
          device: device,
          selected: index == _selectedIndex,
          busy: _busyAddresses.contains(device.address),
          l: l,
        );
      },
    );
  }
}

class _BluetoothDeviceRow extends StatelessWidget {
  const _BluetoothDeviceRow({
    required this.device,
    required this.selected,
    required this.busy,
    required this.l,
  });

  final BluetoothDevice device;
  final bool selected;
  final bool busy;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.black : Colors.white;

    final String status;
    if (busy) {
      status = device.connected ? l.bluetoothDisconnecting : l.bluetoothConnecting;
    } else if (device.connected) {
      status = l.bluetoothConnected;
    } else if (device.paired) {
      status = l.bluetoothPaired;
    } else {
      status = '';
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      margin: const EdgeInsets.symmetric(horizontal: 80, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        color: selected ? Colors.white : Colors.white10,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            device.connected ? Icons.bluetooth_connected : Icons.bluetooth,
            color: selected ? Colors.black : Colors.white54,
            size: 22,
          ),
          const SizedBox(width: 20),
          Expanded(
            flex: 3,
            child: Text(
              device.name.isNotEmpty ? device.name : device.address,
              style: TextStyle(
                color: fg,
                fontSize: 18,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              status,
              textAlign: TextAlign.right,
              softWrap: true,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.black : Colors.white60,
                fontSize: 16,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
