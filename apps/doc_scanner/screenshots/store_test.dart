// Play Store screenshots. Run: flutter test screenshots/store_test.dart --update-goldens
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:doc_scanner/doc_store.dart';
import 'package:doc_scanner/main.dart';
import 'package:doc_scanner/review_screen.dart';
import 'package:doc_scanner/screens/text_screen.dart';
import 'package:doc_scanner/screens/viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
// ignore: implementation_imports
import 'package:printing/src/interface.dart';

import '../../../tool/screenshots/shot.dart';

// ---------------------------------------------------------------------------
// Sample documents, drawn with dart:ui so they look like real scans.

class Doc {
  const Doc(this.name, this.title, this.color, this.lines,
      {this.table = const [], this.ago = Duration.zero, this.pages = 1});
  final String name;
  final String title;
  final Color color;
  final List<String> lines;
  final List<List<String>> table;
  final Duration ago;
  final int pages;
}

final _now = DateTime(2026, 10, 7, 18, 30);

const _docs = [
  Doc('Electricity Bill - Sept 2026', 'ELECTRICITY BILL', Color(0xFF1565C0), [
    'Consumer No: 4521 8890 3312',
    'Billing period: 01 Sep 2026 - 30 Sep 2026',
    'Name: Rahul Verma',
    'Address: 14, Green Park Colony, Pune 411001',
  ], table: [
    ['Units consumed', '312 kWh'],
    ['Energy charges', 'Rs 2,184.00'],
    ['Fixed charges', 'Rs 120.00'],
    ['Taxes', 'Rs 276.48'],
    ['Amount due', 'Rs 2,580.48'],
  ], ago: Duration(hours: 2)),
  Doc('Rent Agreement 2026', 'RENTAL AGREEMENT', Color(0xFF37474F), [
    'This agreement is made on 1st October 2026 between the owner',
    'and the tenant for the flat at 302, Lake View Apartments.',
    '1. The monthly rent is Rs 18,000, payable before the 5th.',
    '2. The security deposit is Rs 54,000, refundable at the end.',
    '3. The term is eleven months from the date above.',
    '4. The tenant will pay electricity and water charges.',
    '5. Either party may end it with one month of notice.',
  ], ago: Duration(days: 1), pages: 4),
  Doc('Lecture Notes - Physics', 'Chapter 7: Laws of Motion', Color(0xFF2E7D32), [
    'Newton\'s first law: a body stays at rest or in uniform',
    'motion unless acted on by an external force.',
    'Second law: F = m x a. Force is the rate of change of momentum.',
    'Third law: every action has an equal and opposite reaction.',
    'Example: a 2 kg block pushed with 10 N accelerates at 5 m/s2.',
    'Friction opposes motion; static friction > kinetic friction.',
  ], ago: Duration(days: 2), pages: 12),
  Doc('Medical Report - Blood Test', 'LABORATORY REPORT', Color(0xFFC62828), [
    'Patient: Priya Sharma   Age: 32   Sample: 05 Oct 2026',
  ], table: [
    ['Haemoglobin', '13.2 g/dL'],
    ['WBC count', '7,400 /uL'],
    ['Platelets', '2.6 lakh /uL'],
    ['Fasting glucose', '92 mg/dL'],
    ['Vitamin D', '28 ng/mL'],
  ], ago: Duration(days: 4), pages: 2),
  Doc('Invoice INV-2048', 'TAX INVOICE', Color(0xFF6A1B9A), [
    'Invoice no: INV-2048   Date: 28 Sep 2026',
    'Bill to: Sunrise Traders, MG Road, Bengaluru',
  ], table: [
    ['Office chairs x 4', 'Rs 22,400'],
    ['Standing desk x 1', 'Rs 18,900'],
    ['Delivery', 'Rs 600'],
    ['GST 18%', 'Rs 7,560'],
    ['Total', 'Rs 49,460'],
  ], ago: Duration(days: 9)),
  Doc('Offer Letter', 'OFFER OF EMPLOYMENT', Color(0xFFEF6C00), [
    'Dear Ankit,',
    'We are pleased to offer you the position of Software Engineer',
    'at our Hyderabad office, starting 1st November 2026.',
    'Please sign and return a copy of this letter to confirm.',
  ], ago: Duration(days: 15), pages: 3),
  Doc('Insurance Policy', 'MOTOR INSURANCE POLICY', Color(0xFF00838F), [
    'Policy no: MI/2026/778812',
    'Vehicle: MH 12 AB 4567, Hatchback, Petrol',
    'Cover: 14 Oct 2026 to 13 Oct 2027',
  ], ago: Duration(days: 23), pages: 6),
];

ui.Paragraph _para(String text, double size, Color color, double width,
    {FontWeight weight = FontWeight.normal}) {
  final b = ui.ParagraphBuilder(ui.ParagraphStyle(fontFamily: 'Roboto'))
    ..pushStyle(ui.TextStyle(
        color: color, fontSize: size, fontWeight: weight, fontFamily: 'Roboto'))
    ..addText(text);
  return b.build()..layout(ui.ParagraphConstraints(width: width));
}

