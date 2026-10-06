import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Adobe Scan-style looks for a page photo.
enum PageFilter {
  original('Original'),
  enhanced('Auto color'),
  grayscale('Grayscale'),
  whiteboard('Whiteboard'),
  blackWhite('B&W');

  const PageFilter(this.label);
  final String label;
}

/// Applies [filter] and [quarterTurns] of clockwise rotation, returning a
/// JPEG. Pure Dart, so it can run in an isolate and in tests.
Uint8List processPage(Uint8List bytes,
    {PageFilter filter = PageFilter.original,
    int quarterTurns = 0,
    int maxSide = 2400,
    int quality = 88}) {
  img.Image? im;
  try {
    im = img.decodeImage(bytes);
  } catch (_) {
    im = null;
  }
  if (im == null) throw const FormatException('Not an image.');
  im = img.bakeOrientation(im);
  if (im.width > maxSide || im.height > maxSide) {
    im = im.width >= im.height
        ? img.copyResize(im, width: maxSide)
        : img.copyResize(im, height: maxSide);
  }
  im = applyFilter(im, filter);
  if (quarterTurns % 4 != 0) im = img.copyRotate(im, angle: 90 * (quarterTurns % 4));
  return img.encodeJpg(im, quality: quality);
}

img.Image applyFilter(img.Image im, PageFilter filter) {
  switch (filter) {
    case PageFilter.original:
      return im;
    case PageFilter.enhanced:
      return img.adjustColor(im, contrast: 1.25, saturation: 1.15, brightness: 1.05);
    case PageFilter.grayscale:
      return img.grayscale(im);
    case PageFilter.whiteboard:
      final g = img.adjustColor(im, contrast: 1.6, brightness: 1.2);
      return _whiten(g, 200);
    case PageFilter.blackWhite:
      final g = img.grayscale(im);
      final t = _otsu(g);
      for (final p in g) {
        final v = p.r > t ? 255 : 0;
        p
          ..r = v
          ..g = v
          ..b = v;
      }
      return g;
  }
}

/// Pushes near-white pixels to pure white (cleans whiteboard glare).
img.Image _whiten(img.Image im, int cut) {
  for (final p in im) {
    if (p.r > cut && p.g > cut && p.b > cut) {
      p
        ..r = 255
        ..g = 255
        ..b = 255;
    }
  }
  return im;
}

/// Otsu threshold on the red channel of a grayscale image.
int _otsu(img.Image g) {
  final hist = List<int>.filled(256, 0);
  for (final p in g) {
    hist[p.r.toInt()]++;
  }
  final total = g.width * g.height;
  var sum = 0.0;
  for (var i = 0; i < 256; i++) {
    sum += i * hist[i];
  }
  var sumB = 0.0, wB = 0, best = 0.0, t = 127;
  for (var i = 0; i < 256; i++) {
    wB += hist[i];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += i * hist[i];
    final mB = sumB / wB, mF = (sum - sumB) / wF;
    final between = wB * wF * (mB - mF) * (mB - mF);
    if (between > best) {
      best = between;
      t = i;
    }
  }
  return t;
}

/// Re-encodes an image smaller (for compression).
Uint8List shrinkJpeg(Uint8List bytes, {int maxSide = 1400, int quality = 60}) =>
    processPage(bytes, maxSide: maxSide, quality: quality);
