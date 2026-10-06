import 'dart:typed_data';

import 'package:doc_scanner/image_filters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List photo(int w, int h) {
  final im = img.Image(width: w, height: h);
  for (final p in im) {
    final v = p.x < w / 2 ? 40 : 220;
    p
      ..r = v
      ..g = v + 10
      ..b = v - 20;
  }
  return img.encodeJpg(im);
}

void main() {
  test('every filter returns a valid JPEG of the same size', () {
    for (final f in PageFilter.values) {
      final out = img.decodeJpg(processPage(photo(120, 80), filter: f))!;
      expect([out.width, out.height], [120, 80], reason: f.label);
    }
  });

  test('rotation swaps width and height', () {
    final out = img.decodeJpg(processPage(photo(120, 80), quarterTurns: 1))!;
    expect([out.width, out.height], [80, 120]);
  });

  test('big photos are scaled down', () {
    final out = img.decodeJpg(processPage(photo(3000, 1000), maxSide: 1500))!;
    expect(out.width, 1500);
  });

  test('black and white is two-tone', () {
    final out = img.decodeJpg(processPage(photo(60, 40), filter: PageFilter.blackWhite, quality: 100))!;
    final dark = out.getPixel(5, 20).r;
    final light = out.getPixel(55, 20).r;
    expect(dark, lessThan(30));
    expect(light, greaterThan(225));
  });

  test('non-images are rejected', () {
    expect(() => processPage(Uint8List.fromList([1, 2, 3])), throwsFormatException);
  });

  test('shrinkJpeg makes files smaller', () {
    final big = processPage(photo(2000, 2000), quality: 95);
    expect(shrinkJpeg(big).length, lessThan(big.length));
  });
}
