import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import 'ble_test_screen.dart';
import 'ota_upgrade_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _pageIndex = 0; // 0=蓝牙透传, 1=OTA升级

  final _pages = const [BleTestScreen(), OtaUpgradeScreen()];

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: _pages[_pageIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _pageIndex,
        onDestinationSelected: (i) {
          if (i == 2) {
            // 第三项是主题切换按钮，不切换页面
            themeProvider.toggle();
          } else {
            setState(() => _pageIndex = i);
          }
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.bluetooth_outlined),
            selectedIcon: Icon(Icons.bluetooth_connected),
            label: '蓝牙透传',
          ),
          const NavigationDestination(
            icon: Icon(Icons.system_update_outlined),
            selectedIcon: Icon(Icons.system_update),
            label: 'OTA 升级',
          ),
          NavigationDestination(
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            ),
            label: isDark ? '浅色模式' : '深色模式',
          ),
        ],
      ),
    );
  }
}