import 'dart:math';

import 'package:flutter/material.dart';

/// Live positions of every Ludo token, in board cell units. The game screen
/// moves them during animations; the painter redraws on every change.
class PieceLayer extends ChangeNotifier {
  PieceLayer(this.colors, List<Offset> start)
      : pos = List.of(start),
        lift = List.filled(start.length, 0.0),
        glow = List.filled(start.length, false);

  /// Fill colour per piece.
  final List<Color> colors;
  final List<Offset> pos;

  /// Height of a hop, in cells, for the bounce and shadow.
  final List<double> lift;

  /// Pieces the player may tap right now.
  final List<bool> glow;
  double pulse = 0;

  void move(int i, Offset p, {double lift = 0}) {
    pos[i] = p;
    this.lift[i] = lift;
    notifyListeners();
  }

  void setGlow(Iterable<int> which) {
    glow.fillRange(0, glow.length, false);
    for (final i in which) {
      glow[i] = true;
    }
    notifyListeners();
  }

  void setPulse(double v) {
    pulse = v;
    if (glow.contains(true)) notifyListeners();
  }

  /// The piece nearest [p] (cell units) among the glowing ones.
  int? hit(Offset p) {
    int? best;
    var bestD = 0.85;
    for (var i = 0; i < pos.length; i++) {
      if (!glow[i]) continue;
      final d = (pos[i] - p).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }
}

class PiecesPainter extends CustomPainter {
  PiecesPainter(this.layer, {this.unit}) : super(repaint: layer);

  final PieceLayer layer;

  /// Pixel size of one cell; defaults to a fifteenth of the width.
  final double? unit;

  @override
  void paint(Canvas canvas, Size size) {
    final c = unit ?? size.width / 15;
    final n = layer.pos.length;

    // Pieces resting on the same square share it in a small cluster.
    final groups = <int, List<int>>{};
    for (var i = 0; i < n; i++) {
      if (layer.lift[i] > 0.001) continue;
      final key = (layer.pos[i].dx * 10).round() * 1000 +
          (layer.pos[i].dy * 10).round();
      groups.putIfAbsent(key, () => []).add(i);
    }
    final place = List<Offset>.of(layer.pos);
    final scale = List<double>.filled(n, 1);
    for (final g in groups.values) {
      if (g.length < 2) continue;
      for (var k = 0; k < g.length; k++) {
        final a = -pi / 2 + k * 2 * pi / g.length + pi / 4;
        place[g[k]] = layer.pos[g[k]] + Offset(cos(a), sin(a)) * 0.2;
        scale[g[k]] = g.length > 2 ? 0.66 : 0.78;
      }
    }

    // Lower pieces first so overlapping ones look stacked; moving and
    // tappable pieces go on top.
    final order = List.generate(n, (i) => i)
      ..sort((a, b) {
        double rank(int i) =>
            (layer.lift[i] > 0.001 ? 100 : 0) +
            (layer.glow[i] ? 50 : 0) +
            place[i].dy;
        return rank(a).compareTo(rank(b));
      });
    for (final i in order) {
      paintPiece(canvas, place[i] * c, c * scale[i], layer.colors[i],
          lift: layer.lift[i] * c,
          glow: layer.glow[i] ? layer.pulse : null);
    }
  }

  @override
  bool shouldRepaint(PiecesPainter old) => old.layer != layer;
}

/// A glossy Ludo pin: round base, tapered body, ball on top.
void paintPiece(Canvas canvas, Offset at, double c, Color color,
    {double lift = 0, double? glow}) {
  final r = c * 0.36;
  canvas.drawOval(
    Rect.fromCenter(
        center: at + Offset(0, r * 0.75),
        width: r * 1.9 / (1 + lift / c),
        height: r * 0.75 / (1 + lift / c)),
    Paint()..color = Colors.black.withValues(alpha: 0.32),
  );
  final p = at - Offset(0, lift + r * 0.3);
  if (glow != null) {
    canvas.drawCircle(
      p,
      r * (1.25 + 0.45 * glow),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = c * 0.09
        ..color = Colors.white.withValues(alpha: 0.9 * (1 - glow)),
    );
    canvas.drawCircle(
      p + Offset(0, r * 0.2),
      r * 1.1,
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, c * 0.15),
    );
  }
  final dark = Color.lerp(color, Colors.black, 0.4)!;
  final light = Color.lerp(color, Colors.white, 0.45)!;
  final base = Rect.fromCenter(
      center: p + Offset(0, r * 0.7), width: r * 1.8, height: r * 0.75);
  canvas.drawOval(base, Paint()..color = dark);
  canvas.drawOval(base.shift(Offset(0, -r * 0.08)),
      Paint()..color = Color.lerp(color, Colors.black, 0.15)!);
  final body = Path()
    ..moveTo(p.dx - r * 0.82, p.dy + r * 0.62)
    ..quadraticBezierTo(
        p.dx - r * 0.42, p.dy - r * 0.05, p.dx - r * 0.26, p.dy - r * 0.42)
    ..lineTo(p.dx + r * 0.26, p.dy - r * 0.42)
    ..quadraticBezierTo(
        p.dx + r * 0.42, p.dy - r * 0.05, p.dx + r * 0.82, p.dy + r * 0.62)
    ..close();
  canvas.drawPath(
    body,
    Paint()
      ..shader = LinearGradient(colors: [light, color, dark])
          .createShader(Rect.fromCircle(center: p, radius: r)),
  );
  final head = p - Offset(0, r * 0.62);
  canvas.drawCircle(
    head,
    r * 0.5,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.4, -0.45),
        colors: [Colors.white, light, color, dark],
        stops: const [0, 0.25, 0.7, 1],
      ).createShader(Rect.fromCircle(center: head, radius: r * 0.5)),
  );
  final outline = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = max(1, c * 0.035)
    ..color = Colors.white;
  canvas.drawCircle(head, r * 0.5, outline);
  canvas.drawPath(body, outline);
}

/// A single piece for player panels and menus.
class PieceIcon extends StatelessWidget {
  const PieceIcon({super.key, required this.color, this.size = 32});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _IconPainter(color)),
      );
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => paintPiece(
      canvas, Offset(size.width / 2, size.height * 0.62), size.width, color);

  @override
  bool shouldRepaint(_IconPainter old) => old.color != color;
}
