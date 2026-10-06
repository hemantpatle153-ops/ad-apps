import 'dart:typed_data';

import 'package:doc_scanner/scan/capture.dart';
import 'package:doc_scanner/scan/geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'scan_detect_test.dart' show scene;

void main() {
  const page = Quad(P(0.2, 0.15), P(0.8, 0.18), P(0.85, 0.85), P(0.15, 0.82));
  final photo = Uint8List.fromList(img.encodeJpg(scene(page, shadow: false), quality: 95));

  test('a shot with a page is found and flattened', () {
    final r = processCapture((photo, null, true));
    expect(r.found, isTrue);
    expect(r.quad.maxShift(page), lessThan(0.03));
    final out = img.decodeJpg(r.jpeg)!;
    expect(out.height, greaterThan(out.width));
    expect(out.getPixel(4, 4).r, greaterThan(170));
  });

  test('photo mode keeps the whole picture', () {
    final r = processCapture((photo, null, false));
    expect(r.found, isFalse);
    expect(r.quad, Quad.full);
    final out = img.decodeJpg(r.jpeg)!;
    expect([out.width, out.height], [480, 640]);
  });

  test('with no page the live outline is used', () {
    final blank = Uint8List.fromList(img.encodeJpg(
        img.fill(img.Image(width: 300, height: 400), color: img.ColorRgb8(90, 90, 90))));
    const hint = Quad(P(0.1, 0.1), P(0.9, 0.1), P(0.9, 0.9), P(0.1, 0.9));
    final r = processCapture((blank, hint, true));
    expect(r.found, isFalse);
    expect(r.quad, hint);
    final out = img.decodeJpg(r.jpeg)!;
    expect(out.width, closeTo(240, 2));
  });

  test('with no page and no outline the whole photo is kept', () {
    final blank = Uint8List.fromList(img.encodeJpg(
        img.fill(img.Image(width: 300, height: 400), color: img.ColorRgb8(90, 90, 90))));
    final r = processCapture((blank, null, true));
    expect(r.quad, Quad.full);
    expect(img.decodeJpg(r.jpeg)!.width, 300);
  });

  test('big photos are limited to 2600 px', () {
    final big = Uint8List.fromList(img.encodeJpg(img.Image(width: 4000, height: 3000)));
    final out = img.decodeJpg(processCapture((big, null, false)).jpeg)!;
    expect(out.width, 2600);
  });

  test('recrop uses the given corners', () {
    final out = img.decodeJpg(recropJob((photo, page)))!;
    expect(out.height, greaterThan(out.width));
  });

  test('detectPhotoJob finds the page', () {
    expect(detectPhotoJob(photo)!.maxShift(page), lessThan(0.03));
  });

  test('not an image is rejected', () {
    expect(() => processCapture((Uint8List.fromList([1, 2, 3]), null, true)), throwsA(anything));
  });

  test('sampleLuma reads strided rows and shrinks', () {
    final y = Uint8List(1000 * 600);
    for (var r = 0; r < 600; r++) {
      for (var c = 0; c < 1000; c++) {
        y[r * 1000 + c] = c < 900 ? (r < 300 ? 10 : 200) : 255; // last 100 = padding
      }
    }
    final l = sampleLuma(y, 900, 600, 1000, target: 180);
    expect(l.width, 180);
    expect(l.height, 120);
    expect(l.bytes[10 * l.width + 5], 10);
    expect(l.bytes[100 * l.width + 179], 200);
  });

  test('small frames are used as they are', () {
    final y = Uint8List(100 * 50);
    final l = sampleLuma(y, 100, 50, 100, target: 200);
    expect([l.width, l.height, l.stride], [100, 50, 100]);
  });
}
