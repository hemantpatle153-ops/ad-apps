import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import 'screens/home_shell.dart';

const appPackageName = 'in.onlysoftware.qr_scanner';
const privacyPolicyUrl = 'https://example.com/privacy'; // TODO: your hosted policy

class QrScannerApp extends StatelessWidget {
  const QrScannerApp({super.key});

  static const _seed = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QR & Barcode Scanner',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(_seed, Brightness.light),
      darkTheme: buildTheme(_seed, Brightness.dark),
      home: const HomeShell(),
    );
  }
}
