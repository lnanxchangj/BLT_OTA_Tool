import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/firmware_data.dart';
import '../services/firmware_parser.dart';
import '../services/xcp_service.dart';
import 'ble_provider.dart';

enum OtaState { idle, parsing, upgrading, success, failed }

class OtaProvider extends ChangeNotifier {
  final BleProvider _bleProvider;
  XcpService? _xcpService;

  FirmwareData? firmware;
  OtaState state = OtaState.idle;
  String statusMsg = '请先选择固件文件';
  double progress = 0.0;
  String progressMsg = '';
  final List<String> logs = [];

  StreamSubscription? _progressSub;
  StreamSubscription? _logSub;

  OtaProvider(this._bleProvider);

  bool get canUpgrade =>
      firmware != null &&
      _bleProvider.isConnected &&
      state != OtaState.upgrading;

  // ─────────────────── 选择固件文件 ───────────────────

  Future<void> pickFirmwareFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['hex', 'srec', 's19', 's28', 's37', 'mot'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) throw Exception('无法读取文件内容');

      state = OtaState.parsing;
      statusMsg = '解析中...';
      notifyListeners();

      final content = String.fromCharCodes(file.bytes!);
      firmware = FirmwareParser.parse(file.name, content);

      state = OtaState.idle;
      statusMsg = '固件已加载: ${file.name}';
      _addLog('固件解析成功');
      _addLog('文件: ${firmware!.fileName}');
      _addLog('类型: ${firmware!.fileType.toUpperCase()}');
      _addLog('起始地址: 0x${firmware!.startAddress.toRadixString(16).toUpperCase().padLeft(8,'0')}');
      _addLog('结束地址: 0x${firmware!.endAddress.toRadixString(16).toUpperCase().padLeft(8,'0')}');
      _addLog('总字节数: ${firmware!.totalBytes} 字节');
      _addLog('内存段数: ${firmware!.segments.length}');
      for (final seg in firmware!.segments) {
        _addLog('  段: $seg');
      }
    } catch (e) {
      state = OtaState.failed;
      statusMsg = '解析失败: $e';
      _addLog('错误: $e');
    }
    notifyListeners();
  }

  // ─────────────────── 开始升级 ───────────────────

  Future<void> startUpgrade() async {
    if (firmware == null) {
      statusMsg = '请先选择固件';
      notifyListeners();
      return;
    }
    if (!_bleProvider.isConnected) {
      statusMsg = '请先连接蓝牙设备';
      notifyListeners();
      return;
    }

    // 清理上次的 XCP 服务
    _cleanupXcp();

    _xcpService = XcpService(_bleProvider.bleService);

    _progressSub = _xcpService!.progressStream.listen((p) {
      progress = p.percent;
      progressMsg = p.message;
      notifyListeners();
    });

    _logSub = _xcpService!.logStream.listen((msg) {
      _addLog(msg);
    });

    state = OtaState.upgrading;
    progress = 0.0;
    statusMsg = '升级中...';
    notifyListeners();

    try {
      await _xcpService!.upgradeFromFirmware(firmware!);
      state = OtaState.success;
      statusMsg = '升级成功！';
      progress = 1.0;
    } catch (e) {
      state = OtaState.failed;
      statusMsg = '升级失败: $e';
      _addLog('升级异常: $e');
      try {
        await _xcpService!.disconnect();
      } catch (_) {}
    }
    notifyListeners();
  }

  void _addLog(String msg) {
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2,'0')}:'
        '${now.minute.toString().padLeft(2,'0')}:'
        '${now.second.toString().padLeft(2,'0')}';
    logs.add('[$time] $msg');
    if (logs.length > 500) logs.removeAt(0);
  }

  void clearLogs() {
    logs.clear();
    notifyListeners();
  }

  void _cleanupXcp() {
    _progressSub?.cancel();
    _logSub?.cancel();
    _xcpService?.dispose();
    _xcpService = null;
  }

  @override
  void dispose() {
    _cleanupXcp();
    super.dispose();
  }
}