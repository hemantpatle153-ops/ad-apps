import 'package:doc_scanner/image_filters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Paper with a strong shadow from left to right and a row of ink.
img.Image shadowedPage() {
  final im = img.Image(width: 160, height: 120);
  for (final p in im) {
    final light = 120 + (p.x / 160 * 120).round(); // 120 (shadow) .. 240
    final ink = p.y > 55 && p.y < 62 && p.x % 20 < 12;
    final v = ink ? (light * 0.2).round() : light;
    p
      ..r = v
      ..g = v
      ..b = v;
  }
  return im;
}

void main() {
  test('shadow removal makes the paper evenly white', () {
    final out = removeShadows(shadowedPage());
    final left = out.getPixel(10, 20).r, right = out.getPixel(150, 20).r;
    expect(left, greaterThan(230));
    expect(right, greaterThan(230));
  });

  test('ink stays dark after shadow removal', () {
    final out = removeShadows(shadowedPage());
    expect(out.getPixel(4, 58).r, lessThan(90));
    expect(out.getPixel(144, 58).r, lessThan(90));
  });

  test('clean B&W keeps ink in the shadow and whitens paper', () {
    final out = applyFilter(shadowedPage(), PageFilter.cleanBw);
    expect(out.getPixel(4, 58).r, 0);
    expect(out.getPixel(10, 20).r, 255);
    expect(out.getPixel(150, 20).r, 255);
  });

  test('plain B&W loses the shadowed side (why Clean B&W exists)', () {
    final out = applyFilter(shadowedPage(), PageFilter.blackWhite);
    expect(out.getPixel(10, 20).r, 0);
  });

  test('magic color returns the same size', () {
    final out = applyFilter(shadowedPage(), PageFilter.magic);
    expect([out.width, out.height], [160, 120]);
    expect(out.getPixel(10, 20).r, greaterThan(220));
  });
}
