import 'dart:math';
import 'dart:typed_data';

import 'package:doc_scanner/image_filters.dart';
import 'package:doc_scanner/jobs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image solid(int w, int h, int r, int g, int b) =>
    img.fill(img.Image(width: w, height: h), color: img.ColorRgb8(r, g, b));

/// Left half dark ink, right half light paper, with seeded noise.
img.Image page(int w, int h, int seed) {
  final rnd = Random(seed);
  final im = img.Image(width: w, height: h);
  for (final p in im) {
    final base = p.x < w / 2 ? 30 + rnd.nextInt(30) : 200 + rnd.nextInt(40);
    p
      ..r = base
      ..g = (base + rnd.nextInt(10)).clamp(0, 255)
      ..b = (base - rnd.nextInt(10)).clamp(0, 255);
  }
  return im;
}

void main() {
  group('labels', () {
    const want = {
      PageFilter.original: 'Original',
      PageFilter.enhanced: 'Auto color',
      PageFilter.grayscale: 'Grayscale',
      PageFilter.whiteboard: 'Whiteboard',
      PageFilter.blackWhite: 'B&W',
    };
    want.forEach((f, l) => test(f.name, () => expect(f.label, l)));
    test('labels are unique', () {
      expect(PageFilter.values.map((f) => f.label).toSet().length, PageFilter.values.length);
    });
  });

  group('every filter, size and turn', () {
    for (final f in PageFilter.values) {
      for (final (w, h) in [(16, 16), (40, 24), (24, 40)]) {
        for (final turns in [0, 1, 2, 3]) {
          test('${f.name} ${w}x$h turned $turns', () {
            final src = Uint8List.fromList(img.encodePng(page(w, h, w * h)));
            final out = img.decodeJpg(processJob((src, f, turns, 2400, 90)))!;
            final swap = turns.isOdd;
            expect([out.width, out.height], swap ? [h, w] : [w, h]);
          });
        }
      }
    }
  });

  group('grayscale makes channels equal', () {
    for (var seed = 0; seed < 8; seed++) {
      test('seed $seed', () {
        final out = applyFilter(page(12, 8, seed), PageFilter.grayscale);
        for (final p in out) {
          expect(p.r, p.g);
          expect(p.g, p.b);
        }
      });
    }
  });

  group('black and white is two-tone and splits ink from paper', () {
    for (var seed = 0; seed < 10; seed++) {
      test('seed $seed', () {
        final out = applyFilter(page(20, 10, seed), PageFilter.blackWhite);
        for (final p in out) {
          expect(p.r == 0 || p.r == 255, isTrue);
          expect(p.r, p.g);
          expect(p.r, p.b);
          expect(p.r, p.x < 10 ? 0 : 255);
        }
      });
    }
  });

  group('whiteboard pushes light pixels to white', () {
    for (final v in [180, 200, 230, 250]) {
      test('gray $v', () {
        final out = applyFilter(solid(6, 6, v, v, v), PageFilter.whiteboard);
        for (final p in out) {
          expect([p.r, p.g, p.b], [255, 255, 255]);
        }
      });
    }
    test('dark ink stays dark', () {
      final out = applyFilter(solid(6, 6, 20, 20, 20), PageFilter.whiteboard);
      expect(out.getPixel(3, 3).r, lessThan(100));
    });
  });

  group('original is untouched', () {
    for (var seed = 0; seed < 4; seed++) {
      test('seed $seed', () {
        final src = page(8, 8, seed);
        final copy = src.clone();
        final out = applyFilter(src, PageFilter.original);
        for (final p in out) {
          final q = copy.getPixel(p.x, p.y);
          expect([p.r, p.g, p.b], [q.r, q.g, q.b]);
        }
      });
    }
  });

  group('enhanced raises contrast', () {
    for (var seed = 0; seed < 4; seed++) {
      test('seed $seed', () {
        final src = page(20, 10, seed);
        num spread(img.Image im) => im.getPixel(15, 5).r - im.getPixel(2, 5).r;
        final before = spread(src.clone());
        final after = spread(applyFilter(src, PageFilter.enhanced));
        expect(after, greaterThan(before));
      });
    }
  });

  group('maxSide scaling keeps aspect ratio', () {
    const cases = [(400, 200, 100), (200, 400, 100), (300, 300, 120), (90, 60, 100), (500, 100, 250)];
    for (final (w, h, m) in cases) {
      test('${w}x$h with maxSide $m', () {
        final src = Uint8List.fromList(img.encodeJpg(solid(w, h, 200, 200, 200)));
        final out = img.decodeJpg(processPage(src, maxSide: m))!;
        final s = max(w, h) > m ? m / max(w, h) : 1.0;
        expect(out.width, closeTo(w * s, 1));
        expect(out.height, closeTo(h * s, 1));
      });
    }
  });

  group('bad input', () {
    for (final b in [<int>[], [0], [1, 2, 3, 4], List.filled(64, 255)]) {
      test('${b.length} junk bytes', () {
        expect(() => processPage(Uint8List.fromList(b)), throwsFormatException);
      });
    }
  });

  group('shrinkJpeg', () {
    for (final side in [1600, 2000]) {
      test('$side px photo is capped at 1400 and smaller', () {
        final big = Uint8List.fromList(img.encodeJpg(page(side, side ~/ 2, side), quality: 95));
        final small = shrinkJpeg(big);
        expect(small.length, lessThan(big.length));
        expect(img.decodeJpg(small)!.width, 1400);
      });
    }
  });
}
