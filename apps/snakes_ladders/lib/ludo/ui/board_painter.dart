import 'dart:math';

import 'package:flutter/material.dart';

import '../engine.dart';
import '../themes.dart';
import 'geometry.dart';

/// Paints the Ludo board. [view] turns it a quarter clockwise per step so
/// this phone's colour sits at the bottom-left, as in Ludo King.
class LudoBoardPainter extends CustomPainter {
  LudoBoardPainter(this.theme, {this.view = 0, this.activeColors});

  final LudoTheme theme;
  final int view;

  /// Colours in play; empty yards are drawn faded. Null means all four.
  final Set<int>? activeColors;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / Grid.size;
    final full = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(full, Radius.circular(u * 0.6));

    canvas.save();
    canvas.clipRRect(rr);
    canvas.drawRect(full, Paint()..color = theme.board);
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(view * pi / 2);
    canvas.translate(-size.width / 2, -size.height / 2);

    for (var c = 0; c < 4; c++) {
      _yard(canvas, u, c);
    }
    _track(canvas, u);
    _centre(canvas, u);
    canvas.restore();

    canvas.drawRRect(
      rr.deflate(u * 0.06),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 0.14
        ..color = theme.frame,
    );
  }

  Color _c(int color) => theme.colors[color];

  bool _active(int color) => activeColors?.contains(color) ?? true;

  Rect _cell((int, int) cell, double u) =>
      Rect.fromLTWH(cell.$2 * u, cell.$1 * u, u, u);

  void _yard(Canvas canvas, double u, int color) {
    final base = _c(color);
    final faded = !_active(color);
    final col = faded ? Color.lerp(base, theme.board, 0.55)! : base;
    final origin = Grid.rotate(const Offset(3, 3), color);
    final outer =
        Rect.fromCenter(center: origin * u, width: 6 * u, height: 6 * u);
    canvas.drawRect(
      outer,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(col, Colors.white, 0.18)!,
            col,
            Color.lerp(col, Colors.black, 0.18)!
          ],
        ).createShader(outer),
    );
    final inner = RRect.fromRectAndRadius(
        outer.deflate(u * 0.85), Radius.circular(u * 0.7));
    canvas.drawRRect(inner.shift(Offset(0, u * 0.08)),
        Paint()..color = Colors.black.withValues(alpha: 0.18));
    canvas.drawRRect(inner, Paint()..color = theme.track);
    for (var t = 0; t < 4; t++) {
      final p = Grid.yardSpot(color, t) * u;
      canvas.drawCircle(
          p, u * 0.62, Paint()..color = Color.lerp(col, Colors.black, 0.25)!);
      canvas.drawCircle(
        p,
        u * 0.55,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.3),
            colors: [Color.lerp(col, Colors.white, 0.35)!, col],
          ).createShader(Rect.fromCircle(center: p, radius: u * 0.55)),
      );
      canvas.drawCircle(
          p, u * 0.36, Paint()..color = Colors.black.withValues(alpha: 0.12));
    }
  }

  void _track(Canvas canvas, double u) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(0.8, u * 0.04)
      ..color = theme.line;
    for (var i = 0; i < Track.loop; i++) {
      final cell = Grid.loop[i];
      final r = _cell(cell, u);
      final startOf = i % 13 == 0 ? i ~/ 13 : null;
      final fill = startOf != null && _active(startOf)
          ? _c(startOf)
          : startOf != null
              ? Color.lerp(_c(startOf), theme.track, 0.5)!
              : theme.track;
      canvas.drawRect(r, Paint()..color = fill);
      canvas.drawRect(r, line);
      if (startOf != null) {
        _arrow(canvas, r.center, u, startOf, Colors.white);
      } else if (Track.isSafe(i)) {
        _star(canvas, r.center, u * 0.36, theme.star);
      }
    }
    for (var c = 0; c < 4; c++) {
      final col = _active(c) ? _c(c) : Color.lerp(_c(c), theme.track, 0.5)!;
      for (var k = 1; k <= 5; k++) {
        final r = _cell(Grid.homeColumn(c, k), u);
        canvas.drawRect(
          r,
          Paint()
            ..shader = LinearGradient(colors: [
              Color.lerp(col, Colors.white, 0.12)!,
              col,
            ]).createShader(r),
        );
        canvas.drawRect(r, line);
      }
      // Arrow on the square where this colour turns into its home column.
      final entry = _cell(Grid.loop[(Track.startOf(c) + 50) % 52], u);
      _arrow(canvas, entry.center, u, c, col, entry: true);
    }
  }

  /// A small arrow showing the way: on start squares it points along the
  /// track, on entry squares it points into the home column.
  void _arrow(Canvas canvas, Offset at, double u, int color, Color fill,
      {bool entry = false}) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    // Red's start square runs to the right; its entry turns right too.
    canvas.rotate(color * pi / 2);
    final s = u * 0.28;
    final path = Path()
      ..moveTo(s, 0)
      ..lineTo(-s * 0.6, -s * 0.8)
      ..lineTo(-s * 0.2, 0)
      ..lineTo(-s * 0.6, s * 0.8)
      ..close();
    if (entry) {
      canvas.drawPath(path, Paint()..color = fill.withValues(alpha: 0.9));
    } else {
      canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.fill);
      canvas.drawPath(
          path,
          Paint()
            ..color = Colors.black.withValues(alpha: 0.25)
            ..style = PaintingStyle.stroke
            ..strokeWidth = u * 0.03);
    }
    canvas.restore();
  }

  void _star(Canvas canvas, Offset c, double r, Color color) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final a = -pi / 2 + i * pi / 5;
      final rr = i.isEven ? r : r * 0.45;
      final p = c + Offset(cos(a), sin(a)) * rr;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.85));
  }

  void _centre(Canvas canvas, double u) {
    final mid = const Offset(7.5, 7.5) * u;
    final corners = [
      const Offset(6, 6),
      const Offset(9, 6),
      const Offset(9, 9),
      const Offset(6, 9),
    ];
    // Red's triangle is on the left (its home column arrives from the left),
    // then clockwise: green top, yellow right, blue bottom.
    final sides = {0: (3, 0), 1: (0, 1), 2: (1, 2), 3: (2, 3)};
    for (final e in sides.entries) {
      final a = corners[e.value.$1] * u, b = corners[e.value.$2] * u;
      final tri = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..lineTo(mid.dx, mid.dy)
        ..close();
      final col =
          _active(e.key) ? _c(e.key) : Color.lerp(_c(e.key), theme.track, 0.5)!;
      canvas.drawPath(
        tri,
        Paint()
          ..shader = RadialGradient(colors: [
            Color.lerp(col, Colors.white, 0.3)!,
            col,
          ]).createShader(Rect.fromCircle(center: mid, radius: 1.5 * u)),
      );
      canvas.drawPath(
          tri,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = u * 0.04
            ..color = Colors.white.withValues(alpha: 0.7));
    }
    // A small gold medallion in the middle.
    canvas.drawCircle(
        mid, u * 0.42, Paint()..color = Colors.black.withValues(alpha: 0.2));
    canvas.drawCircle(
      mid,
      u * 0.38,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.3),
          colors: [Color(0xFFFFF59D), Color(0xFFFFB300), Color(0xFFE65100)],
        ).createShader(Rect.fromCircle(center: mid, radius: u * 0.38)),
    );
    _star(canvas, mid, u * 0.24, Colors.white);
  }

  @override
  bool shouldRepaint(LudoBoardPainter old) =>
      old.theme != theme ||
      old.view != view ||
      old.activeColors?.length != activeColors?.length;
}