/// Paints page [page] of [d] filling [s] (A4 shaped).
void _paintPage(Canvas c, Size s, Doc d, int page, {bool photo = false}) {
  final u = s.width / 600; // layout unit
  c.drawRect(Offset.zero & s, Paint()..color = photo ? const Color(0xFFF3EFE6) : Colors.white);
  final ink = photo ? const Color(0xFF2B2B2B) : const Color(0xFF222222);
  final m = 44 * u;
  final w = s.width - 2 * m;
  var y = m;
  if (page == 0) {
    c.drawRect(Rect.fromLTWH(0, 0, s.width, 10 * u), Paint()..color = d.color);
    c.drawCircle(Offset(m + 18 * u, y + 20 * u), 18 * u, Paint()..color = d.color);
    c.drawParagraph(_para(d.title, 24 * u, d.color, w - 50 * u, weight: FontWeight.bold),
        Offset(m + 50 * u, y + 4 * u));
    y += 60 * u;
    c.drawLine(Offset(m, y), Offset(m + w, y),
        Paint()..color = d.color.withValues(alpha: .5)..strokeWidth = 1.5 * u);
    y += 18 * u;
    for (final l in d.lines) {
      final p = _para(l, 13 * u, ink, w);
      c.drawParagraph(p, Offset(m, y));
      y += p.height + 8 * u;
    }
    if (d.table.isNotEmpty) {
      y += 14 * u;
      for (var i = 0; i < d.table.length; i++) {
        final last = i == d.table.length - 1;
        final rh = 32 * u;
        if (last) {
          c.drawRect(Rect.fromLTWH(m, y, w, rh), Paint()..color = d.color.withValues(alpha: .12));
        } else if (i.isEven) {
          c.drawRect(Rect.fromLTWH(m, y, w, rh), Paint()..color = const Color(0x0A000000));
        }
        final wt = last ? FontWeight.bold : FontWeight.normal;
        c.drawParagraph(_para(d.table[i][0], 13 * u, ink, w / 2, weight: wt), Offset(m + 10 * u, y + 8 * u));
        final r = _para(d.table[i][1], 13 * u, ink, w / 2, weight: wt);
        c.drawParagraph(r, Offset(m + w - 10 * u - r.longestLine, y + 8 * u));
        y += rh;
      }
      y += 20 * u;
    }
  } else {
    y += 10 * u;
  }
  // Body text as grey lines, like small print seen from afar.
  final grey = Paint()..color = (photo ? const Color(0xFF9A968D) : const Color(0xFFBDBDBD));
  var k = page * 7;
  while (y < s.height - m - 40 * u) {
    for (var j = 0; j < 5 && y < s.height - m - 40 * u; j++) {
      final len = (j == 4) ? .55 : .85 + ((k * 37) % 15) / 100;
      c.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(m, y, w * len.clamp(0, 1), 6 * u), Radius.circular(3 * u)),
          grey);
      y += 16 * u;
      k++;
    }
    y += 14 * u;
  }
  if (page == 0 && d.table.isEmpty) {
    // Signature scrawl.
    final path = Path()..moveTo(m + w - 150 * u, s.height - m - 20 * u);
    for (var i = 0; i < 6; i++) {
      path.relativeQuadraticBezierTo(10 * u, -24 * u, 22 * u, 4 * u);
    }
    c.drawPath(path, Paint()..color = const Color(0xFF1A237E)..style = PaintingStyle.stroke..strokeWidth = 2 * u);
  }
}

Future<ui.Image> _pageImage(Doc d, int page, int w, int h, {bool photo = false}) async {
  final rec = ui.PictureRecorder();
  _paintPage(Canvas(rec), Size(w.toDouble(), h.toDouble()), d, page, photo: photo);
  return rec.endRecording().toImage(w, h);
}

