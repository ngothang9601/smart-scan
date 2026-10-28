import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/document_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(
    ChangeNotifierProvider(
      create: (_) => DocumentStore()..load(),
      child: const SmartScanApp(),
    ),
  );
}

class SmartScanApp extends StatelessWidget {
  const SmartScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1A9E8F);
    return MaterialApp(
      title: 'Smart Scan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(
          colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}
