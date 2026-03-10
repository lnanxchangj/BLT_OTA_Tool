import 'dart:typed_data';
import 'dart:async';

abstract class ITransport {
  Stream<Uint8List> get dataStream;
  Future<void> sendData(List<int> data);
  bool get isConnected;
  Future<void> disconnect();
}