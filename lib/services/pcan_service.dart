// pcan_service.dart
// PCAN-USB CAN升级功能 - 待实现（仅Windows桌面）
// 实现时需通过 dart:ffi 调用 PCANBasic.dll

import 'dart:async';
import 'dart:typed_data';
import 'i_transport.dart';

class PcanService implements ITransport {
  @override
  Stream<Uint8List> get dataStream =>
      const Stream.empty();

  @override
  bool get isConnected => false;

  Future<void> open(int channel, int baudRate) async {
    throw UnimplementedError('PCAN功能暂未实现，需配置 PCANBasic.dll');
  }

  @override
  Future<void> sendData(List<int> data) async {
    throw UnimplementedError('PCAN功能暂未实现');
  }

  @override
  Future<void> disconnect() async {}

  void dispose() {}
}