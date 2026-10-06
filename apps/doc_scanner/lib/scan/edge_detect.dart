import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'geometry.dart';

/// A grayscale frame: one byte per pixel, [stride] bytes per row.
class Luma {
  const Luma(this.bytes, this.width, this.height, [int? stride])
      : stride = stride ?? width;
  final Uint8List bytes;
  final int width;
  final int height;
  final int stride;

  factory Luma.fromImage(img.Image im) {
    final g = Uint8List(im.width * im.height);
    var i = 0;
    for (final p in im) {
      g[i++] = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
    }
    return Luma(g, im.width, im.height);
  }
}

/// Finds the document (a page, receipt, card...) in a camera frame.
///
/// Works on a small copy of the frame: the page is separated from the
/// background by brightness (Otsu), holes such as text are closed, and the
/// biggest region's outline is fitted with the largest four-cornered shape.
/// Runs in pure Dart, so no Google Play services or OpenCV are needed.
/// Returns null when nothing page-like is in view.
Quad? detectDocument(Luma frame, {int work = 180}) {
  final small = _downscale(frame, work);
  final w = small.width, h = small.height;
  final blurred = _boxBlur(small.bytes, w, h, 2);
  final t = _otsu(blurred);
  Quad? best;
  var bestScore = 0.0;
  for (final bright in const [true, false]) {
    final mask = Uint8List(w * h);
    for (var i = 0; i < mask.length; i++) {
      mask[i] = (bright ? blurred[i] > t : blurred[i] < t) ? 1 : 0;
    }
    final closed = _erode(_dilate(mask, w, h, 2), w, h, 2);
    final opened = _dilate(_erode(closed, w, h, 1), w, h, 1);
    final comp = _largestComponent(opened, w, h);
    if (comp == null || comp.count < w * h * 0.08) continue;
    // A region that runs off several edges is the table, not the page. A
    // dark "page" on a light table must sit fully inside the frame.
    if (comp.bordersTouched >= (bright ? 3 : 1)) continue;
    final hull = _convexHull(comp.boundary);
    if (hull.length < 4) continue;
    final quad = _maxQuad(hull);
    if (quad == null) continue;
    final q = Quad.ordered([
      for (final p in quad) P(p.x / (w - 1), p.y / (h - 1)),
    ]);
    final area = q.area;
    if (area < 0.12 || area > 0.985 || !q.isConvex) continue;
    final fill = comp.count / (area * w * h);
    if (fill < 0.75) continue;
    // Prefer big, solid, four-sided regions.
    final score = area * math.min(fill, 1.0) * (bright ? 1.0 : 0.8);
    if (score > bestScore) {
      bestScore = score;
      best = q;
    }
  }
  return best;
}

/// Detects the document in an encoded photo (after applying EXIF rotation).
Quad? detectInPhoto(Uint8List encoded) {
  final im = img.decodeImage(encoded);
  if (im == null) return null;
  final up = img.bakeOrientation(im);
  final small = up.width > up.height
      ? img.copyResize(up, width: 360)
      : img.copyResize(up, height: 360);
  return detectDocument(Luma.fromImage(small));
}

Luma _downscale(Luma f, int target) {
  final scale = math.max(f.width, f.height) / target;
  if (scale <= 1) {
    final copy = Uint8List(f.width * f.height);
    for (var y = 0; y < f.height; y++) {
      copy.setRange(y * f.width, (y + 1) * f.width, f.bytes, y * f.stride);
    }
    return Luma(copy, f.width, f.height);
  }
  final w = (f.width / scale).floor(), h = (f.height / scale).floor();
  final out = Uint8List(w * h);
  final step = scale.floor().clamp(1, 1 << 20);
  for (var y = 0; y < h; y++) {
    final sy = (y * scale).floor();
    for (var x = 0; x < w; x++) {
      final sx = (x * scale).floor();
      var sum = 0, n = 0;
      // Average a few samples per output pixel to smooth sensor noise.
      for (var dy = 0; dy < step; dy += math.max(1, step ~/ 2)) {
        final row = (sy + dy).clamp(0, f.height - 1) * f.stride;
        for (var dx = 0; dx < step; dx += math.max(1, step ~/ 2)) {
          sum += f.bytes[row + (sx + dx).clamp(0, f.width - 1)];
          n++;
        }
      }
      out[y * w + x] = sum ~/ n;
    }
  }
  return Luma(out, w, h);
}

Uint8List _boxBlur(Uint8List src, int w, int h, int r) {
  final tmp = Uint8List(w * h), out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var s = 0, n = 0;
      for (var k = -r; k <= r; k++) {
        final xx = x + k;
        if (xx < 0 || xx >= w) continue;
        s += src[y * w + xx];
        n++;
      }
      tmp[y * w + x] = s ~/ n;
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var s = 0, n = 0;
      for (var k = -r; k <= r; k++) {
        final yy = y + k;
        if (yy < 0 || yy >= h) continue;
        s += tmp[yy * w + x];
        n++;
      }
      out[y * w + x] = s ~/ n;
    }
  }
  return out;
}

