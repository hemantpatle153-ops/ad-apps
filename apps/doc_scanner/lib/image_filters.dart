import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Adobe Scan-style looks for a page photo.
enum PageFilter {
  original('Original'),
  magic('Magic color'),
  lightText('Light text'),
  cleanBw('Clean B&W'),
  enhanced('Auto color'),
  grayscale('Grayscale'),
  whiteboard('Whiteboard'),
  blackWhite('B&W');

  const PageFilter(this.label);
  final String label;
}

/// Applies [filter], then the user's [brightness] and [contrast] (each
/// -100..100, 0 = unchanged) and [quarterTurns] of clockwise rotation,
/// returning a JPEG. Pure Dart, so it can run in an isolate and in tests.
Uint8List processPage(Uint8List bytes,
    {PageFilter filter = PageFilter.original,
    int quarterTurns = 0,
    int maxSide = 2400,
    int quality = 88,
    int brightness = 0,
    int contrast = 0}) {
  img.Image? im;
  try {
    im = img.decodeImage(bytes);
  } catch (_) {
    im = null;
  }
  if (im == null) throw const FormatException('Not an image.');
  im = fitWithin(img.bakeOrientation(im), maxSide);
  im = applyFilter(im, filter);
  if (brightness != 0 || contrast != 0) im = adjustPage(im, brightness, contrast);
  if (quarterTurns % 4 != 0) im = img.copyRotate(im, angle: 90 * (quarterTurns % 4));
  return img.encodeJpg(im, quality: quality);
}

/// Scales [im] down so neither side is over [maxSide]. Averages pixels
/// (rather than skipping them) so small print stays sharp and smooth.
img.Image fitWithin(img.Image im, int maxSide) {
  if (im.width <= maxSide && im.height <= maxSide) return im;
  return im.width >= im.height
      ? img.copyResize(im, width: maxSide, interpolation: img.Interpolation.average)
      : img.copyResize(im, height: maxSide, interpolation: img.Interpolation.average);
}

img.Image applyFilter(img.Image im, PageFilter filter) {
  switch (filter) {
    case PageFilter.original:
      return im;
    case PageFilter.magic:
      return _adjust(removeShadows(im), contrast: 1.15, saturation: 1.2);
    case PageFilter.lightText:
      // Faint pencil or light print: flatten the light, then make anything
      // darker than paper 3.5 times darker so thin strokes become solid.
      final g = _gray(removeShadows(im));
      final b = _bytes(g);
      final curve = Uint8List(256);
      for (var v = 0; v < 256; v++) {
        curve[v] = v >= 242 ? 255 : (255 - (255 - v) * 3.5).round().clamp(0, 255);
      }
      for (var i = 0; i < b.length; i++) {
        b[i] = curve[b[i]];
      }
      return g;
    case PageFilter.cleanBw:
      return _threshold(_gray(removeShadows(im)));
    case PageFilter.enhanced:
      return _adjust(_autoLevels(im), saturation: 1.12);
    case PageFilter.grayscale:
      return _gray(im);
    case PageFilter.whiteboard:
      return _whiten(_adjust(im, contrast: 1.6, brightness: 1.2), 200);
    case PageFilter.blackWhite:
      return _threshold(_gray(im));
  }
}

/// The user's brightness and contrast sliders, each -100..100.
img.Image adjustPage(img.Image im, int brightness, int contrast) {
  final out = _rgb(im, copy: true);
  final b = _bytes(out);
  final add = brightness * 1.28;
  final k = contrast >= 0 ? 1 + contrast / 50 : 1 + contrast / 125;
  final lut = Uint8List(256);
  for (var v = 0; v < 256; v++) {
    lut[v] = ((v + add - 128) * k + 128).round().clamp(0, 255);
  }
  for (var i = 0; i < b.length; i++) {
    b[i] = lut[b[i]];
  }
  return out;
}

/// The image as 8-bit RGB. With [copy], never shares pixels with [im].
img.Image _rgb(img.Image im, {bool copy = false}) {
  final ok = im.format == img.Format.uint8 && im.numChannels == 3 && !im.hasPalette;
  if (ok) return copy ? im.clone() : im;
  return im.convert(format: img.Format.uint8, numChannels: 3);
}

/// Direct access to an 8-bit RGB image's pixels (r, g, b, r, g, b, ...).
Uint8List _bytes(img.Image rgb) => rgb.data!.toUint8List();

img.Image _fromBytes(int w, int h, Uint8List b) =>
    img.Image.fromBytes(width: w, height: h, bytes: b.buffer, numChannels: 3);

/// Gray with equal channels (Rec. 601 luma).
img.Image _gray(img.Image im) {
  final src = _bytes(_rgb(im));
  final out = Uint8List(src.length);
  for (var i = 0; i + 2 < src.length; i += 3) {
    final v = (src[i] * 77 + src[i + 1] * 150 + src[i + 2] * 29 + 128) >> 8;
    out[i] = out[i + 1] = out[i + 2] = v;
  }
  return _fromBytes(im.width, im.height, out);
}

/// Multiplies by [brightness], stretches around mid-gray by [contrast] and
/// pushes colors away from gray by [saturation] (1 = unchanged).
img.Image _adjust(img.Image im,
    {double contrast = 1, double saturation = 1, double brightness = 1}) {
  final src = _bytes(_rgb(im));
  final out = Uint8List(src.length);
  final lut = Float64List(256);
  for (var v = 0; v < 256; v++) {
    lut[v] = (v * brightness - 128) * contrast + 128;
  }
  for (var i = 0; i + 2 < src.length; i += 3) {
    var r = lut[src[i]], g = lut[src[i + 1]], b = lut[src[i + 2]];
    if (saturation != 1) {
      final l = 0.299 * r + 0.587 * g + 0.114 * b;
      r = l + (r - l) * saturation;
      g = l + (g - l) * saturation;
      b = l + (b - l) * saturation;
    }
    out[i] = r.round().clamp(0, 255);
    out[i + 1] = g.round().clamp(0, 255);
    out[i + 2] = b.round().clamp(0, 255);
  }
  return _fromBytes(im.width, im.height, out);
}

