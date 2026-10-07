// Play Store screenshots. Run: flutter test screenshots/store_test.dart --update-goldens
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner/src/app.dart';
import 'package:qr_scanner/src/screens/result_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../tool/screenshots/shot.dart';

final _now = DateTime(2026, 10, 7, 18, 30);

String _entry(String v, Duration ago) =>
    jsonEncode({'v': v, 't': _now.subtract(ago).millisecondsSinceEpoch});

final _history = [
  _entry('https://www.zomato.com/bangalore/cafe-coffee-day-menu', const Duration(minutes: 5)),
  _entry('upi://pay?pa=sharmastores@okaxis&pn=Sharma%20General%20Stores', const Duration(hours: 3)),
  _entry('WIFI:S:Cafe_Guest_5G;T:WPA;P:welcome2026;;', const Duration(days: 1)),
  _entry('8901030865278', const Duration(days: 1, hours: 4)),
  _entry('tel:+919876543210', const Duration(days: 2)),
  _entry('mailto:support@flipkart.com', const Duration(days: 3)),
  _entry('https://maps.app.goo.gl/rT8xQ2kLmN4vP9wZ7', const Duration(days: 4)),
  _entry('Table 12 - Order online and skip the queue!', const Duration(days: 6)),
  _entry('9780143442295', const Duration(days: 9)),
  _entry('https://youtube.com/@cookingwithpriya', const Duration(days: 12)),
];

void _mockScanner() {
  // The camera plugin has no platform side in tests; answer quietly.
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in [
    'dev.steenbakker.mobile_scanner/scanner/method',
    'dev.steenbakker.mobile_scanner/scanner/event',
    'dev.steenbakker.mobile_scanner/scanner/deviceOrientation',
  ]) {
    m.setMockMethodCallHandler(MethodChannel(name), (_) async => null);
  }
}

Future<void> _openApp(WidgetTester tester) async {
  usePhone(tester);
  SharedPreferences.setMockInitialValues({'scan_history': _history});
  _mockScanner();
  await tester.pumpWidget(const QrScannerApp());
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUpAll(loadRealFonts);

  testWidgets('history', (tester) async {
    await _openApp(tester);
    await tester.tap(find.text('History'));
    await settleReal(tester, rounds: 5);
    await shot(tester, '01_history');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('create', (tester) async {
    await _openApp(tester);
    await tester.tap(find.text('Create'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byType(TextField), 'https://onlysoftware.in');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 500));
    await shot(tester, '02_create_qr');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('result link', (tester) async {
    await _openApp(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute(builder: (_) => const ResultScreen(
        value: 'https://www.zomato.com/bangalore/cafe-coffee-day-menu')));
    await tester.pumpAndSettle();
    await shot(tester, '03_result_link');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('result upi', (tester) async {
    await _openApp(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute(builder: (_) => const ResultScreen(
        value: 'upi://pay?pa=sharmastores@okaxis&pn=Sharma%20General%20Stores')));
    await tester.pumpAndSettle();
    await shot(tester, '04_result_upi');
    await tester.pumpWidget(const SizedBox());
  });
}