Future<Uint8List> _png(ui.Image im) async =>
    (await im.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();

// ---------------------------------------------------------------------------
// Fakes for the platform side.

final _byLength = <int, Doc>{};

/// Renders our sample pages instead of the phone's PDF renderer.
class _FakePrinting extends PrintingPlatform {
  @override
  Future<PrintingInfo> info() async =>
      const PrintingInfo(canPrint: true, canShare: true, canRaster: true);

  @override
  Stream<PdfRaster> raster(Uint8List document, List<int>? pages, double dpi) async* {
    final d = _byLength[document.length] ?? _docs.first;
    final w = (PdfPageFormat.a4.width * dpi / 72).round();
    final h = (PdfPageFormat.a4.height * dpi / 72).round();
    for (final p in pages ?? List.generate(d.pages, (i) => i)) {
      final im = await _pageImage(d, p, w, h);
      final px = (await im.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
      yield PdfRaster(w, h, px);
    }
  }

  @override
  Future<bool> layoutPdf(_, __, ___, ____, _____, ______, _______, ________, _________) async => true;
  @override
  Future<List<Printer>> listPrinters() async => const [];
  @override
  Future<Printer?> pickPrinter(Rect bounds) async => null;
  @override
  Future<bool> sharePdf(_, __, ___, ____, _____, ______) async => true;
  @override
  Future<Uint8List> convertHtml(_, __, ___) async => Uint8List(0);
}

/// Like [shot], but repaints every render object (not just the root) so
/// widgets behind repaint boundaries get real shadows instead of the test
/// binding's thick debug outlines.
Future<void> _shot(WidgetTester tester, String name) async {
  debugDisableShadows = false;
  try {
    void visit(RenderObject o) {
      o.markNeedsPaint();
      o.visitChildren(visit);
    }
    visit(tester.binding.renderView);
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(MaterialApp).first,
        matchesGoldenFile('../store/screenshots/$name.png'));
  } finally {
    debugDisableShadows = true;
  }
}

late Directory _root;

Future<void> _setUpFiles() async {
  _root = Directory.systemTemp.createTempSync('doc_shots');
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => _root.path);
  m.setMockMethodCallHandler(const MethodChannel('in.onlysoftware.doc_scanner/system'),
      (_) async => null);
  PrintingPlatform.instance = _FakePrinting();
}

/// Writes the sample PDFs (real files, real sizes) with their dates.
Future<List<SavedDoc>> _writeDocs(WidgetTester tester) async {
  return (await tester.runAsync(() async {
    final dir = Directory('${_root.path}/pdfs')..createSync(recursive: true);
    for (final f in dir.listSync()) {
      f.deleteSync(recursive: true);
    }
    for (final d in _docs) {
      final images = <Uint8List>[];
      for (var p = 0; p < d.pages.clamp(1, 2); p++) {
        images.add(await _png(await _pageImage(d, p, 1240, 1754, photo: true)));
      }
      final pdf = await DocStore.buildPdf(images, PageSize.a4);
      final f = await DocStore.instance.savePdf(d.name, pdf);
      _byLength[pdf.length] = d;
      await f.setLastModified(_now.subtract(d.ago));
      await DocStore.instance.saveText(f, d.lines.join('\n'));
    }
    return DocStore.instance.list();
  }))!;
}

Future<void> _openApp(WidgetTester tester) async {
  usePhone(tester);
  await tester.pumpWidget(const DocScannerApp());
  await settleReal(tester, rounds: 30);
}

void main() {
  setUpAll(() async {
    await loadRealFonts();
    await _setUpFiles();
  });

  testWidgets('documents', (tester) async {
    await _writeDocs(tester);
    await _openApp(tester);
    await _shot(tester, '01_documents');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('review scan', (tester) async {
    usePhone(tester);
    final paths = (await tester.runAsync(() async {
      final out = <String>[];
      for (var p = 0; p < 3; p++) {
        final d = _docs[1];
        final f = File('${_root.path}/page_$p.png');
        await f.writeAsBytes(await _png(await _pageImage(d, p, 620, 877, photo: true)));
        out.add(f.path);
      }
      return out;
    }))!;
    await tester.pumpWidget(const DocScannerApp());
    await settleReal(tester, rounds: 5);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute(builder: (_) => ReviewScreen(pages: paths, title: 'Rent Agreement')));
    await settleReal(tester, rounds: 30);
    await _shot(tester, '02_review_scan');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('viewer', (tester) async {
    final docs = await _writeDocs(tester);
    await _openApp(tester);
    final d = docs.firstWhere((d) => d.name.startsWith('Electricity'));
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute(builder: (_) => ViewerScreen(doc: d)));
    await settleReal(tester, rounds: 40);
    await _shot(tester, '03_viewer');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tools', (tester) async {
    await _writeDocs(tester);
    await _openApp(tester);
    await tester.tap(find.text('Tools'));
    await settleReal(tester, rounds: 5);
    await _shot(tester, '04_pdf_tools');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('text', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(const DocScannerApp());
    await settleReal(tester, rounds: 5);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute(
        builder: (_) => TextScreen(name: 'Lecture Notes - Physics', pages: [
              'Chapter 7: Laws of Motion\n\n${_docs[2].lines.join('\n')}',
              'Momentum and impulse\n\nMomentum p = m x v is a vector quantity. '
                  'The impulse of a force equals the change in momentum it '
                  'produces: J = F x t = m(v - u).\n\nConservation of momentum: '
                  'when no external force acts on a system, its total momentum '
                  'stays constant. This explains the recoil of a gun and how '
                  'rockets move forward by pushing gases backward.',
            ])));
    await settleReal(tester, rounds: 5);
    await _shot(tester, '05_extracted_text');
    await tester.pumpWidget(const SizedBox());
  });
}
