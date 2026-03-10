import 'dart:async';
import 'dart:typed_data';
import 'ble_service.dart';
import '../models/firmware_data.dart';

const Map<int, String> xcpErrors = {
  0x00: 'CMD_SYNCH',   0x10: 'CMD_BUSY',    0x20: 'CMD_UNKNOWN',
  0x21: 'CMD_SYNTAX',  0x22: 'OUT_OF_RANGE', 0x23: 'WRITE_PROTECTED',
  0x24: 'ACCESS_DENIED', 0x25: 'ACCESS_LOCKED', 0x29: 'SEQUENCE',
  0x30: 'MEMORY_OVERFLOW', 0x31: 'GENERIC',  0x32: 'VERIFY',
};

// ── 对齐Python xcp_master.py 的命令码 ──────────────────────────────
class _Cmd {
  static const connect      = 0xFF;
  static const disconnect   = 0xFE;
  static const setMta       = 0xF6;
  static const programStart = 0xD2;  // Python: 0xD2
  static const programClear = 0xD1;  // Python: 0xD1
  static const program      = 0xD0;  // Python: 0xD0
  static const programReset = 0xCF;  // Python: 0xCF
}

class XcpProgress {
  final int currentBytes;
  final int totalBytes;
  final String stage;
  final String message;
  final double percent;
  const XcpProgress({
    required this.currentBytes, required this.totalBytes,
    required this.stage, required this.message, required this.percent,
  });
}

class XcpService {
  final BleService _ble;

  int _maxCto = 8;
  int _pgmMaxCto = 8;
  bool _littleEndian = true;

  Completer<List<int>>? _pending;
  final List<int> _rxBuf = [];
  StreamSubscription? _dataSub;

  final _progressCtrl = StreamController<XcpProgress>.broadcast();
  final _logCtrl      = StreamController<String>.broadcast();

  Stream<XcpProgress> get progressStream => _progressCtrl.stream;
  Stream<String>      get logStream      => _logCtrl.stream;

  XcpService(this._ble) {
    _dataSub = _ble.dataStream.listen(_onData);
  }

  // ─────────────────────────── 数据接收 ───────────────────────────

  void _onData(Uint8List data) {
    // 打印原始数据
    _log('← RAW [${data.length}B]: ${_hex(data.toList())}  '
        '| "${_ascii(data)}"');
    _rxBuf.addAll(data);
    _tryParse();
  }

  void _tryParse() {
    // OpenBLT帧格式（无COUNTER）: [LENGTH][XCP_DATA...]
    // LENGTH = XCP_DATA字节数
    while (_rxBuf.length >= 1) {
      final dataLen = _rxBuf[0];

      // 防御非XCP数据（如ASCII文本ERROR\r\n，首字节0x45=69）
      if (dataLen == 0 || dataLen > 128) {
        _log('⚠ 非XCP帧头(0x${_rxBuf[0].toRadixString(16)}="${_ascii(Uint8List.fromList(_rxBuf.take(8).toList()))}"), 丢弃');
        _rxBuf.clear();
        if (_pending != null && !_pending!.isCompleted) {
          _pending!.complete([0x00]); // 非空但非0xFF，触发上层报错
          _pending = null;
        }
        return;
      }

      final totalLen = dataLen + 1; // 1(length字节) + dataLen
      if (_rxBuf.length < totalLen) return; // 等待更多数据

      final packet  = List<int>.from(_rxBuf.sublist(0, totalLen));
      _rxBuf.removeRange(0, totalLen);

      final xcpData = packet.sublist(1); // 去掉LENGTH字节
      _log('← 帧[${totalLen}B]: ${_hex(packet)}  XCP: ${_hex(xcpData)}');

      if (_pending != null && !_pending!.isCompleted) {
        _pending!.complete(xcpData);
        _pending = null;
      }
    }
  }

  // ─────────────────────────── 底层发送 ───────────────────────────

