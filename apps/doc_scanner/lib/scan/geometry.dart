import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A point in fractions of the image (0..1), so it doesn't depend on the
/// resolution it was found at.
class P {
  const P(this.x, this.y);
  final double x;
  final double y;

  P operator +(P o) => P(x + o.x, y + o.y);
  P operator -(P o) => P(x - o.x, y - o.y);
  P scale(double s) => P(x * s, y * s);
  double dist(P o) => math.sqrt((x - o.x) * (x - o.x) + (y - o.y) * (y - o.y));
  P clamp() => P(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));

  @override
  bool operator ==(Object other) => other is P && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
  @override
  String toString() => '(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)})';
}

/// The four corners of a document, clockwise from top-left.
class Quad {
  const Quad(this.tl, this.tr, this.br, this.bl);
  final P tl, tr, br, bl;

  static const full = Quad(P(0, 0), P(1, 0), P(1, 1), P(0, 1));

  /// A slightly inset frame, the starting point when nothing is found.
  static const inset = Quad(P(0.08, 0.08), P(0.92, 0.08), P(0.92, 0.92), P(0.08, 0.92));

  List<P> get points => [tl, tr, br, bl];

  Quad withPoint(int i, P p) => switch (i) {
        0 => Quad(p, tr, br, bl),
        1 => Quad(tl, p, br, bl),
        2 => Quad(tl, tr, p, bl),
        _ => Quad(tl, tr, br, p),
      };

  /// Puts arbitrary corners in TL, TR, BR, BL order.
  factory Quad.ordered(List<P> pts) {
    assert(pts.length == 4);
    final bySum = [...pts]..sort((a, b) => (a.x + a.y).compareTo(b.x + b.y));
    final tl = bySum.first, br = bySum.last;
    final rest = pts.where((p) => !identical(p, tl) && !identical(p, br)).toList();
    if (rest.length != 2) return Quad(tl, P(br.x, tl.y), br, P(tl.x, br.y));
    final tr = rest[0].x - rest[0].y > rest[1].x - rest[1].y ? rest[0] : rest[1];
    final bl = identical(tr, rest[0]) ? rest[1] : rest[0];
    return Quad(tl, tr, br, bl);
  }

  /// Area as a share of the whole image (shoelace formula).
  double get area {
    final p = points;
    var s = 0.0;
    for (var i = 0; i < 4; i++) {
      final a = p[i], b = p[(i + 1) % 4];
      s += a.x * b.y - b.x * a.y;
    }
    return s.abs() / 2;
  }

  /// True when every turn goes the same way (no bow-tie or dent).
  bool get isConvex {
    final p = points;
    double? sign;
    for (var i = 0; i < 4; i++) {
      final a = p[i], b = p[(i + 1) % 4], c = p[(i + 2) % 4];
      final cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
      if (cross.abs() < 1e-9) return false;
      sign ??= cross.sign;
      if (cross.sign != sign) return false;
    }
    return true;
  }

  /// Largest distance any corner moved, for "hold still" detection.
  double maxShift(Quad o) {
    var m = 0.0;
    for (var i = 0; i < 4; i++) {
      m = math.max(m, points[i].dist(o.points[i]));
    }
    return m;
  }

  /// Rotates the quad with the image it belongs to, clockwise.
  Quad rotated(int quarterTurns) {
    var q = this;
    for (var i = 0; i < quarterTurns % 4; i++) {
      P r(P p) => P(1 - p.y, p.x);
      // After turning, the old bottom-left becomes the top-left.
      q = Quad(r(q.bl), r(q.tl), r(q.tr), r(q.br));
    }
    return q;
  }

  Quad lerp(Quad o, double t) => Quad(
        tl + (o.tl - tl).scale(t),
        tr + (o.tr - tr).scale(t),
        br + (o.br - br).scale(t),
        bl + (o.bl - bl).scale(t),
      );

  @override
  String toString() => 'Quad($tl, $tr, $br, $bl)';
}

