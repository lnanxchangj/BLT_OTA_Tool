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
    state != OtaState.upgrading &&
    !_isUpgrading;

  // ─────────────────── 选择固件文件 ───────────────────

  Future<void> pickFirmwareFile() async {
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,          // ← 改为 any，不限制扩展名
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) {
      throw Exception('无法读取文件内容，请重新选择');
    }

    // 手动验证扩展名
    final name = file.name.toLowerCase();
    final supportedExts = ['hex', 'srec', 's19', 's28', 's37', 'mot', 's'];
    final ext = name.contains('.') ? name.split('.').last : '';
    if (!supportedExts.contains(ext)) {
      throw Exception(
        '不支持的文件格式: .$ext\n'
        '支持格式: .hex / .srec / .s19 / .s28 / .s37 / .mot',
      );
    }

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
    _addLog(
      '起始地址: 0x${firmware!.startAddress.toRadixString(16).toUpperCase().padLeft(8, '0')}',
    );
    _addLog(
      '结束地址: 0x${firmware!.endAddress.toRadixString(16).toUpperCase().padLeft(8, '0')}',
    );
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

  bool _isUpgrading = false;  // 新增标志

Future<void> startUpgrade() async {
  if (_isUpgrading) {
    statusMsg = '升级正在进行中，请等待...';
    notifyListeners();
    return;
  }
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

  _isUpgrading = true;
  _cleanupXcp();
  
  // 确保BleService还有效
  if (!_bleProvider.bleService.isConnected) {
    _isUpgrading = false;
    statusMsg = '蓝牙连接已断开，请重新连接';
    notifyListeners();
    return;
  }

  _xcpService = XcpService(_bleProvider.bleService);

  _progressSub = _xcpService!.progressStream.listen((p) {
    progress = p.percent;
    progressMsg = p.message;
    notifyListeners();
  });
  _logSub = _xcpService!.logStream.listen(_addLog);

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
    try { await _xcpService?.disconnect(); } catch (_) {}
  } finally {
    _isUpgrading = false;  // 无论成败都释放锁
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