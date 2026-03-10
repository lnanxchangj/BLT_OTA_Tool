// serial_service.dart
// 串口升级功能 - 待实现（需要桌面平台支持）
// 实现时需在 pubspec.yaml 添加:
//   flutter_libserialport: ^0.3.0
// 并确保在 Windows/Linux/macOS 桌面平台运行

import 'dart:async';
import 'dart:typed_data';
import 'i_transport.dart';

class SerialService implements ITransport {
  // 获取可用串口列表（桩实现）
  static List<String> get availablePorts => [];

  @override
  Stream<Uint8List> get dataStream =>
      const Stream.empty();

  @override
  bool get isConnected => false;

  Future<void> open(String portName, int baudRate) async {
    throw UnimplementedError('串口功能暂未实现，需安装 flutter_libserialport');
  }

  @override
  Future<void> sendData(List<int> data) async {
    throw UnimplementedError('串口功能暂未实现');
  }

  @override
  Future<void> disconnect() async {}

  void dispose() {}
}