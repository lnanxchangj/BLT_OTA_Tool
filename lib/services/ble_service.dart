import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleUartConfig {
  final String name;
  final String serviceUuid;
  final String writeUuid;
  final String notifyUuid;

  const BleUartConfig({
    required this.name,
    required this.serviceUuid,
    required this.writeUuid,
    required this.notifyUuid,
  });

  static const nordicUart = BleUartConfig(
    name: 'Nordic UART (NUS)',
    serviceUuid: '6e400001-b5a3-f393-e0a9-e50e24dcca9e',
    writeUuid:   '6e400002-b5a3-f393-e0a9-e50e24dcca9e',
    notifyUuid:  '6e400003-b5a3-f393-e0a9-e50e24dcca9e',
  );

  static const hm10 = BleUartConfig(
    name: 'HM-10 / CC2541 (FFE1=RX FFE1=TX)',
    serviceUuid: '0000ffe0-0000-1000-8000-00805f9b34fb',
    writeUuid:   '0000ffe1-0000-1000-8000-00805f9b34fb',
    notifyUuid:  '0000ffe1-0000-1000-8000-00805f9b34fb',
  );

  // ← 你的模块：FFE1=通知(RX), FFE2=写入(TX)
  static const ffe1Notify_ffe2Write = BleUartConfig(
    name: 'nanchang_ble',
    serviceUuid: '0000ffe0-0000-1000-8000-00805f9b34fb',
    writeUuid:   '0000ffe2-0000-1000-8000-00805f9b34fb',
    notifyUuid:  '0000ffe1-0000-1000-8000-00805f9b34fb',
  );

  static const List<BleUartConfig> presets = [
    ffe1Notify_ffe2Write, // 放第一位作为默认
    nordicUart,
    hm10,
  ];
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

  // 默认使用你的模块配置
  BleUartConfig config = BleUartConfig.ffe1Notify_ffe2Write;

  BluetoothDevice? get device => _device;
  bool get isConnected => _device != null && _writeChar != null;

  Future<void> connect(BluetoothDevice device) async {
    // 先彻底清理旧连接
    await disconnect();
    await Future.delayed(const Duration(milliseconds: 500)); // 等待 BLE 栈稳定

    _device = device;

    try {
      await device.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 15),
      );
    } catch (e) {
      _device = null;
      rethrow;
    }

    _connStateSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _connectionController.add(false);
        _cleanup();
      }
    });

    // 请求 MTU（只请求一次，避免重复请求）
    try {
      await device.requestMtu(247);
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      // MTU 请求失败不致命，继续
    }

    try {
      await _discoverUartService();
    } catch (e) {
      // 发现服务失败，断开并抛出
      await disconnect();
      rethrow;
    }

    _connectionController.add(true);
  }

  Future<void> _discoverUartService() async {
    if (_device == null) throw Exception('设备未连接');

    final services = await _device!.discoverServices();

    // 打印所有发现的服务（调试用）
    for (final s in services) {
      final chars = s.characteristics.map((c) =>
          '    char: ${c.uuid} W:${c.properties.write} '
          'WNR:${c.properties.writeWithoutResponse} '
          'N:${c.properties.notify} I:${c.properties.indicate}').join('\n');
      print('[BLE] Service: ${s.uuid}\n$chars');
    }

    final targetSvcUuid = config.serviceUuid.toLowerCase();
    final targetWriteUuid = config.writeUuid.toLowerCase();
    final targetNotifyUuid = config.notifyUuid.toLowerCase();

    for (final service in services) {
      final svcUuid = service.uuid.toString().toLowerCase();

      // 支持短UUID匹配（ffe0 匹配 0000ffe0-...）
      final svcMatch = svcUuid == targetSvcUuid ||
          svcUuid.contains(targetSvcUuid.replaceAll('-', '').substring(0, 8)) ||
          targetSvcUuid.contains(svcUuid);

      if (!svcMatch) continue;

      print('[BLE] 匹配到目标Service: $svcUuid');

      for (final char in service.characteristics) {
        final uuid = char.uuid.toString().toLowerCase();

        final writeMatch = uuid == targetWriteUuid ||
            uuid.contains(targetWriteUuid.substring(4, 8));
        final notifyMatch = uuid == targetNotifyUuid ||
            uuid.contains(targetNotifyUuid.substring(4, 8));

        if (writeMatch &&
            (char.properties.write || char.properties.writeWithoutResponse)) {
          _writeChar = char;
          print('[BLE] 写入特征值: $uuid');
        }

        if (notifyMatch &&
            (char.properties.notify || char.properties.indicate)) {
          _notifyChar = char;
          print('[BLE] 通知特征值: $uuid');
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
      // 列出所有特征值帮助排查
      final allChars = services.expand((s) => s.characteristics)
          .map((c) => '${c.uuid} W:${c.properties.write} '
              'WNR:${c.properties.writeWithoutResponse}')
          .join('\n');
      throw Exception(
        '未找到写入特征值 (${config.writeUuid})\n'
        '已发现特征值:\n$allChars');
    }
    if (_notifyChar == null) {
      throw Exception('未找到通知特征值 (${config.notifyUuid})');
    }
  }

  /// 发送原始数据
  Future<void> sendData(List<int> data) async {
    if (_writeChar == null) throw Exception('蓝牙未连接');

    final mtu = ((_device?.mtuNow ?? 23) - 3).clamp(20, 244);
    final useWNR = _writeChar!.properties.writeWithoutResponse;

    for (int i = 0; i < data.length; i += mtu) {
      final end = (i + mtu).clamp(0, data.length);
      await _writeChar!.write(
        data.sublist(i, end),
        withoutResponse: useWNR,
      );
      if (useWNR) {
        await Future.delayed(const Duration(milliseconds: 30));
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