int _otsu(Uint8List g) {
  final hist = List<int>.filled(256, 0);
  for (final v in g) {
    hist[v]++;
  }
  final total = g.length;
  var sum = 0.0;
  for (var i = 0; i < 256; i++) {
    sum += i * hist[i];
  }
  var sumB = 0.0, wB = 0, best = -1.0, t = 127;
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

Uint8List _dilate(Uint8List m, int w, int h, int r) => _morph(m, w, h, r, 1);
Uint8List _erode(Uint8List m, int w, int h, int r) => _morph(m, w, h, r, 0);

/// Square-window morphology, separable: [hit] is the value that spreads.
Uint8List _morph(Uint8List m, int w, int h, int r, int hit) {
  final tmp = Uint8List(w * h), out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var v = 1 - hit;
      for (var k = -r; k <= r && v != hit; k++) {
        final xx = (x + k).clamp(0, w - 1);
        if (m[y * w + xx] == hit) v = hit;
      }
      tmp[y * w + x] = v;
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var v = 1 - hit;
      for (var k = -r; k <= r && v != hit; k++) {
        final yy = (y + k).clamp(0, h - 1);
        if (tmp[yy * w + x] == hit) v = hit;
      }
      out[y * w + x] = v;
    }
  }
  return out;
}

class _Comp {
  _Comp(this.count, this.boundary, this.bordersTouched);
  final int count;
  final List<math.Point<int>> boundary;

  /// How many image edges (0..4) the region reaches.
  final int bordersTouched;
}

_Comp? _largestComponent(Uint8List m, int w, int h) {
  final label = Int32List(w * h);
  var next = 0, bestLabel = 0, bestCount = 0;
  final stack = <int>[];
  for (var i = 0; i < m.length; i++) {
    if (m[i] == 0 || label[i] != 0) continue;
    next++;
    var count = 0;
    stack.add(i);
    label[i] = next;
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      count++;
      final x = p % w, y = p ~/ w;
      if (x > 0 && m[p - 1] == 1 && label[p - 1] == 0) {
        label[p - 1] = next;
        stack.add(p - 1);
      }
      if (x < w - 1 && m[p + 1] == 1 && label[p + 1] == 0) {
        label[p + 1] = next;
        stack.add(p + 1);
      }
      if (y > 0 && m[p - w] == 1 && label[p - w] == 0) {
        label[p - w] = next;
        stack.add(p - w);
      }
      if (y < h - 1 && m[p + w] == 1 && label[p + w] == 0) {
        label[p + w] = next;
        stack.add(p + w);
      }
    }
    if (count > bestCount) {
      bestCount = count;
      bestLabel = next;
    }
  }
  if (bestLabel == 0) return null;
  // Only the leftmost and rightmost pixel of each row matter for the hull.
  final pts = <math.Point<int>>[];
  for (var y = 0; y < h; y++) {
    var first = -1, last = -1;
    for (var x = 0; x < w; x++) {
      if (label[y * w + x] == bestLabel) {
        if (first < 0) first = x;
        last = x;
      }
    }
    if (first >= 0) {
      pts.add(math.Point(first, y));
      if (last != first) pts.add(math.Point(last, y));
    }
  }
  var top = false, bottom = false, left = false, right = false;
  for (final p in pts) {
    if (p.y == 0) top = true;
    if (p.y == h - 1) bottom = true;
    if (p.x == 0) left = true;
    if (p.x == w - 1) right = true;
  }
  final touched = [top, bottom, left, right].where((t) => t).length;
  return _Comp(bestCount, pts, touched);
}

/// Andrew's monotone chain; returns hull points counter-clockwise.
List<math.Point<int>> _convexHull(List<math.Point<int>> pts) {
  final p = [...pts]..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
  if (p.length < 3) return p;
  int cross(math.Point<int> o, math.Point<int> a, math.Point<int> b) =>
      (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
  final lower = <math.Point<int>>[];
  for (final q in p) {
    while (lower.length >= 2 && cross(lower[lower.length - 2], lower.last, q) <= 0) {
      lower.removeLast();
    }
    lower.add(q);
  }
  final upper = <math.Point<int>>[];
  for (final q in p.reversed) {
    while (upper.length >= 2 && cross(upper[upper.length - 2], upper.last, q) <= 0) {
      upper.removeLast();
    }
    upper.add(q);
  }
  return [...lower.sublist(0, lower.length - 1), ...upper.sublist(0, upper.length - 1)];
}

/// The largest-area quadrilateral whose corners are hull vertices.
List<math.Point<int>>? _maxQuad(List<math.Point<int>> hull) {
  var pts = hull;
  // Keep it quick: a page outline needs no more than ~64 hull points.
  if (pts.length > 64) {
    final step = pts.length / 64;
    pts = [for (var i = 0; i < 64; i++) pts[(i * step).floor()]];
  }
  final n = pts.length;
  if (n < 4) return null;
  double tri(math.Point<int> a, math.Point<int> b, math.Point<int> c) =>
      ((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)).abs() / 2;
  var best = 0.0;
  List<math.Point<int>>? out;
  for (var i = 0; i < n; i++) {
    for (var k = i + 2; k < n; k++) {
      var bj = -1, bjA = 0.0;
      for (var j = i + 1; j < k; j++) {
        final a = tri(pts[i], pts[j], pts[k]);
        if (a > bjA) {
          bjA = a;
          bj = j;
        }
      }
      var bl = -1, blA = 0.0;
      for (var l = k + 1; l < n + i; l++) {
        final a = tri(pts[i], pts[k], pts[l % n]);
        if (a > blA) {
          blA = a;
          bl = l % n;
        }
      }
      if (bj < 0 || bl < 0) continue;
      if (bjA + blA > best) {
        best = bjA + blA;
        out = [pts[i], pts[bj], pts[k], pts[bl]];
      }
    }
  }
  return out;
}
