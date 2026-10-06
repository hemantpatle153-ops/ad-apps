import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:doc_scanner/doc_store.dart';
import 'package:doc_scanner/pdf_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// A PDF whose page i says "Page i+1" (real text, so it can be extracted).
Uint8List textPdf(int pages, {Size size = const Size(595, 842)}) {
  final d = PdfDocument();
  d.pageSettings
    ..margins.all = 0
    ..orientation = size.width > size.height
        ? PdfPageOrientation.landscape
        : PdfPageOrientation.portrait
    ..size = size;
  for (var i = 0; i < pages; i++) {
    d.pages.add().graphics.drawString(
        'Page ${i + 1}', PdfStandardFont(PdfFontFamily.helvetica, 24),
        bounds: const Rect.fromLTWH(40, 40, 300, 40));
  }
  final out = Uint8List.fromList(d.saveSync());
  d.dispose();
  return out;
}

List<String> texts(Uint8List pdf) =>
    PdfTools.pageTexts(pdf).map((t) => t.trim()).toList();

void main() {
  final dump = Platform.environment['PDF_DUMP'];
  void save(String name, Uint8List b) {
    if (dump != null) File('$dump/$name.pdf').writeAsBytesSync(b);
  }

  test('merge keeps every page in order', () {
    final out = PdfTools.merge([textPdf(2), textPdf(3)]);
    save('merge', out);
    expect(texts(out), ['Page 1', 'Page 2', 'Page 1', 'Page 2', 'Page 3']);
  });

  test('organize reorders, drops and duplicates pages', () {
    final out = PdfTools.organize(textPdf(3),
        const [PageRef(2), PageRef(0), PageRef(0, 1)]);
    save('organize', out);
    expect(texts(out), ['Page 3', 'Page 1', 'Page 1']);
    // The turned copy is landscape now.
    final s = PdfTools.pageSize(out, 2);
    expect(s.width, greaterThan(s.height));
  });

  test('organize refuses an empty result', () {
    expect(() => PdfTools.organize(textPdf(1), const []), throwsArgumentError);
  });

  test('split makes one file per group', () {
    final parts = PdfTools.split(textPdf(5), [
      [0, 1],
      [4],
    ]);
    expect(parts.map(texts), [
      ['Page 1', 'Page 2'],
      ['Page 5'],
    ]);
  });

  test('removePages drops the chosen pages', () {
    expect(texts(PdfTools.removePages(textPdf(4), {1, 3})),
        ['Page 1', 'Page 3']);
  });

  test('rotate swaps page orientation and keeps text', () {
    final out = PdfTools.rotate(textPdf(2), 1, pages: {0});
    save('rotate', out);
    expect(PdfTools.pageSize(out, 0).width, 842);
    expect(PdfTools.pageSize(out, 1).width, 595);
    expect(texts(out), ['Page 1', 'Page 2']);
  });

  test('crop shrinks pages', () {
    final out = PdfTools.crop(textPdf(1), left: 0.1, right: 0.1, top: 0.2);
    save('crop', out);
    final s = PdfTools.pageSize(out, 0);
    expect(s.width, closeTo(595 * 0.8, 1));
    expect(s.height, closeTo(842 * 0.8, 1));
  });

  test('watermark and page numbers add text', () {
    var out = PdfTools.watermark(textPdf(2), 'CONFIDENTIAL');
    out = PdfTools.addPageNumbers(out, pattern: 'Page {n} of {total}');
    save('stamped', out);
    final t = PdfTools.pageTexts(out);
    expect(t[0], contains('CONFIDENTIAL'));
    expect(t[1], contains('Page 2 of 2'));
  });

  test('page labels fill in the pattern', () {
    expect(PdfTools.pageLabel(3, 9, '{n} / {total}'), '3 / 9');
  });

  test('protect needs the password and unlock removes it', () {
    final locked = PdfTools.protect(textPdf(2), 'secret');
    expect(PdfTools.isEncrypted(locked), isTrue);
    expect(() => PdfTools.unlock(locked, 'wrong'),
        throwsA(isA<PasswordRequired>()));
    final open = PdfTools.unlock(locked, 'secret');
    expect(PdfTools.isEncrypted(open), isFalse);
    expect(texts(open), ['Page 1', 'Page 2']);
  });

  test('protect rejects an empty password', () {
    expect(() => PdfTools.protect(textPdf(1), ''), throwsArgumentError);
  });

  test('stamp image, add text and cover boxes keep the page count', () {
    final png = Uint8List.fromList(
        img.encodePng(img.fill(img.Image(width: 40, height: 20), color: img.ColorRgb8(0, 0, 255))));
    var out = PdfTools.stampImage(textPdf(2), png,
        page: 1, box: const Rect.fromLTWH(0.6, 0.8, 0.3, 0.1));
    out = PdfTools.addText(out, 'Approved', page: 0, at: const Offset(0.5, 0.5));
    out = PdfTools.coverBoxes(out,
        page: 0, boxes: [const Rect.fromLTWH(0, 0, 0.5, 0.1)]);
    save('stamp', out);
    expect(PdfTools.pageCount(out), 2);
    expect(PdfTools.pageTexts(out)[0], contains('Approved'));
  });

  test('stamping a rotated page lands in the shown position', () {
    final rotated = PdfTools.open(textPdf(1));
    rotated.pages[0].rotation = PdfPageRotateAngle.rotateAngle90;
    final bytes = Uint8List.fromList(rotated.saveSync());
    rotated.dispose();
    final out = PdfTools.addText(bytes, 'Here', page: 0, at: const Offset(0.1, 0.1));
    save('rotated_stamp', out);
    // Baked: the page is now landscape with no /Rotate.
    final d = PdfTools.open(out);
    expect(d.pages[0].rotation, PdfPageRotateAngle.rotateAngle0);
    expect(d.pages[0].size.width, 842);
    d.dispose();
  });

  test('optimize keeps content', () {
    expect(texts(PdfTools.optimize(textPdf(3))), ['Page 1', 'Page 2', 'Page 3']);
  });

  test('replaceWithImages swaps chosen pages for images', () {
    final jpg = Uint8List.fromList(img.encodeJpg(img.Image(width: 60, height: 80)));
    final out = PdfTools.replaceWithImages(textPdf(2), {0: jpg});
    expect(texts(out), ['', 'Page 2']);
  });

  test('buildPdf adds a hidden, searchable text layer', () async {
    final jpg = Uint8List.fromList(img.encodeJpg(img.Image(width: 600, height: 800)));
    final out = await DocStore.buildPdf([jpg], PageSize.a4, text: [
      const PageText(600, 800, [
        OcrLine('Invoice 2041', Rect.fromLTWH(50, 60, 300, 40)),
        OcrLine('Total ₹ 950', Rect.fromLTWH(50, 700, 200, 30)),
      ]),
    ]);
    save('ocr', out);
    // The extractor may break lines between words; compare word by word.
    final t = PdfTools.pageTexts(out).first.split(RegExp(r'\s+')).join(' ');
    expect(t, contains('Invoice 2041'));
    expect(t, contains('Total ? 950'));
  });

  test('ID card puts both sides on one page', () async {
    final jpg = Uint8List.fromList(img.encodeJpg(img.Image(width: 856, height: 540)));
    final out = await DocStore.buildIdCardPdf(jpg, jpg);
    save('idcard', out);
    expect(PdfTools.pageCount(out), 1);
  });
}
