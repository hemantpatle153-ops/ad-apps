import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import 'screens/home_shell.dart';

const appPackageName = 'in.onlysoftware.qr_scanner';
// Rahul's published Google Doc (same text as website/build.py's page).
const privacyPolicyUrl =
    'https://docs.google.com/document/d/e/2PACX-1vQGUBqDjMOdmypiIrwgkwVXqCxpWgUuzt2sZvb6d8q1wgYsZyEMOV9MjD-9EARk3qEnIRMDwrn79iMi/pub';

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
