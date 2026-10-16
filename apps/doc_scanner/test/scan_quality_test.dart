import 'dart:typed_data';

import 'package:doc_scanner/doc_store.dart';
import 'package:doc_scanner/image_filters.dart';
import 'package:doc_scanner/jobs.dart';
import 'package:doc_scanner/review_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

img.Image gray(int w, int h, int v) =>
    img.fill(img.Image(width: w, height: h), color: img.ColorRgb8(v, v, v));

/// Light paper with a faint pencil stroke across the middle.
img.Image faintPage() {
  final im = gray(80, 60, 225);
  for (var x = 10; x < 70; x++) {
    for (var y = 28; y < 32; y++) {
      im.setPixelRgb(x, y, 170, 170, 170);
    }
  }
  return im;
}

void main() {
  group('Light text', () {
    test('darkens faint strokes and keeps paper white', () {
      final out = applyFilter(faintPage(), PageFilter.lightText);
      expect(out.getPixel(40, 30).r, lessThan(120));
      expect(out.getPixel(40, 5).r, 255);
    });
    test('is gray', () {
      final out = applyFilter(faintPage(), PageFilter.lightText);
      for (final p in out) {
        expect(p.r, p.g);
        expect(p.g, p.b);
      }
    });
  });

  group('brightness and contrast', () {
    for (final b in [-60, -20, 20, 60]) {
      test('brightness $b moves mid-gray the same way', () {
        final out = adjustPage(gray(4, 4, 128), b, 0);
        expect((out.getPixel(1, 1).r - 128).sign, b.sign);
      });
    }
    test('more contrast pulls dark and light apart', () {
      final im = img.Image(width: 2, height: 1)
        ..setPixelRgb(0, 0, 90, 90, 90)
        ..setPixelRgb(1, 0, 170, 170, 170);
      final out = adjustPage(im, 0, 50);
      expect(out.getPixel(0, 0).r, lessThan(90));
      expect(out.getPixel(1, 0).r, greaterThan(170));
    });
    test('less contrast pulls them together', () {
      final im = img.Image(width: 2, height: 1)
        ..setPixelRgb(0, 0, 40, 40, 40)
        ..setPixelRgb(1, 0, 220, 220, 220);
      final out = adjustPage(im, 0, -50);
      expect(out.getPixel(0, 0).r, greaterThan(40));
      expect(out.getPixel(1, 0).r, lessThan(220));
    });
    test('does not change the source image', () {
      final im = gray(3, 3, 100);
      adjustPage(im, 50, 50);
      expect(im.getPixel(1, 1).r, 100);
    });
    test('renderJob applies the sliders', () {
      final src = Uint8List.fromList(img.encodePng(gray(20, 20, 128)));
      final plain = img.decodeJpg(renderJob((src, PageFilter.original, 0, 3000, 95, 0, 0)))!;
      final bright = img.decodeJpg(renderJob((src, PageFilter.original, 0, 3000, 95, 50, 0)))!;
      expect(bright.getPixel(10, 10).r, greaterThan(plain.getPixel(10, 10).r + 40));
    });
  });

  test('filter previews: one small JPEG per filter', () {
    final photo = Uint8List.fromList(img.encodeJpg(gray(1200, 1600, 200)));
    final previews = filterPreviewsJob(photo);
    expect(previews.length, PageFilter.values.length);
    for (final p in previews) {
      final im = img.decodeJpg(p)!;
      expect(im.height, 220);
      expect(im.width, 165);
    }
  });

  test('downscaling averages pixels (fine stripes become gray, not jagged)', () {
    final im = img.Image(width: 400, height: 10);
    for (final p in im) {
      final v = p.x.isEven ? 0 : 255;
      p
        ..r = v
        ..g = v
        ..b = v;
    }
    final out = fitWithin(im, 200);
    expect(out.width, 200);
    expect(out.getPixel(50, 2).r, inInclusiveRange(100, 155));
  });

  group('PDF pages', () {
    Future<sf.PdfDocument> build(int w, int h, PageSize size) async {
      final page = Uint8List.fromList(img.encodeJpg(gray(w, h, 210)));
      return sf.PdfDocument(inputBytes: await DocStore.buildPdf([page], size));
    }

    for (final size in [PageSize.a4, PageSize.letter]) {
      test('${size.label}: a wide photo gets a sideways page', () async {
        final d = await build(400, 300, size);
        final s = d.pages[0].size;
        expect(s.width, greaterThan(s.height));
        d.dispose();
      });
      test('${size.label}: a tall photo stays upright', () async {
        final d = await build(300, 400, size);
        final s = d.pages[0].size;
        expect(s.height, greaterThan(s.width));
        d.dispose();
      });
    }
  });

  test('Apply to all copies the look but not the rotation', () {
    final a = ScanPage('/a.jpg')
      ..filter = PageFilter.lightText
      ..brightness = 20
      ..contrast = -10
      ..turns = 1;
    final b = ScanPage('/b.jpg')..copyLook(a);
    expect([b.filter, b.brightness, b.contrast, b.turns], [PageFilter.lightText, 20, -10, 0]);
  });
}