/// Stretches each channel so its darkest 1% is black and brightest 1% is
/// white, which also fixes a yellow or blue cast from indoor light.
img.Image _autoLevels(img.Image im) {
  final src = _bytes(_rgb(im));
  final n = src.length ~/ 3;
  final out = Uint8List(src.length);
  for (var c = 0; c < 3; c++) {
    final hist = List<int>.filled(256, 0);
    for (var i = c; i < src.length; i += 3) {
      hist[src[i]]++;
    }
    var lo = 0, hi = 255, acc = 0;
    final cut = n ~/ 100;
    while (lo < 255 && acc + hist[lo] <= cut) {
      acc += hist[lo++];
    }
    acc = 0;
    while (hi > 0 && acc + hist[hi] <= cut) {
      acc += hist[hi--];
    }
    final lut = Uint8List(256);
    for (var v = 0; v < 256; v++) {
      lut[v] = hi - lo < 16 ? v : ((v - lo) * 255 / (hi - lo)).round().clamp(0, 255);
    }
    for (var i = c; i < src.length; i += 3) {
      out[i] = lut[src[i]];
    }
  }
  return _fromBytes(im.width, im.height, out);
}

/// Black or white at the Otsu threshold of a gray image.
img.Image _threshold(img.Image gray) {
  final b = _bytes(gray);
  final t = _otsu(b);
  for (var i = 0; i < b.length; i++) {
    b[i] = b[i] > t ? 255 : 0;
  }
  return gray;
}

/// Pushes near-white pixels to pure white (cleans whiteboard glare).
img.Image _whiten(img.Image im, int cut) {
  final b = _bytes(im);
  for (var i = 0; i + 2 < b.length; i += 3) {
    if (b[i] > cut && b[i + 1] > cut && b[i + 2] > cut) b[i] = b[i + 1] = b[i + 2] = 255;
  }
  return im;
}

/// Otsu threshold over the first channel of gray RGB bytes.
int _otsu(Uint8List b) {
  final hist = List<int>.filled(256, 0);
  for (var i = 0; i < b.length; i += 3) {
    hist[b[i]]++;
  }
  final total = b.length ~/ 3;
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

/// Small previews of every filter for the filter strip, as JPEGs in
/// [PageFilter.values] order. Top-level so it can run in an isolate.
List<Uint8List> filterPreviewsJob(Uint8List photo) {
  final im = fitWithin(img.bakeOrientation(img.decodeImage(photo)!), 220);
  return [
    for (final f in PageFilter.values) img.encodeJpg(applyFilter(im, f), quality: 80),
  ];
}

/// Evens out lighting the way paid scanner apps do: estimates the paper's
/// brightness everywhere (a blurred "max" of a small copy, which skips the
/// ink) and divides it out, so shadows and uneven light turn white.
img.Image removeShadows(img.Image source) {
  final im = _rgb(source);
  final w = im.width, h = im.height;
  final sw = (w / 16).ceil().clamp(4, 400), sh = (h / 16).ceil().clamp(4, 400);
  var bg = img.copyResize(im, width: sw, height: sh, interpolation: img.Interpolation.average);
  final src = bg.clone();
  for (final p in bg) {
    num r = 0, g = 0, b = 0;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final q = src.getPixelClamped(p.x + dx, p.y + dy);
        if (q.r > r) r = q.r;
        if (q.g > g) g = q.g;
        if (q.b > b) b = q.b;
      }
    }
    p
      ..r = r
      ..g = g
      ..b = b;
  }
  final base = _bytes(_rgb(img.gaussianBlur(bg, radius: 2)));

  // Bilinear lookup of the small background for every full-size pixel.
  final x0 = Int32List(w), x1 = Int32List(w), fx = Float64List(w);
  for (var x = 0; x < w; x++) {
    final f = x * sw / w;
    final i = f.floor();
    x0[x] = i.clamp(0, sw - 1) * 3;
    x1[x] = math.min(i + 1, sw - 1) * 3;
    fx[x] = f - i;
  }
  final s = _bytes(im);
  final out = Uint8List(s.length);
  // 0.9: treat paper a little darker than its estimate so it lands on white.
  const gain = 255 / 0.9;
  var o = 0;
  for (var y = 0; y < h; y++) {
    final f = y * sh / h;
    final j = f.floor();
    final r0 = j.clamp(0, sh - 1) * sw * 3, r1 = math.min(j + 1, sh - 1) * sw * 3;
    final fy = f - j;
    for (var x = 0; x < w; x++) {
      final a0 = r0 + x0[x], a1 = r0 + x1[x], b0 = r1 + x0[x], b1 = r1 + x1[x];
      final t = fx[x];
      for (var c = 0; c < 3; c++) {
        final top = base[a0 + c] + (base[a1 + c] - base[a0 + c]) * t;
        final bot = base[b0 + c] + (base[b1 + c] - base[b0 + c]) * t;
        final paper = top + (bot - top) * fy;
        final v = s[o];
        out[o++] = paper < 8 ? v : (v * gain / paper).round().clamp(0, 255);
      }
    }
  }
  return _fromBytes(w, h, out);
}
