/// 固件原始记录（一行HEX/SREC解析后的结果）
class FirmwareRecord {
  final int address;
  final List<int> data;
  const FirmwareRecord({required this.address, required this.data});
}

/// 合并后的连续内存段
class FirmwareSegment {
  final int address;
  final List<int> data;

  const FirmwareSegment({required this.address, required this.data});

  int get size => data.length;
  int get endAddress => address + data.length;

  @override
  String toString() =>
      '0x${address.toRadixString(16).toUpperCase().padLeft(8, '0')}'
      ' - 0x${endAddress.toRadixString(16).toUpperCase().padLeft(8, '0')}'
      ' (${size} bytes)';
}

/// 固件完整数据
class FirmwareData {
  final String fileName;
  final String fileType; // 'hex' or 'srec'
  final List<FirmwareRecord> records;
  final List<FirmwareSegment> segments;
  final int startAddress;
  final int endAddress;
  final int totalBytes;

  const FirmwareData({
    required this.fileName,
    required this.fileType,
    required this.records,
    required this.segments,
    required this.startAddress,
    required this.endAddress,
    required this.totalBytes,
  });
}