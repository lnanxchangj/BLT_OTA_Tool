import 'package:flutter/material.dart';
import 'ble_test_screen.dart';
import 'ota_upgrade_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final _pages = const [BleTestScreen(), OtaUpgradeScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bluetooth),
            label: '蓝牙透传',
          ),
          NavigationDestination(
            icon: Icon(Icons.system_update),
            label: 'OTA 升级',
          ),
        ],
      ),
    );
  }
}