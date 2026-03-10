import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/ble_provider.dart';
import 'providers/ota_provider.dart';
import 'providers/theme_provider.dart';
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
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => BleProvider()),
        ChangeNotifierProxyProvider<BleProvider, OtaProvider>(
          create: (ctx) => OtaProvider(ctx.read<BleProvider>()),
          update: (ctx, ble, old) => old ?? OtaProvider(ble),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, theme, _) => MaterialApp(
          title: 'BLT OTA Tool',
          debugShowCheckedModeBanner: false,
          themeMode: theme.themeMode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
            cardTheme: const CardThemeData(elevation: 2), // ¡û CardThemeData
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
            cardTheme: const CardThemeData(elevation: 2), // ¡û CardThemeData
          ),
          home: const HomeScreen(),
        ),
      ),
    );
  }
}