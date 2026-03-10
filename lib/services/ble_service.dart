import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// 蓝牙透传模块配置（常见模组UUID）
class BleUartConfig {
  final String name;
  final String serviceUuid;
  final String writeUuid;   // 手机 -> 模组（TX）
  final String notifyUuid;  // 模组 -> 手机（RX）

  const BleUartConfig({
    required this.name,
    required this.serviceUuid,
    required this.writeUuid,
    required this.notifyUuid,
  });

  static const nordicUart = BleUartConfig(
    name: 'Nordic UART (NUS)',
    serviceUuid: '6e400001-b5a3-f393-e0a9-e50e24dcca9e',
    writeUuid: '6e400002-b5a3-f393-e0a9-e50e24dcca9e',
    notifyUuid: '6e400003-b5a3-f393-e0a9-e50e24dcca9e',
  );

  static const hm10 = BleUartConfig(
    name: 'HM-10 / CC2541',
    serviceUuid: '0000ffe0-0000-1000-8000-00805f9b34fb',
    writeUuid: '0000ffe1-0000-1000-8000-00805f9b34fb',
    notifyUuid: '0000ffe1-0000-1000-8000-00805f9b34fb',
  );

  static const List<BleUartConfig> presets = [nordicUart, hm10];
}

class BleService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;
  StreamSubscription? _notifySub;
  StreamSubscription? _connStateSub;

  final _dataController = StreamController<Uint8List>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  Stream<Uint8List> get dataStream => _dataController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;

  BleUartConfig config = BleUartConfig.nordicUart;

  BluetoothDevice? get device => _device;
  bool get isConnected => _device != null && _writeChar != null;

  /// 连接设备并发现 UART 服务
  Future<void> connect(BluetoothDevice device) async {
    await disconnect();
    _device = device;

    await device.connect(
      autoConnect: false,
      timeout: const Duration(seconds: 15),
    );

    _connStateSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _connectionController.add(false);
        _cleanup();
      }
    });

    // 请求更大 MTU 提升传输效率
    try {
      await device.requestMtu(512);
    } catch (_) {}

    await _discoverUartService();
    _connectionController.add(true);
  }

  Future<void> _discoverUartService() async {
    if (_device == null) return;
    final services = await _device!.discoverServices();

    final targetServiceUuid = config.serviceUuid.toLowerCase();
    final targetWriteUuid = config.writeUuid.toLowerCase();
    final targetNotifyUuid = config.notifyUuid.toLowerCase();

    for (final service in services) {
      if (service.uuid.toString().toLowerCase() != targetServiceUuid) continue;

      for (final char in service.characteristics) {
        final uuid = char.uuid.toString().toLowerCase();

        if (uuid == targetWriteUuid &&
            (char.properties.write || char.properties.writeWithoutResponse)) {
          _writeChar = char;
        }

        if (uuid == targetNotifyUuid &&
            (char.properties.notify || char.properties.indicate)) {
          _notifyChar = char;
          await char.setNotifyValue(true);
          _notifySub = char.lastValueStream.listen((data) {
            if (data.isNotEmpty) {
              _dataController.add(Uint8List.fromList(data));
            }
          });
        }
      }
      break;
    }

    if (_writeChar == null) {
      throw Exception(
        '未找到写入特征值 (${config.writeUuid})\n请确认蓝牙模块型号与UUID配置');
    }
    if (_notifyChar == null) {
      throw Exception(
        '未找到通知特征值 (${config.notifyUuid})\n请确认蓝牙模块型号与UUID配置');
    }
  }

  /// 发送原始数据（自动按 MTU 分包）
  Future<void> sendData(List<int> data) async {
    if (_writeChar == null) throw Exception('蓝牙未连接');

    final mtu = (_device?.mtuNow ?? 23) - 3; // 实际可用 MTU
    final useWriteWithoutResponse = _writeChar!.properties.writeWithoutResponse;

    for (int i = 0; i < data.length; i += mtu) {
      final end = (i + mtu).clamp(0, data.length);
      final chunk = data.sublist(i, end);
      await _writeChar!.write(
        chunk,
        withoutResponse: useWriteWithoutResponse,
      );
      if (useWriteWithoutResponse) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
    }
  }

  Future<void> disconnect() async {
    _cleanup();
    try {
      await _device?.disconnect();
    } catch (_) {}
    _device = null;
    _connectionController.add(false);
  }

  void _cleanup() {
    _notifySub?.cancel();
    _notifySub = null;
    _connStateSub?.cancel();
    _connStateSub = null;
    _writeChar = null;
    _notifyChar = null;
  }

  void dispose() {
    _cleanup();
    _dataController.close();
    _connectionController.close();
  }
}