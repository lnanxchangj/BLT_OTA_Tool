import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/ble_service.dart';

class BleProvider extends ChangeNotifier {
  final bleService = BleService();

  List<ScanResult> scanResults = [];
  bool isScanning = false;
  bool isConnected = false;
  String statusMsg = '未连接';
  String? connectedDeviceName;

  // 透传测试日志
  final List<String> txLogs = [];

  StreamSubscription? _scanSub;
  StreamSubscription? _connSub;
  StreamSubscription? _dataSub;

  BleProvider() {
    _connSub = bleService.connectionStream.listen((connected) {
      isConnected = connected;
      statusMsg = connected
          ? '已连接: $connectedDeviceName'
          : '连接已断开';
      notifyListeners();
    });
  }

  // ─────────────────── 权限 ───────────────────

  Future<bool> requestPermissions() async {
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    return statuses.values.every((s) => s.isGranted || s.isLimited);
  }

  // ─────────────────── 扫描 ───────────────────

  Future<void> startScan() async {
    if (!await requestPermissions()) {
      statusMsg = '蓝牙权限未授权';
      notifyListeners();
      return;
    }

    scanResults.clear();
    isScanning = true;
    statusMsg = '扫描中...';
    notifyListeners();

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      scanResults = results
          .where((r) => r.device.platformName.isNotEmpty)
          .toList();
      notifyListeners();
    });

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
    );

    await Future.delayed(const Duration(seconds: 15));
    isScanning = false;
    statusMsg = '扫描完成，找到 ${scanResults.length} 个设备';
    notifyListeners();
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    isScanning = false;
    notifyListeners();
  }

  // ─────────────────── 连接 ───────────────────

  Future<void> connectDevice(BluetoothDevice device) async {
    try {
      statusMsg = '正在连接 ${device.platformName}...';
      notifyListeners();

      await bleService.connect(device);
      connectedDeviceName = device.platformName;
      isConnected = true;
      statusMsg = '已连接: ${device.platformName}';

      // 监听透传数据用于日志展示
      _dataSub?.cancel();
      _dataSub = bleService.dataStream.listen((data) {
        final hex = data
            .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
            .join(' ');
        addLog('← RX [${ data.length}B]: $hex');
      });
    } catch (e) {
      statusMsg = '连接失败: $e';
    }
    notifyListeners();
  }

  Future<void> disconnectDevice() async {
    _dataSub?.cancel();
    await bleService.disconnect();
    isConnected = false;
    connectedDeviceName = null;
    statusMsg = '已断开';
    notifyListeners();
  }

  // ─────────────────── 透传测试 ───────────────────

  Future<void> sendHex(String hexStr) async {
    try {
      final clean = hexStr.replaceAll(' ', '').replaceAll('\n', '');
      if (clean.isEmpty || clean.length % 2 != 0) {
        throw Exception('HEX 格式错误');
      }
      final bytes = <int>[];
      for (int i = 0; i < clean.length; i += 2) {
        bytes.add(int.parse(clean.substring(i, i + 2), radix: 16));
      }
      await bleService.sendData(bytes);
      final hex = bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' ');
      addLog('→ TX [${bytes.length}B]: $hex');
    } catch (e) {
      addLog('发送失败: $e');
    }
    notifyListeners();
  }

  Future<void> sendText(String text) async {
    try {
      final bytes = text.codeUnits;
      await bleService.sendData(bytes);
      addLog('→ TX [${bytes.length}B]: "$text"');
    } catch (e) {
      addLog('发送失败: $e');
    }
    notifyListeners();
  }

  void addLog(String msg) {
    final now = DateTime.now();
    final time = '${now.hour.toString().padLeft(2,'0')}:'
        '${now.minute.toString().padLeft(2,'0')}:'
        '${now.second.toString().padLeft(2,'0')}';
    txLogs.add('[$time] $msg');
    if (txLogs.length > 200) txLogs.removeAt(0);
    notifyListeners();
  }

  void clearLogs() {
    txLogs.clear();
    notifyListeners();
  }

  void setUartConfig(BleUartConfig config) {
    bleService.config = config;
    notifyListeners();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _connSub?.cancel();
    _dataSub?.cancel();
    bleService.dispose();
    super.dispose();
  }
}