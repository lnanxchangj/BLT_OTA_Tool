import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/ble_provider.dart';
import '../providers/ota_provider.dart';

class OtaUpgradeScreen extends StatefulWidget {
  const OtaUpgradeScreen({super.key});

  @override
  State<OtaUpgradeScreen> createState() => _OtaUpgradeScreenState();
}

class _OtaUpgradeScreenState extends State<OtaUpgradeScreen> {
  final _logScrollCtrl = ScrollController();

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollCtrl.hasClients) {
        _logScrollCtrl.animateTo(
          _logScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<BleProvider, OtaProvider>(
      builder: (context, ble, ota, _) {
        _scrollToBottom();
        return Scaffold(
          appBar: AppBar(
            title: const Text('OTA 固件升级'),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          ),
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                // 蓝牙连接状态
                _ConnectionCard(ble: ble),
                const SizedBox(height: 12),

                // 固件信息卡
                _FirmwareCard(ota: ota),
                const SizedBox(height: 12),

                // 升级进度
                if (ota.state == OtaState.upgrading ||
                    ota.state == OtaState.success ||
                    ota.state == OtaState.failed)
                  _ProgressCard(ota: ota),

                if (ota.state == OtaState.upgrading ||
                    ota.state == OtaState.success ||
                    ota.state == OtaState.failed)
                  const SizedBox(height: 12),

                // 升级按钮
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: ota.canUpgrade ? ota.startUpgrade : null,
                    icon: ota.state == OtaState.upgrading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.system_update),
                    label: Text(
                      ota.state == OtaState.upgrading
                          ? '升级中...'
                          : '开始升级',
                      style: const TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          ota.state == OtaState.success
                              ? Colors.green
                              : null,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 日志区
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              '升级日志',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: ota.clearLogs,
                              child: const Text('清空',
                                  style: TextStyle(
                                      color: Colors.white54, fontSize: 11)),
                            ),
                          ],
                        ),
                        Expanded(
                          child: ListView.builder(
                            controller: _logScrollCtrl,
                            itemCount: ota.logs.length,
                            itemBuilder: (ctx, i) {
                              final log = ota.logs[i];
                              Color color = Colors.white70;
                              if (log.contains('TX:') || log.contains('→')) {
                                color = Colors.cyanAccent;
                              } else if (log.contains('RX:') ||
                                  log.contains('←')) {
                                color = Colors.greenAccent;
                              } else if (log.contains('错误') ||
                                  log.contains('失败') ||
                                  log.contains('error') ||
                                  log.contains('Error')) {
                                color = Colors.redAccent;
                              } else if (log.contains('===') ||
                                  log.contains('成功')) {
                                color = Colors.yellowAccent;
                              }
                              return Text(
                                log,
                                style: TextStyle(
                                  color: color,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _logScrollCtrl.dispose();
    super.dispose();
  }
}

// ─────────────────── 子卡片组件 ───────────────────

class _ConnectionCard extends StatelessWidget {
  final BleProvider ble;
  const _ConnectionCard({required this.ble});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          ble.isConnected
              ? Icons.bluetooth_connected
              : Icons.bluetooth_disabled,
          color: ble.isConnected ? Colors.green : Colors.grey,
        ),
        title: Text(ble.isConnected ? '已连接设备' : '未连接'),
        subtitle: Text(ble.statusMsg, style: const TextStyle(fontSize: 12)),
        trailing: ble.isConnected
            ? Chip(
                label: const Text('已连接',
                    style: TextStyle(color: Colors.white, fontSize: 11)),
                backgroundColor: Colors.green,
              )
            : const Chip(label: Text('请在蓝牙透传页面先连接设备',
                style: TextStyle(fontSize: 11))),
      ),
    );
  }
}

class _FirmwareCard extends StatelessWidget {
  final OtaProvider ota;
  const _FirmwareCard({required this.ota});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.memory, size: 20),
                const SizedBox(width: 8),
                const Text('固件文件',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: ota.state != OtaState.upgrading
                      ? ota.pickFirmwareFile
                      : null,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('选择文件'),
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6)),
                ),
              ],
            ),
            if (ota.firmware != null) ...[
              const Divider(),
              _InfoRow('文件名', ota.firmware!.fileName),
              _InfoRow('文件类型', ota.firmware!.fileType.toUpperCase()),
              _InfoRow(
                '起始地址',
                '0x${ota.firmware!.startAddress.toRadixString(16).toUpperCase().padLeft(8, '0')}',
              ),
              _InfoRow(
                '结束地址',
                '0x${ota.firmware!.endAddress.toRadixString(16).toUpperCase().padLeft(8, '0')}',
              ),
              _InfoRow('数据大小', '${ota.firmware!.totalBytes} 字节'),
              _InfoRow('内存段数', '${ota.firmware!.segments.length}'),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                ota.statusMsg,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(
                    color: Colors.grey, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final OtaProvider ota;
  const _ProgressCard({required this.ota});

  @override
  Widget build(BuildContext context) {
    final isSuccess = ota.state == OtaState.success;
    final isFailed = ota.state == OtaState.failed;

    return Card(
      color: isSuccess
          ? Colors.green.shade50
          : isFailed
              ? Colors.red.shade50
              : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSuccess
                      ? Icons.check_circle
                      : isFailed
                          ? Icons.error
                          : Icons.upload,
                  color: isSuccess
                      ? Colors.green
                      : isFailed
                          ? Colors.red
                          : Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ota.statusMsg,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  '${(ota.progress * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: ota.progress,
              backgroundColor: Colors.grey.shade200,
              color: isSuccess
                  ? Colors.green
                  : isFailed
                      ? Colors.red
                      : null,
            ),
            if (ota.progressMsg.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(ota.progressMsg,
                  style: const TextStyle(
                      color: Colors.grey, fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }
}