  /// 发送XCP命令，等待响应
  /// 帧格式: [LENGTH][XCP_DATA...]  ← 无COUNTER，与Python一致
Future<List<int>> _send(
  List<int> xcpData, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  // 取消上一个未完成的请求
  if (_pending != null && !_pending!.isCompleted) {
    _pending!.complete([]);
  }
  _rxBuf.clear();
  
  final completer = Completer<List<int>>();
  _pending = completer;  // 保存引用

  final frame = [xcpData.length, ...xcpData];
  _log('→ TX [${frame.length}B]: ${_hex(frame)}');
  
  try {
    await _ble.sendData(frame);
  } catch (e) {
    _pending = null;
    throw Exception('BLE发送失败: $e');
  }

  List<int> response;
  try {
    // 用本地变量引用，避免_pending被置null后的空指针
    response = await completer.future.timeout(timeout);
  } on TimeoutException {
    _pending = null;
    _log('✗ 超时 ${timeout.inSeconds}s');
    throw TimeoutException('响应超时(${timeout.inSeconds}s)，请确认下位机处于Bootloader状态');
  } catch (e) {
    _pending = null;
    rethrow;
  }
  _pending = null;

  if (response.isEmpty) {
    throw Exception('收到空响应（可能是非XCP数据被丢弃）');
  }
  if (response[0] == 0xFE) {
    final code = response.length > 1 ? response[1] : 0x31;
    final msg  = xcpErrors[code] ?? '0x${code.toRadixString(16)}';
    throw Exception('XCP错误: $msg');
  }
  if (response[0] != 0xFF) {
    throw Exception('非正响应: ${_hex(response)}');
  }

  _log('✓ 响应: ${_hex(response)}');
  return response;
}

  // ─────────────────────────── XCP 命令 ───────────────────────────

  /// CONNECT (0xFF)
  Future<void> connect() async {
    _log('[XCP] CONNECT →');
    // 先排空缓冲
    _rxBuf.clear();
    await Future.delayed(const Duration(milliseconds: 100));

    final resp = await _send([_Cmd.connect, 0x00]);

    // 解析CONNECT响应（对齐Python _parse_connect_response）
    // resp: [0xFF, resource, comm_mode, max_cto, max_dto_hi, max_dto_lo, proto, trans]
    if (resp.length >= 8) {
      final commMode = resp[2];
      _littleEndian = (commMode & 0x01) == 0; // Python: bit0=0 → LE
      _maxCto       = resp[3];
      final maxDto  = (resp[4] << 8) | resp[5];
      _log('[XCP] CONNECT OK: LE=$_littleEndian maxCTO=$_maxCto maxDTO=$maxDto');
    } else {
      _log('[XCP] CONNECT OK (响应短，使用默认参数)');
    }
  }

  /// DISCONNECT (0xFE)
  Future<void> disconnect() async {
    _log('[XCP] DISCONNECT');
    try { await _send([_Cmd.disconnect], timeout: const Duration(seconds: 2)); }
    catch (_) {}
  }

  /// PROGRAM_START (0xD2)
  Future<void> programStart() async {
    _log('[XCP] PROGRAM_START (0xD2)');
    final resp = await _send(
      [_Cmd.programStart],
      timeout: const Duration(seconds: 10),
    );
    // resp: [0xFF, 0x00, 0x00, pgm_max_cto, ...]
    if (resp.length >= 4 && resp[3] > 0) {
      _pgmMaxCto = resp[3];
    } else {
      _pgmMaxCto = _maxCto;
    }
    _log('[XCP] PROGRAM_START OK, pgmMaxCTO=$_pgmMaxCto');
  }

  /// SET_MTA (0xF6)
  Future<void> setMta(int address) async {
    _log('[XCP] SET_MTA 0x${address.toRadixString(16).padLeft(8, '0').toUpperCase()}');
    await _send([_Cmd.setMta, 0x00, 0x00, 0x00, ..._u32(address)]);
  }

  /// PROGRAM_CLEAR (0xD1)
  Future<void> programClear(int size) async {
    _log('[XCP] PROGRAM_CLEAR size=0x${size.toRadixString(16).toUpperCase()}');
    await _send(
      [_Cmd.programClear, 0x00, 0x00, 0x00, ..._u32(size)],
      timeout: const Duration(seconds: 60),
    );
    _log('[XCP] 擦除完成');
  }

  /// PROGRAM (0xD0) - 对齐Python: [0xD0, actual_len, data...]
  Future<void> programChunk(List<int> data) async {
    final maxPayload = _pgmMaxCto - 2; // cmd(1) + len(1) + data
    if (data.length > maxPayload) {
      throw Exception('数据块太大: ${data.length} > $maxPayload');
    }
    await _send(
      [_Cmd.program, data.length, ...data],
      timeout: const Duration(seconds: 5),
    );
  }

