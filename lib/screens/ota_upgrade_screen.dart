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
  void dispose() {
    _logScrollCtrl.dispose();
    super.dispose();
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
          body: SafeArea(
            child: Column(
              children: [
                // ── 上半部分：卡片区，高度自适应，内容多时可滚动 ──
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.55,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 连接状态卡片
                        _ConnectionCard(ble: ble),
                        const SizedBox(height: 8),

                        // 固件文件卡片
                        _FirmwareCard(ota: ota),
                        const SizedBox(height: 8),

                        // 升级进度卡片（仅升级中/完成/失败时显示）
                        if (ota.state == OtaState.upgrading ||
                            ota.state == OtaState.success ||
                            ota.state == OtaState.failed) ...[
                          _ProgressCard(ota: ota),
                          const SizedBox(height: 8),
                        ],

                        // 升级按钮
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed:
                                ota.canUpgrade ? ota.startUpgrade : null,
                            icon: ota.state == OtaState.upgrading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.system_update),
                            label: Text(
                              ota.state == OtaState.upgrading
                                  ? '升级中...'
                                  : '开始升级',
                              style: const TextStyle(fontSize: 16),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: ota.state == OtaState.success
                                  ? Colors.green
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),

                // ── 下半部分：日志区，占满剩余空间 ──
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 日志标题栏
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
                              child: const Text(
                                '清空',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                        // 日志列表
                        Expanded(
                          child: ListView.builder(
                            controller: _logScrollCtrl,
                            itemCount: ota.logs.length,
                            itemBuilder: (ctx, i) {
                              final log = ota.logs[i];
                              final color = _logColor(log);
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

  Color _logColor(String log) {
    if (log.contains('→ TX')) return Colors.cyanAccent;
    if (log.contains('← ')) return Colors.greenAccent;
    if (log.contains('✗') ||
        log.contains('失败') ||
        log.contains('错误') ||
        log.contains('Error')) {
      return Colors.redAccent;
    }
    if (log.contains('✓') ||
        log.contains('成功') ||
        log.contains('===')) {
      return Colors.yellowAccent;
    }
    if (log.contains('⚠')) return Colors.orangeAccent;
    if (log.contains('[进度]')) return Colors.lightBlueAccent;
    return Colors.white70;
  }
}

// ═══════════════════════════════════════════════════════
//  子组件
// ═══════════════════════════════════════════════════════

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
        subtitle:
            Text(ble.statusMsg, style: const TextStyle(fontSize: 12)),
        trailing: ble.isConnected
            ? const Chip(
                label: Text(
                  '已连接',
                  style: TextStyle(color: Colors.white, fontSize: 11),
                ),
                backgroundColor: Colors.green,
              )
            : const Chip(
                label: Text(
                  '请先在蓝牙透传页连接',
                  style: TextStyle(fontSize: 11),
                ),
              ),
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
            // 标题行 + 选择按钮
            Row(
              children: [
                const Icon(Icons.memory, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '固件文件',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: ota.state != OtaState.upgrading
                      ? ota.pickFirmwareFile
                      : null,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('选择文件'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                  ),
                ),
              ],
            ),

            // 固件信息（解析成功后显示）
            if (ota.firmware != null) ...[
              const Divider(),
              _InfoRow('文件名', ota.firmware!.fileName),
              _InfoRow('类型', ota.firmware!.fileType.toUpperCase()),
              _InfoRow(
                '起始地址',
                '0x${ota.firmware!.startAddress.toRadixString(16).toUpperCase().padLeft(8, '0')}',
              ),
              _InfoRow(
                '结束地址',
                '0x${ota.firmware!.endAddress.toRadixString(16).toUpperCase().padLeft(8, '0')}',
              ),
              _InfoRow('大小', '${ota.firmware!.totalBytes} 字节'),
              _InfoRow('段数', '${ota.firmware!.segments.length}'),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                ota.statusMsg,
                style: TextStyle(
                  color:
                      Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
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
            width: 72,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 12, fontFamily: 'monospace'),
            ),
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
              Text(
                ota.progressMsg,
                style: const TextStyle(
                    color: Colors.grey, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}