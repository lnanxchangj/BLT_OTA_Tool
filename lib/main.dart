import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/ble_provider.dart';
import 'providers/ota_provider.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BleProvider()),
        ChangeNotifierProxyProvider<BleProvider, OtaProvider>(
          create: (ctx) => OtaProvider(ctx.read<BleProvider>()),
          update: (ctx, ble, old) => old ?? OtaProvider(ble),
        ),
      ],
      child: MaterialApp(
        title: 'BLT OTA Tool',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}