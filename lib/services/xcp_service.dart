import 'dart:async';
import 'dart:typed_data';
import 'ble_service.dart';
import '../models/firmware_data.dart';

/// XCP 错误码
const Map<int, String> xcpErrors = {
  0x00: 'ERR_CMD_SYNCH',
  0x10: 'ERR_CMD_BUSY',
  0x11: 'ERR_DAQ_ACTIVE',
  0x12: 'ERR_PGM_ACTIVE',
  0x20: 'ERR_CMD_UNKNOWN',
  0x21: 'ERR_CMD_SYNTAX',
  0x22: 'ERR_OUT_OF_RANGE',
  0x23: 'ERR_WRITE_PROTECTED',
  0x24: 'ERR_ACCESS_DENIED',
  0x25: 'ERR_ACCESS_LOCKED',
  0x26: 'ERR_PAGE_NOT_VALID',
  0x27: 'ERR_MODE_NOT_VALID',
  0x28: 'ERR_SEGMENT_NOT_VALID',
  0x29: 'ERR_SEQUENCE',
  0x2A: 'ERR_DAQ_CONFIG',
  0x30: 'ERR_MEMORY_OVERFLOW',
  0x31: 'ERR_GENERIC',
  0x32: 'ERR_VERIFY',
};

/// XCP 升级进度信息
class XcpProgress {
  final int currentBytes;
  final int totalBytes;
  final String stage;
  final String message;
  final double percent;

  const XcpProgress({
    required this.currentBytes,
    required this.totalBytes,
    required this.stage,
    required this.message,
    required this.percent,
  });
}

/// OpenBLT XCP over UART（通过蓝牙透传）协议实现
///
/// UART 帧格式：[LENGTH][COUNTER][XCP_DATA...]
/// LENGTH  = XCP_DATA 的字节数（不含 LENGTH 和 COUNTER 本身）
/// COUNTER = 包计数器 0-255 循环
class XcpService {
  final BleService _ble;

  int _counter = 0;
  int _maxCto = 8; // 从 CONNECT 响应获取
  bool _littleEndian = true; // 大多数 ARM 为小端

  Completer<List<int>>? _pending;
  final List<int> _rxBuf = [];
  StreamSubscription? _dataSub;

  final _progressCtrl = StreamController<XcpProgress>.broadcast();
  final _logCtrl = StreamController<String>.broadcast();

  Stream<XcpProgress> get progressStream => _progressCtrl.stream;
  Stream<String> get logStream => _logCtrl.stream;

  XcpService(this._ble) {
    _dataSub = _ble.dataStream.listen(_onData);
  }

  // ─────────────────────────── 数据接收 ───────────────────────────

  void _onData(Uint8List data) {
    _rxBuf.addAll(data);
    _tryParse();
  }

  void _tryParse() {
    while (_rxBuf.length >= 2) {
      final expectedLen = _rxBuf[0] + 2; // length + counter + data
      if (_rxBuf.length < expectedLen) break;

      final packet = List<int>.from(_rxBuf.sublist(0, expectedLen));
      _rxBuf.removeRange(0, expectedLen);

      final xcpData = packet.sublist(2); // 去掉 LENGTH 和 COUNTER
      _log('← RX: ${_bytesToHex(packet)}');

      if (_pending != null && !_pending!.isCompleted) {
        _pending!.complete(xcpData);
        _pending = null;
      }
    }
  }

  // ─────────────────────────── 底层发送 ───────────────────────────

  Future<List<int>> _send(
    List<int> xcpData, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    _rxBuf.clear();
    _pending = Completer<List<int>>();

    final frame = [xcpData.length, _counter & 0xFF, ...xcpData];
    _counter = (_counter + 1) & 0xFF;

    _log('→ TX: ${_bytesToHex(frame)}');
    await _ble.sendData(frame);

    final response = await _pending!.future.timeout(
      timeout,
      onTimeout: () => throw TimeoutException('响应超时'),
    );
    _pending = null;

    if (response.isEmpty) throw Exception('收到空响应');
    if (response[0] == 0xFE) {
      final errCode = response.length > 1 ? response[2] : 0;
      final errMsg = xcpErrors[errCode] ?? '未知错误(0x${errCode.toRadixString(16)})';
      throw Exception('XCP 错误: $errMsg');
    }
    if (response[0] != 0xFF) {
      throw Exception(
        '意外响应头: 0x${response[0].toRadixString(16).toUpperCase()}');
    }

    return response;
  }

  // ─────────────────────────── XCP 命令 ───────────────────────────

  /// CONNECT (0xFF) - 连接 Bootloader
  Future<void> connect() async {
    _log('[XCP] CONNECT');
    final resp = await _send([0xFF, 0x00]); // mode=0x00 normal
    if (resp.length >= 8) {
      final commMode = resp[2];
      _littleEndian = (commMode & 0x01) == 1;
      _maxCto = resp[3];
      _log(
        '[XCP] CONNECT OK: maxCTO=$_maxCto '
        'byteOrder=${_littleEndian ? 'LE' : 'BE'}');
    }
  }