/// 3x3 projective transform mapping the unit square to [q] (in pixels).
List<double> _squareToQuad(List<double> x, List<double> y) {
  final dx1 = x[1] - x[2], dx2 = x[3] - x[2], sx = x[0] - x[1] + x[2] - x[3];
  final dy1 = y[1] - y[2], dy2 = y[3] - y[2], sy = y[0] - y[1] + y[2] - y[3];
  double g, h;
  if (sx.abs() < 1e-12 && sy.abs() < 1e-12) {
    g = 0;
    h = 0;
  } else {
    final den = dx1 * dy2 - dx2 * dy1;
    g = (sx * dy2 - dx2 * sy) / den;
    h = (dx1 * sy - sx * dy1) / den;
  }
  return [
    x[1] - x[0] + g * x[1], x[3] - x[0] + h * x[3], x[0],
    y[1] - y[0] + g * y[1], y[3] - y[0] + h * y[3], y[0],
    g, h, 1,
  ];
}

/// Output size for a flattened document: the average lengths of opposite
/// edges, so the page keeps its real shape.
(int, int) rectifiedSize(Quad q, int w, int h, {int maxSide = 2600}) {
  double len(P a, P b) => math.sqrt(math.pow((a.x - b.x) * w, 2) + math.pow((a.y - b.y) * h, 2));
  var ow = (len(q.tl, q.tr) + len(q.bl, q.br)) / 2;
  var oh = (len(q.tl, q.bl) + len(q.tr, q.br)) / 2;
  final s = math.max(ow, oh) > maxSide ? maxSide / math.max(ow, oh) : 1.0;
  ow *= s;
  oh *= s;
  return (math.max(1, ow.round()), math.max(1, oh.round()));
}

/// Flattens the document inside [q] to a straight rectangle with a true
/// perspective transform (bilinear sampling).
img.Image warpPerspective(img.Image src, Quad q, {int maxSide = 2600}) {
  final w = src.width, h = src.height;
  final (ow, oh) = rectifiedSize(q, w, h, maxSide: maxSide);
  final m = _squareToQuad(
    [q.tl.x * (w - 1), q.tr.x * (w - 1), q.br.x * (w - 1), q.bl.x * (w - 1)],
    [q.tl.y * (h - 1), q.tr.y * (h - 1), q.br.y * (h - 1), q.bl.y * (h - 1)],
  );
  final s = src.convert(numChannels: 3, format: img.Format.uint8);
  final sb = s.getBytes(order: img.ChannelOrder.rgb);
  final out = img.Image(width: ow, height: oh);
  final ob = out.getBytes(order: img.ChannelOrder.rgb);
  final rowBytes = w * 3;
  var o = 0;
  for (var j = 0; j < oh; j++) {
    final v = oh == 1 ? 0.0 : j / (oh - 1);
    for (var i = 0; i < ow; i++) {
      final u = ow == 1 ? 0.0 : i / (ow - 1);
      final z = m[6] * u + m[7] * v + m[8];
      var sx = (m[0] * u + m[1] * v + m[2]) / z;
      var sy = (m[3] * u + m[4] * v + m[5]) / z;
      if (sx < 0) sx = 0;
      if (sy < 0) sy = 0;
      if (sx > w - 1) sx = (w - 1).toDouble();
      if (sy > h - 1) sy = (h - 1).toDouble();
      final x0 = sx.floor(), y0 = sy.floor();
      final x1 = x0 + 1 < w ? x0 + 1 : x0, y1 = y0 + 1 < h ? y0 + 1 : y0;
      final fx = sx - x0, fy = sy - y0;
      final a = y0 * rowBytes + x0 * 3, b = y0 * rowBytes + x1 * 3;
      final c = y1 * rowBytes + x0 * 3, d = y1 * rowBytes + x1 * 3;
      for (var k = 0; k < 3; k++) {
        final top = sb[a + k] + (sb[b + k] - sb[a + k]) * fx;
        final bot = sb[c + k] + (sb[d + k] - sb[c + k]) * fx;
        ob[o++] = (top + (bot - top) * fy).round();
      }
    }
  }
  return img.Image.fromBytes(width: ow, height: oh, bytes: ob.buffer, numChannels: 3);
}

/// Decodes a photo, applies its EXIF rotation, crops and flattens [q],
/// and returns a JPEG.
Uint8List cropDocument(Uint8List jpeg, Quad q, {int maxSide = 2600, int quality = 92}) {
  final src = img.decodeImage(jpeg);
  if (src == null) throw const FormatException('Not an image.');
  final upright = img.bakeOrientation(src);
  final out = warpPerspective(upright, q, maxSide: maxSide);
  return img.encodeJpg(out, quality: quality);
}
