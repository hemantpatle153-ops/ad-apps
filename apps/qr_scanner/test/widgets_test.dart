import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:qr_scanner/src/history_store.dart';
import 'package:qr_scanner/src/scan_kind.dart';
import 'package:qr_scanner/src/screens/create_screen.dart';
import 'package:qr_scanner/src/screens/history_screen.dart';
import 'package:qr_scanner/src/screens/result_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// Raw pixels of the single QR code currently on screen.
Future<List<int>> _qrPixels(WidgetTester tester) async {
  final paint = tester.widget<CustomPaint>(find.descendant(
      of: find.byType(QrImageView), matching: find.byType(CustomPaint)));
  final painter = paint.painter! as QrPainter;
  final data = await tester.runAsync(() => painter.toImageData(120));
  return data!.buffer.asUint8List();
}

void main() {
  group('ResultScreen', () {
    const cases = {
      'https://example.com/menu': 'Open',
      'upi://pay?pa=shop@ybl&pn=Shop': 'Pay with UPI app',
      'tel:+911234567890': 'Call',
      'mailto:me@example.com': 'Send email',
      '8901030865278': 'Search product',
      'WIFI:S:Home;T:WPA;P:pw;;': null,
      'just some text': null,
    };
    for (final c in cases.entries) {
      testWidgets('"${c.key}" shows its kind and the right action',
          (tester) async {
        await tester.pumpWidget(MaterialApp(home: ResultScreen(value: c.key)));
        final kind = ScanKind.of(c.key);
        // Label appears in the app bar and next to the icon.
        expect(find.text(kind.label), findsNWidgets(2));
        expect(find.byIcon(kind.icon), findsOneWidget);
        expect(find.text(c.key), findsOneWidget);
        if (c.value == null) {
          expect(find.byType(FilledButton), findsNothing);
        } else {
          expect(find.widgetWithText(FilledButton, c.value!), findsOneWidget);
        }
        expect(find.text('Copy'), findsOneWidget);
        expect(find.text('Share'), findsOneWidget);
      });
    }

    testWidgets('Copy puts the value on the clipboard and confirms',
        (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(
          const MaterialApp(home: ResultScreen(value: 'copy me')));
      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(copied, 'copy me');
      expect(find.text('Copied'), findsOneWidget);
    });
  });

  group('CreateScreen', () {
    testWidgets('shows no QR code until text is entered', (tester) async {
      await tester.pumpWidget(_wrap(const CreateScreen()));
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('Text, link or phone number'), findsOneWidget);
    });

    const inputs = {
      'hello': 'hello',
      '  https://example.com  ': 'https://example.com',
      '\n8901030865278\n': '8901030865278',
    };
    for (final i in inputs.entries) {
      testWidgets('encodes trimmed "${i.value}"', (tester) async {
        await tester.pumpWidget(_wrap(const CreateScreen()));
        await tester.enterText(find.byType(TextField), i.key);
        await tester.pump();
        expect(find.byType(QrImageView), findsOneWidget);
        final shown = await _qrPixels(tester);
        // Render a reference code for the expected (trimmed) data.
        await tester.pumpWidget(_wrap(Center(
            child: QrImageView(data: i.value, size: 240))));
        final reference = await _qrPixels(tester);
        expect(shown, reference);
      });
    }

    testWidgets('whitespace-only input shows no QR code', (tester) async {
      await tester.pumpWidget(_wrap(const CreateScreen()));
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();
      expect(find.byType(QrImageView), findsOneWidget);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(find.byType(QrImageView), findsNothing);
    });
  });

  group('HistoryScreen', () {
    setUpAll(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('shows a hint when empty', (tester) async {
      await tester.pumpWidget(_wrap(const HistoryScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Scanned codes will show up here.'), findsOneWidget);
    });

    testWidgets('lists entries newest first with kind icons', (tester) async {
      await HistoryStore.instance.clear();
      await HistoryStore.instance.add('hello');
      await HistoryStore.instance.add('https://example.com');
      await tester.pumpWidget(_wrap(const HistoryScreen()));
      await tester.pumpAndSettle();
      final titles = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((t) => (t.title as Text).data)
          .toList();
      expect(titles, ['https://example.com', 'hello']);
      expect(find.byIcon(Icons.link), findsOneWidget);
      expect(find.byIcon(Icons.notes), findsOneWidget);
    });

    testWidgets('tapping an entry opens its result', (tester) async {
      await HistoryStore.instance.clear();
      await HistoryStore.instance.add('tel:12345');
      await tester.pumpWidget(_wrap(const HistoryScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('tel:12345'));
      await tester.pumpAndSettle();
      expect(find.byType(ResultScreen), findsOneWidget);
      expect(find.text('Call'), findsOneWidget);
    });

    testWidgets('swiping an entry away removes it from history',
        (tester) async {
      await HistoryStore.instance.clear();
      await HistoryStore.instance.add('keep');
      await HistoryStore.instance.add('drop');
      await tester.pumpWidget(_wrap(const HistoryScreen()));
      await tester.pumpAndSettle();
      await tester.drag(find.text('drop'), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('drop'), findsNothing);
      expect(HistoryStore.instance.entries.map((e) => e.value), ['keep']);
    });
  });
}