  /// DISCONNECT (0xFE)
  Future<void> disconnect() async {
    _log('[XCP] DISCONNECT');
    try {
      await _send([0xFE]);
    } catch (_) {}
  }

  /// PROGRAM_START (0xF2) - 进入编程模式
  Future<void> programStart() async {
    _log('[XCP] PROGRAM_START');
    await _send([0xF2]);
    _log('[XCP] 进入编程模式');
  }

  /// SET_MTA (0xF6) - 设置内存传输地址
  Future<void> setMta(int address) async {
    _log('[XCP] SET_MTA 0x${address.toRadixString(16).toUpperCase().padLeft(8,'0')}');
    final addrBytes = _u32(address);
    await _send([0xF6, 0x00, 0x00, 0x00, ...addrBytes]);
  }

  /// PROGRAM_CLEAR (0xF3) - 擦除 [MTA, MTA+size)
  Future<void> programClear(int size) async {
    _log('[XCP] PROGRAM_CLEAR size=0x${size.toRadixString(16).toUpperCase()}');
    final sizeBytes = _u32(size);
    await _send(
      [0xF3, 0x00, 0x00, 0x00, ...sizeBytes],
      timeout: const Duration(seconds: 60), // 擦除耗时较长
    );
    _log('[XCP] 擦除完成');
  }

  /// PROGRAM_RESET (0xEF) - 复位设备（完成升级）
  Future<void> programReset() async {
    _log('[XCP] PROGRAM_RESET');
    try {
      await _send([0xEF], timeout: const Duration(seconds: 3));
    } catch (_) {
      // 复位后设备可能不回应，忽略超时
    }
    _log('[XCP] 设备已复位');
  }

  // ─────────────────────────── 编程核心 ───────────────────────────

  /// 对单个内存段进行擦除+编程
  Future<void> _programSegment(
    FirmwareSegment segment,
    int totalBytes,
    int doneBytes,
  ) async {
    _log('[XCP] 段: ${segment}');

    // 1. 擦除
    _emitProgress(doneBytes, totalBytes, 'erase',
      '擦除 0x${segment.address.toRadixString(16).toUpperCase()}...');
    await setMta(segment.address);
    await programClear(segment.size);

    // 2. 编程（MTA 在 CLEAR 后保持不变，正好指向段起始地址）
    final maxData = _maxCto - 1; // PROGRAM_MAX 每帧最多数据字节数
    int offset = 0;

    while (offset < segment.data.length) {
      final remaining = segment.data.length - offset;
      final chunkSize = remaining >= maxData ? maxData : remaining;
      final chunk = segment.data.sublist(offset, offset + chunkSize);

      // 不足 maxData 时用 0xFF 补齐（已擦除区域为 0xFF，安全）
      final padded = chunkSize < maxData
          ? [...chunk, ...List.filled(maxData - chunkSize, 0xFF)]
          : chunk;

      // PROGRAM_MAX (0xEE): [0xEE, data...(maxData bytes)]
      await _send([0xEE, ...padded]);

      offset += chunkSize;
      final done = doneBytes + offset;
      _emitProgress(
        done,
        totalBytes,
        'program',
        '编程 ${(done / totalBytes * 100).toStringAsFixed(1)}%',
      );
    }
  }

  /// 执行完整固件升级流程
  Future<void> upgradeFromFirmware(FirmwareData firmware) async {
    final totalBytes = firmware.segments
        .fold(0, (s, seg) => s + seg.size);
    int doneBytes = 0;

    _log('=== 开始升级: ${firmware.fileName} ===');
    _log('总字节数: $totalBytes  段数: ${firmware.segments.length}');

    // Step 1: XCP CONNECT
    _emitProgress(0, totalBytes, 'connect', '正在连接 Bootloader...');
    await connect();

    // Step 2: PROGRAM_START
    _emitProgress(0, totalBytes, 'start', '进入编程模式...');
    await programStart();

    // Step 3: 逐段擦除 + 编程
    for (final seg in firmware.segments) {
      await _programSegment(seg, totalBytes, doneBytes);
      doneBytes += seg.size;
    }

    // Step 4: 完成，复位运行新固件
    _emitProgress(totalBytes, totalBytes, 'reset', '编程完成，复位设备...');
    await programReset();

    _emitProgress(totalBytes, totalBytes, 'done', '升级成功！');
    _log('=== 升级完成 ===');
  }

  // ─────────────────────────── 工具方法 ───────────────────────────

  List<int> _u32(int value) {
    if (_littleEndian) {
      return [
        value & 0xFF,
        (value >> 8) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 24) & 0xFF,
      ];
    } else {
      return [
        (value >> 24) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 8) & 0xFF,
        value & 0xFF,
      ];
    }
  }

  void _emitProgress(int done, int total, String stage, String msg) {
    _progressCtrl.add(XcpProgress(
      currentBytes: done,
      totalBytes: total,
      stage: stage,
      message: msg,
      percent: total > 0 ? done / total : 0.0,
    ));
    _log('[进度] $msg');
  }

  void _log(String msg) => _logCtrl.add(msg);

  String _bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

  void dispose() {
    _dataSub?.cancel();
    _progressCtrl.close();
    _logCtrl.close();
  }
}