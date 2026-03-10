import '../models/firmware_data.dart';

class FirmwareParser {
  /// 根据文件扩展名自动选择解析器
  static FirmwareData parse(String fileName, String content) {
    final ext = fileName.split('.').last.toLowerCase();
    if (ext == 'hex') {
      return parseHex(fileName, content);
    } else if (['srec', 's19', 's28', 's37', 'mot', 's'].contains(ext)) {
      return parseSrec(fileName, content);
    }
    throw Exception('不支持的文件格式: $ext');
  }

  // ─────────────────────────── Intel HEX ───────────────────────────

  static FirmwareData parseHex(String fileName, String content) {
    final records = <FirmwareRecord>[];
    int extendedAddress = 0;
    int segmentBase = 0;

    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || !line.startsWith(':')) continue;

      final bytes = _hexToBytes(line.substring(1));
      if (bytes.length < 5) continue;

      final byteCount = bytes[0];
      final address = (bytes[1] << 8) | bytes[2];
      final recordType = bytes[3];

      // 验证校验和
      int checksum = 0;
      for (int i = 0; i < bytes.length - 1; i++) checksum += bytes[i];
      if (((~checksum + 1) & 0xFF) != bytes.last) continue;

      switch (recordType) {
        case 0x00: // Data record
          final fullAddress = extendedAddress + segmentBase + address;
          records.add(FirmwareRecord(
            address: fullAddress,
            data: bytes.sublist(4, 4 + byteCount),
          ));
          break;
        case 0x01: // End of File
          break;
        case 0x02: // Extended Segment Address (× 16)
          segmentBase = ((bytes[4] << 8) | bytes[5]) << 4;
          extendedAddress = 0;
          break;
        case 0x04: // Extended Linear Address (upper 16 bits)
          extendedAddress = ((bytes[4] << 8) | bytes[5]) << 16;
          segmentBase = 0;
          break;
      }
    }

    return _buildFirmwareData(fileName, 'hex', records);
  }

  // ─────────────────────────── Motorola SREC ───────────────────────────

  static FirmwareData parseSrec(String fileName, String content) {
    final records = <FirmwareRecord>[];

    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.length < 4 || line[0] != 'S') continue;

      final type = line[1];
      if (!['1', '2', '3'].contains(type)) continue;

      final bytes = _hexToBytes(line.substring(2));
      if (bytes.isEmpty) continue;

      final byteCount = bytes[0]; // 地址+数据+校验和的总字节数
      int addrLen;
      switch (type) {
        case '1':
          addrLen = 2;
          break;
        case '2':
          addrLen = 3;
          break;
        case '3':
          addrLen = 4;
          break;
        default:
          continue;
      }

      if (bytes.length < 1 + addrLen + 1) continue;

      // 解析地址
      int address = 0;
      for (int i = 0; i < addrLen; i++) {
        address = (address << 8) | bytes[1 + i];
      }

      // 数据范围：1(byteCount) + addrLen bytes address, last byte is checksum
      final dataStart = 1 + addrLen;
      final dataEnd = byteCount; // byteCount = addrLen + data_len + 1(checksum)
      if (dataEnd <= dataStart) continue;

      final data = bytes.sublist(dataStart, dataEnd);
      records.add(FirmwareRecord(address: address, data: data));
    }

    return _buildFirmwareData(fileName, 'srec', records);
  }

  // ─────────────────────────── 内部工具方法 ───────────────────────────

  static List<int> _hexToBytes(String hex) {
    final result = <int>[];
    for (int i = 0; i + 1 < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  static FirmwareData _buildFirmwareData(
    String fileName,
    String fileType,
    List<FirmwareRecord> records,
  ) {
    if (records.isEmpty) {
      return FirmwareData(
        fileName: fileName,
        fileType: fileType,
        records: [],
        segments: [],
        startAddress: 0,
        endAddress: 0,
        totalBytes: 0,
      );
    }

    // 按地址排序
    records.sort((a, b) => a.address.compareTo(b.address));

    final startAddr = records.first.address;
    final lastRecord = records.last;
    final endAddr = lastRecord.address + lastRecord.data.length;
    final totalBytes = records.fold(0, (s, r) => s + r.data.length);

    // 合并连续段（间隔 <= 256 字节时填 0xFF 合并）
    final segments = _mergeSegments(records);

    return FirmwareData(
      fileName: fileName,
      fileType: fileType,
      records: records,
      segments: segments,
      startAddress: startAddr,
      endAddress: endAddr,
      totalBytes: totalBytes,
    );
  }

  static List<FirmwareSegment> _mergeSegments(
    List<FirmwareRecord> records, {
    int maxGap = 256,
  }) {
    final segments = <FirmwareSegment>[];
    if (records.isEmpty) return segments;

    int curStart = records[0].address;
    final curData = List<int>.from(records[0].data);
    int curEnd = curStart + curData.length;

    for (int i = 1; i < records.length; i++) {
      final rec = records[i];
      if (rec.address - curEnd <= maxGap) {
        // 填充间隙
        for (int a = curEnd; a < rec.address; a++) curData.add(0xFF);
        curData.addAll(rec.data);
        curEnd = rec.address + rec.data.length;
      } else {
        segments.add(FirmwareSegment(address: curStart, data: List.from(curData)));
        curStart = rec.address;
        curData.clear();
        curData.addAll(rec.data);
        curEnd = curStart + curData.length;
      }
    }
    segments.add(FirmwareSegment(address: curStart, data: List.from(curData)));
    return segments;
  }
}