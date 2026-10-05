import 'dart:math';

import 'package:flutter/material.dart';

import '../game/board.dart';
import '../game/themes.dart';
import 'geometry.dart';

/// Paints the static board: cells, numbers, ladders and snakes.
///
/// Wrap it in a RepaintBoundary; it only repaints when the board or theme
/// changes, while tokens animate on a separate layer above it.
class BoardPainter extends CustomPainter {
  BoardPainter(this.board, this.theme, {this.showNumbers = true});

  final BoardLayout board;
  final BoardTheme theme;
  final bool showNumbers;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.width / 10;
    final outer =
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(c * 0.35));
    canvas.save();
    canvas.clipRRect(outer);
    _cells(canvas, c);
    canvas.restore();
    canvas.drawRRect(
      outer.deflate(c * 0.04),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = c * 0.08
        ..color = theme.frame,
    );
    for (final e in board.ladders.entries) {
      _ladder(canvas, c, e.key, e.value);
    }
    var i = 0;
    for (final e in board.snakes.entries) {
      _snake(
          canvas, c, e.key, e.value, theme.snakes[i++ % theme.snakes.length]);
    }
  }

  void _cells(Canvas canvas, double c) {
    final n = theme.cells.length;
    for (var cell = 1; cell <= 100; cell++) {
      final g = cellGrid(cell);
      final rect = Rect.fromLTWH(g.col * c, (9 - g.row) * c, c, c);
      final base = theme.cells[(g.col + g.row) % n];
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(base, Colors.white, 0.18)!,
              Color.lerp(base, Colors.black, 0.06)!,
            ],
          ).createShader(rect),
      );
      canvas.drawRect(
        rect.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = theme.number.withValues(alpha: 0.12),
      );
      if (cell == 100) _finish(canvas, rect);
      if (showNumbers) _number(canvas, rect, cell);
    }
  }

  void _finish(Canvas canvas, Rect rect) {
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(colors: [
          const Color(0xFFFFE082),
          theme.accent.withValues(alpha: 0.9),
        ]).createShader(rect),
    );
    final star = Path();
    final ctr = rect.center + Offset(0, rect.height * 0.08);
    final r = rect.width * 0.3;
    for (var k = 0; k < 10; k++) {
      final a = -pi / 2 + k * pi / 5;
      final rr = k.isEven ? r : r * 0.45;
      final p = ctr + Offset(cos(a) * rr, sin(a) * rr);
      k == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
    }
    star.close();
    canvas.drawPath(star, Paint()..color = Colors.white.withValues(alpha: 0.9));
  }

  void _number(Canvas canvas, Rect rect, int cell) {
    final tp = TextPainter(
      text: TextSpan(
        text: '$cell',
        style: TextStyle(
          fontSize: rect.width * 0.26,
          fontWeight: FontWeight.w800,
          color: theme.number.withValues(alpha: cell == 100 ? 1 : 0.75),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
        canvas, rect.topLeft + Offset(rect.width * 0.08, rect.width * 0.04));
  }

  void _ladder(Canvas canvas, double c, int bottom, int top) {
    final a = unitCenter(bottom) * c;
    final b = unitCenter(top) * c;
    final d = b - a;
    final dir = d / d.distance;
    final perp = Offset(-dir.dy, dir.dx);
    final half = c * 0.2;
    final start = a - dir * c * 0.18;
    final end = b + dir * c * 0.18;
    final shadow = Offset(c * 0.06, c * 0.08);

    final rail = c * 0.075;
    final rung = c * 0.055;
    void rails(Paint p, Offset shift) {
      for (final s in [-1.0, 1.0]) {
        canvas.drawLine(
            start + perp * half * s + shift, end + perp * half * s + shift, p);
      }
    }

    void rungs(Paint p, Offset shift) {
      final len = (end - start).distance;
      final count = max(2, (len / (c * 0.38)).floor());
      for (var k = 1; k < count; k++) {
        final m = Offset.lerp(start, end, k / count)!;
        canvas.drawLine(m - perp * half + shift, m + perp * half + shift, p);
      }
    }

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..strokeWidth = rail
      ..strokeCap = StrokeCap.round;
    rungs(shadowPaint..strokeWidth = rung, shadow);
    rails(shadowPaint..strokeWidth = rail, shadow);

    final dark = Color.lerp(theme.ladderRail, Colors.black, 0.45)!;
    rungs(
        Paint()
          ..color = dark
          ..strokeWidth = rung + c * 0.03
          ..strokeCap = StrokeCap.round,
        Offset.zero);
    rungs(
        Paint()
          ..color = theme.ladderRung
          ..strokeWidth = rung
          ..strokeCap = StrokeCap.round,
        Offset.zero);
    rails(
        Paint()
          ..color = dark
          ..strokeWidth = rail + c * 0.035
          ..strokeCap = StrokeCap.round,
        Offset.zero);
    rails(
        Paint()
          ..color = theme.ladderRail
          ..strokeWidth = rail
          ..strokeCap = StrokeCap.round,
        Offset.zero);
    rails(
        Paint()
          ..color = Colors.white.withValues(alpha: 0.25)
          ..strokeWidth = rail * 0.3
          ..strokeCap = StrokeCap.round,
        -perp * rail * 0.2);
  }

  void _snake(
      Canvas canvas, double c, int head, int tail, (Color, Color) colors) {
    final pts = [for (final p in snakePath(head, tail)) p * c];
    final n = pts.length;
    double width(int i) => c * (0.30 - 0.22 * i / (n - 1));

    // Left and right edges of the body.
    final left = <Offset>[];
    final right = <Offset>[];
    for (var i = 0; i < n; i++) {
      final prev = pts[max(0, i - 1)];
      final next = pts[min(n - 1, i + 1)];
      final t = next - prev;
      final nrm = Offset(-t.dy, t.dx) / max(0.001, t.distance);
      left.add(pts[i] + nrm * width(i) / 2);
      right.add(pts[i] - nrm * width(i) / 2);
    }
    Path body([Offset shift = Offset.zero]) {
      final p = Path()..moveTo(left[0].dx + shift.dx, left[0].dy + shift.dy);
      for (final q in left.skip(1)) {
        p.lineTo(q.dx + shift.dx, q.dy + shift.dy);
      }
      p.lineTo(pts.last.dx + shift.dx, pts.last.dy + shift.dy);
      for (final q in right.reversed) {
        p.lineTo(q.dx + shift.dx, q.dy + shift.dy);
      }
      return p..close();
    }

    final (main, stripe) = colors;
    canvas.drawPath(body(Offset(c * 0.07, c * 0.09)),
        Paint()..color = Colors.black.withValues(alpha: 0.28));
    final outline = body();
    canvas.drawPath(outline, Paint()..color = main);

    // Diamond stripes along the back.
    final stripePaint = Paint()..color = stripe;
    for (var i = 4; i < n - 3; i += 5) {
      final q = Path()
        ..moveTo(left[i].dx, left[i].dy)
        ..lineTo(pts[i + 2].dx, pts[i + 2].dy)
        ..lineTo(right[i].dx, right[i].dy)
        ..lineTo(pts[i - 2].dx, pts[i - 2].dy)
        ..close();
      canvas.drawPath(q, stripePaint);
    }
    // Belly highlight.
    final hl = Path()..moveTo(pts[2].dx, pts[2].dy);
    for (var i = 3; i < n - 2; i++) {
      hl.lineTo(Offset.lerp(pts[i], left[i], 0.45)!.dx,
          Offset.lerp(pts[i], left[i], 0.45)!.dy);
    }
    canvas.drawPath(
      hl,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = c * 0.03
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.3),
    );
    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = c * 0.025
        ..color = Color.lerp(main, Colors.black, 0.5)!,
    );

    // Head, facing away from the body.
    final h = pts[0];
    final fwd = (pts[0] - pts[3]);
    final ang = atan2(fwd.dy, fwd.dx);
    canvas.save();
    canvas.translate(h.dx, h.dy);
    canvas.rotate(ang);
    final hw = c * 0.46, hh = c * 0.36;
    final tongue = Path()
      ..moveTo(hw * 0.4, 0)
      ..lineTo(hw * 0.85, 0)
      ..moveTo(hw * 0.85, 0)
      ..lineTo(hw * 1.0, -hh * 0.18)
      ..moveTo(hw * 0.85, 0)
      ..lineTo(hw * 1.0, hh * 0.18);
    canvas.drawPath(
      tongue,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = c * 0.03
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFD50000),
    );
    final headRect =
        Rect.fromCenter(center: Offset.zero, width: hw, height: hh);
    canvas.drawOval(headRect.shift(Offset(c * 0.03, c * 0.05)),
        Paint()..color = Colors.black.withValues(alpha: 0.25));
    canvas.drawOval(headRect, Paint()..color = main);
    canvas.drawOval(
      headRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = c * 0.025
        ..color = Color.lerp(main, Colors.black, 0.5)!,
    );
    for (final s in [-1.0, 1.0]) {
      final eye = Offset(hw * 0.12, s * hh * 0.24);
      canvas.drawCircle(eye, c * 0.065, Paint()..color = Colors.white);
      canvas.drawCircle(
          eye + Offset(c * 0.015, 0), c * 0.035, Paint()..color = Colors.black);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(BoardPainter old) =>
      old.board != board ||
      old.theme != theme ||
      old.showNumbers != showNumbers;
}
