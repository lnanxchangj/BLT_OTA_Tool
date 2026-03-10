import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import '../providers/ble_provider.dart';
import '../services/ble_service.dart';

class BleTestScreen extends StatefulWidget {
  const BleTestScreen({super.key});

  @override
  State<BleTestScreen> createState() => _BleTestScreenState();
}

class _BleTestScreenState extends State<BleTestScreen> {
  final _hexController = TextEditingController();
  final _textController = TextEditingController();
  final _logScrollCtrl = ScrollController();
  BleUartConfig _selectedConfig = BleUartConfig.nordicUart;

  @override
  void dispose() {
    _hexController.dispose();
    _textController.dispose();
    _logScrollCtrl.dispose();
    super.dispose();
  }

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
    return Consumer<BleProvider>(
      builder: (context, ble, _) {
        _scrollToBottom();
        return Scaffold(
          appBar: AppBar(
            title: const Text('蓝牙透传测试'),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            actions: [
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () => _showConfigDialog(context, ble),
                tooltip: 'UUID 配置',
              ),
            ],
          ),
          body: Column(
            children: [
              // 状态栏
              _StatusBar(ble: ble),

              // 扫描结果
              if (!ble.isConnected) _ScanPanel(ble: ble),

              // 收发日志
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(8),
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
                          const Text('收发日志',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                          const Spacer(),
                          TextButton(
                            onPressed: ble.clearLogs,
                            child: const Text('清空',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 11)),
                          ),
                        ],
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: _logScrollCtrl,
                          itemCount: ble.txLogs.length,
                          itemBuilder: (ctx, i) {
                            final log = ble.txLogs[i];
                            final isRx = log.contains('← RX');
                            return Text(
                              log,
                              style: TextStyle(
                                color:
                                    isRx ? Colors.greenAccent : Colors.cyan,
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

              // 发送区（仅连接后显示）
              if (ble.isConnected) _SendPanel(ble: ble),
            ],
          ),
        );
      },
    );
  }

  void _showConfigDialog(BuildContext context, BleProvider ble) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('蓝牙模组 UUID 配置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: BleUartConfig.presets.map((config) {
            return RadioListTile<BleUartConfig>(
              title: Text(config.name),
              subtitle: Text(config.serviceUuid, style: const TextStyle(fontSize: 10)),
              value: config,
              groupValue: _selectedConfig,
              onChanged: (v) {
                if (v != null) {
                  setState(() => _selectedConfig = v);
                  ble.setUartConfig(v);
                  Navigator.pop(ctx);
                }
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
        ],
      ),
    );
  }
}

// ─────────────────── 子组件 ───────────────────

class _StatusBar extends StatelessWidget {
  final BleProvider ble;
  const _StatusBar({required this.ble});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: ble.isConnected ? Colors.green.shade700 : Colors.grey.shade700,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            ble.isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ble.statusMsg,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          if (ble.isConnected)
            TextButton(
              onPressed: ble.disconnectDevice,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('断开'),
            ),
        ],
      ),
    );
  }
}

class _ScanPanel extends StatelessWidget {
  final BleProvider ble;
  const _ScanPanel({required this.ble});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: ble.isScanning ? ble.stopScan : ble.startScan,
                  icon: ble.isScanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: Text(ble.isScanning ? '停止扫描' : '扫描设备'),
                ),
              ),
            ],
          ),
        ),
        if (ble.scanResults.isNotEmpty)
          SizedBox(
            height: 160,
            child: ListView.builder(
              itemCount: ble.scanResults.length,
              itemBuilder: (ctx, i) {
                final r = ble.scanResults[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.bluetooth, size: 20),
                  title: Text(r.device.platformName,
                      style: const TextStyle(fontSize: 14)),
                  subtitle: Text(r.device.remoteId.toString(),
                      style: const TextStyle(fontSize: 11)),
                  trailing: Text('${r.rssi} dBm',
                      style: const TextStyle(fontSize: 11)),
                  onTap: () => ble.connectDevice(r.device),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _SendPanel extends StatefulWidget {
  final BleProvider ble;
  const _SendPanel({required this.ble});

  @override
  State<_SendPanel> createState() => _SendPanelState();
}

class _SendPanelState extends State<_SendPanel> {
  final _hexCtrl = TextEditingController();
  final _textCtrl = TextEditingController();
  bool _sendAsHex = true;

  @override
  void dispose() {
    _hexCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ChoiceChip(
                label: const Text('HEX'),
                selected: _sendAsHex,
                onSelected: (v) => setState(() => _sendAsHex = true),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('文本'),
                selected: !_sendAsHex,
                onSelected: (v) => setState(() => _sendAsHex = false),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _sendAsHex ? _hexCtrl : _textCtrl,
                  decoration: InputDecoration(
                    hintText: _sendAsHex
                        ? 'FF 01 02 03 (空格分隔)'
                        : '输入文本内容',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  if (_sendAsHex) {
                    widget.ble.sendHex(_hexCtrl.text);
                  } else {
                    widget.ble.sendText(_textCtrl.text);
                  }
                },
                child: const Text('发送'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}