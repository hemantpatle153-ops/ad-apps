import 'dart:typed_data';
import 'dart:math' as math;

import 'package:doc_scanner/scan/edge_detect.dart';
import 'package:doc_scanner/scan/geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A photo-like scene: a textured, unevenly lit table with a page on it.
img.Image scene(Quad page,
    {int w = 480, int h = 640, int seed = 1, int bg = 70, int paper = 225, bool shadow = true}) {
  final r = math.Random(seed);
  final im = img.Image(width: w, height: h);
  for (final p in im) {
    final grain = (math.sin(p.y / 7.0 + p.x / 40.0) * 12).round();
    final v = (bg + grain + r.nextInt(16)).clamp(0, 255);
    p
      ..r = v + 20
      ..g = v
      ..b = v - 15;
  }
  final poly = [for (final c in page.points) img.Point(c.x * w, c.y * h)];
  img.fillPolygon(im, vertices: poly, color: img.ColorRgb8(paper, paper, paper - 5));
  // Text lines: dark strokes inside the page.
  for (var k = 1; k < 12; k++) {
    final t = k / 12;
    final a = page.tl + (page.bl - page.tl).scale(t), b = page.tr + (page.br - page.tr).scale(t);
    final a2 = a + (b - a).scale(0.1), b2 = a + (b - a).scale(0.85);
    img.drawLine(im,
        x1: (a2.x * w).round(), y1: (a2.y * h).round(),
        x2: (b2.x * w).round(), y2: (b2.y * h).round(),
        color: img.ColorRgb8(30, 30, 30), thickness: 2);
  }
  if (shadow) {
    for (final p in im) {
      final f = 1 - 0.3 * (p.x / w);
      p
        ..r = (p.r * f).round()
        ..g = (p.g * f).round()
        ..b = (p.b * f).round();
    }
  }
  return im;
}

Quad rotatedRect(double cx, double cy, double hw, double hh, double deg) {
  final a = deg * math.pi / 180;
  P rot(double x, double y) => P(cx + x * math.cos(a) - y * math.sin(a), cy + x * math.sin(a) + y * math.cos(a));
  return Quad.ordered([rot(-hw, -hh), rot(hw, -hh), rot(hw, hh), rot(-hw, hh)]);
}

void expectNear(Quad? found, Quad want, {double tol = 0.03}) {
  expect(found, isNotNull, reason: 'no document found, wanted $want');
  expect(found!.maxShift(want), lessThan(tol), reason: 'found $found, wanted $want');
}

void main() {
  test('straight page on a table', () {
    const page = Quad(P(0.15, 0.12), P(0.85, 0.12), P(0.85, 0.88), P(0.15, 0.88));
    expectNear(detectDocument(Luma.fromImage(scene(page))), page);
  });

  for (final deg in [5.0, 15.0, 30.0, 40.0, -20.0]) {
    test('page rotated $deg degrees', () {
      final page = rotatedRect(0.5, 0.5, 0.26, 0.3, deg);
      expectNear(detectDocument(Luma.fromImage(scene(page, seed: deg.round()))), page);
    });
  }

  test('page seen in perspective', () {
    const page = Quad(P(0.25, 0.15), P(0.75, 0.18), P(0.9, 0.85), P(0.08, 0.82));
    expectNear(detectDocument(Luma.fromImage(scene(page))), page);
  });

  test('landscape frame like the camera stream', () {
    const page = Quad(P(0.2, 0.15), P(0.75, 0.2), P(0.7, 0.85), P(0.25, 0.8));
    expectNear(detectDocument(Luma.fromImage(scene(page, w: 640, h: 480))), page);
  });

  test('empty table finds nothing', () {
    final im = scene(Quad.full, paper: 70);
    final empty = img.Image(width: 480, height: 640);
    for (final p in empty) {
      final v = 60 + (math.sin(p.x / 9.0) * 10).round();
      p
        ..r = v
        ..g = v
        ..b = v;
    }
    expect(detectDocument(Luma.fromImage(empty)), isNull);
    expect(im.width, 480);
  });

  test('tiny paper scrap is ignored', () {
    const scrap = Quad(P(0.45, 0.45), P(0.55, 0.45), P(0.55, 0.52), P(0.45, 0.52));
    expect(detectDocument(Luma.fromImage(scene(scrap))), isNull);
  });

  test('strided luma rows are read correctly', () {
    const page = Quad(P(0.15, 0.12), P(0.85, 0.12), P(0.85, 0.88), P(0.15, 0.88));
    final l = Luma.fromImage(scene(page, w: 300, h: 400));
    final padded = List<int>.filled(320 * 400, 0);
    for (var y = 0; y < 400; y++) {
      padded.setRange(y * 320, y * 320 + 300, l.bytes, y * 300);
    }
    final strided = Luma(Uint8List.fromList(padded), 300, 400, 320);
    expectNear(detectDocument(strided), page);
  });

  test('warp flattens a perspective page to the right shape', () {
    const page = Quad(P(0.25, 0.15), P(0.75, 0.18), P(0.9, 0.85), P(0.08, 0.82));
    final out = warpPerspective(scene(page, shadow: false), page);
    // The page is roughly 0.6 wide by 0.68 tall in a 480x640 frame.
    expect(out.height, greaterThan(out.width));
    // Corners of the result are paper, not table.
    for (final (x, y) in [(3, 3), (out.width - 4, 3), (3, out.height - 4), (out.width - 4, out.height - 4)]) {
      expect(out.getPixel(x, y).r, greaterThan(180), reason: 'corner $x,$y');
    }
  });

  test('quad helpers', () {
    expect(Quad.full.area, closeTo(1, 1e-9));
    expect(Quad.full.isConvex, isTrue);
    const bow = Quad(P(0, 0), P(1, 1), P(1, 0), P(0, 1));
    expect(bow.isConvex, isFalse);
    expect(Quad.ordered(const [P(1, 1), P(0, 0), P(0, 1), P(1, 0)]).points,
        const [P(0, 0), P(1, 0), P(1, 1), P(0, 1)]);
    expect(Quad.full.rotated(1).points, Quad.full.points);
    const q = Quad(P(0.1, 0.2), P(0.9, 0.2), P(0.9, 0.7), P(0.1, 0.7));
    expect(q.rotated(4).maxShift(q), lessThan(1e-9));
    // One turn clockwise: the top-left corner moves to the top-right side.
    expect(q.rotated(1).tl, const P(1 - 0.7, 0.1));
  });
}