  /// PROGRAM(0xD0) 发空包 = 通知一段结束（Python upload_firmware末尾有此步骤）
  Future<void> programEmpty() async {
    _log('[XCP] PROGRAM 空包 (段结束标记)');
    try {
      await _send([_Cmd.program, 0x00], timeout: const Duration(seconds: 5));
    } catch (_) {}
  }

  /// PROGRAM_RESET (0xCF) - 超时=正常（设备跳转APP后不回复）
  Future<void> programReset() async {
    _log('[XCP] PROGRAM_RESET (0xCF)');
    _rxBuf.clear();
    final frame = [1, _Cmd.programReset]; // [length=1][cmd]
    _log('→ TX [${frame.length}B]: ${_hex(frame)}');
    await _ble.sendData(frame);

    // Python逻辑: 超时=跳转成功, 有响应=校验失败
    try {
      _pending = Completer<List<int>>();
      final resp = await _pending!.future
          .timeout(const Duration(seconds: 2));
      _pending = null;
      if (resp.isNotEmpty && resp[0] == 0xFF) {
        _log('⚠ Bootloader未跳转APP（校验和可能失败）');
      }
    } on TimeoutException {
      _pending = null;
      _log('✓ Bootloader已跳转APP（无回复=正常）');
    }
  }

  // ─────────────────────────── 升级流程 ───────────────────────────

  Future<void> upgradeFromFirmware(FirmwareData firmware) async {
    final totalBytes = firmware.segments.fold(0, (s, seg) => s + seg.size);
    int doneBytes = 0;

    _log('=== 开始升级: ${firmware.fileName} ===');
    _log('总字节数: $totalBytes，段数: ${firmware.segments.length}');

    // Step1: CONNECT（最多重试3次）
    _emit(0, totalBytes, 'connect', '连接Bootloader...');
    bool ok = false;
    for (int i = 0; i < 3; i++) {
      try {
        _rxBuf.clear();
        await connect();
        ok = true;
        break;
      } catch (e) {
        _log('CONNECT [${i+1}/3] 失败: $e');
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    if (!ok) throw Exception('无法连接Bootloader');

    // Step2: PROGRAM_START
    _emit(0, totalBytes, 'start', '进入编程模式...');
    await programStart();

    // Step3: 逐段处理
    for (int si = 0; si < firmware.segments.length; si++) {
      final seg = firmware.segments[si];
      _log('--- 段[${si+1}/${firmware.segments.length}]: $seg ---');

      // 擦除
      _emit(doneBytes, totalBytes, 'erase',
          '擦除 0x${seg.address.toRadixString(16).toUpperCase()}...');
      await setMta(seg.address);
      await programClear(seg.size);

      // 编程（擦除后MTA自动重置到段起始，但为稳妥再设一次）
      await setMta(seg.address);

      final maxData = _pgmMaxCto - 2; // [cmd][len][data...]
      int offset = 0;

      while (offset < seg.data.length) {
        final chunkSize =
            (seg.data.length - offset).clamp(1, maxData);
        final chunk = seg.data.sublist(offset, offset + chunkSize);

        await programChunk(chunk);
        offset    += chunkSize;
        doneBytes += chunkSize;

        _emit(doneBytes, totalBytes, 'program',
            '编程 ${(doneBytes / totalBytes * 100).toStringAsFixed(1)}%'
            '  ($doneBytes/$totalBytes B)');
      }

      // 段结束标记（对齐Python末尾的 PROGRAM 0x00 包）
      await programEmpty();
    }

    // Step4: 复位
    _emit(totalBytes, totalBytes, 'reset', '复位设备...');
    await programReset();

    _emit(totalBytes, totalBytes, 'done', '升级成功！');
    _log('=== 升级完成 ===');
  }

  // ─────────────────────────── 工具 ───────────────────────────────

  List<int> _u32(int v) => _littleEndian
      ? [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]
      : [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

  void _emit(int done, int total, String stage, String msg) {
    _progressCtrl.add(XcpProgress(
      currentBytes: done, totalBytes: total,
      stage: stage, message: msg,
      percent: total > 0 ? done / total : 0.0,
    ));
    _log('[进度] $msg');
  }

  void _log(String msg) => _logCtrl.add(msg);

  String _hex(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

  String _ascii(Uint8List b) => String.fromCharCodes(
      b.map((x) => (x >= 0x20 && x < 0x7F) ? x : 0x2E));

  void dispose() {
    _dataSub?.cancel();
    _progressCtrl.close();
    _logCtrl.close();
  }
}