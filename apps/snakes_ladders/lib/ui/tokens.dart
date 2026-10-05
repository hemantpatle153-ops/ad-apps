import 'dart:math';

import 'package:flutter/material.dart';

import '../game/themes.dart';

/// Live positions of every token, in board units. The game screen moves
/// them during animations; the painter redraws on every change.
class TokenLayer extends ChangeNotifier {
  TokenLayer(this.colors, List<Offset> start)
      : pos = List.of(start),
        lift = List.filled(start.length, 0.0),
        waiting = List.filled(start.length, false);

  /// Index into [tokenColors] per player.
  final List<int> colors;
  final List<Offset> pos;

  /// Height of a hop, in cells, for the bounce and shadow.
  final List<double> lift;

  /// Not on the board yet; drawn faded on cell 1.
  final List<bool> waiting;

  int? active;
  double pulse = 0;

  void move(int i, Offset p, {double lift = 0}) {
    pos[i] = p;
    this.lift[i] = lift;
    notifyListeners();
  }

  void setWaiting(int i, bool v) {
    waiting[i] = v;
    notifyListeners();
  }

  void setPulse(double v, int? who) {
    pulse = v;
    active = who;
    notifyListeners();
  }
}

class TokensPainter extends CustomPainter {
  TokensPainter(this.layer, {this.unit}) : super(repaint: layer);

  final TokenLayer layer;

  /// Pixel size of one board unit; defaults to a tenth of the width.
  final double? unit;

  @override
  void paint(Canvas canvas, Size size) {
    final c = unit ?? size.width / 10;
    final n = layer.pos.length;

    // Tokens resting on the same cell share it, arranged in a small ring.
    final groups = <int, List<int>>{};
    for (var i = 0; i < n; i++) {
      if (layer.lift[i] > 0.001) continue;
      final key = (layer.pos[i].dx * 10).round() * 1000 +
          (layer.pos[i].dy * 10).round();
      groups.putIfAbsent(key, () => []).add(i);
    }
    final place = List<Offset>.filled(n, Offset.zero);
    final scale = List<double>.filled(n, 1);
    for (final g in groups.values) {
      for (var k = 0; k < g.length; k++) {
        final i = g[k];
        if (g.length == 1) {
          place[i] = layer.pos[i];
        } else {
          final a = -pi / 2 + k * 2 * pi / g.length + pi / 4;
          place[i] = layer.pos[i] + Offset(cos(a), sin(a)) * 0.2;
          scale[i] = 0.72;
        }
      }
    }
    for (var i = 0; i < n; i++) {
      if (layer.lift[i] > 0.001) place[i] = layer.pos[i];
    }

    // Draw moving and active tokens last so they sit on top.
    final order = List.generate(n, (i) => i)
      ..sort((a, b) {
        int rank(int i) =>
            (layer.lift[i] > 0.001 ? 2 : 0) + (i == layer.active ? 1 : 0);
        return rank(a).compareTo(rank(b));
      });
    for (final i in order) {
      _pawn(canvas, c, place[i] * c, scale[i], i);
    }
  }

  void _pawn(Canvas canvas, double c, Offset at, double scale, int i) {
    final color = tokenColors[layer.colors[i]];
    final lift = layer.lift[i] * c;
    final r = c * 0.36 * scale * (1 + layer.lift[i] * 0.25);
    final alpha = layer.waiting[i] ? 0.55 : 1.0;

    // Shadow stays on the board while the token hops.
    canvas.drawOval(
      Rect.fromCenter(
        center: at + Offset(0, r * 0.75),
        width: r * 1.8 / (1 + layer.lift[i]),
        height: r * 0.7 / (1 + layer.lift[i]),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.3 * alpha),
    );

    final p = at - Offset(0, lift + r * 0.25);
    if (i == layer.active && !layer.waiting[i]) {
      final glow = r * (1.35 + 0.25 * layer.pulse);
      canvas.drawCircle(
        p,
        glow,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.55 * (1 - layer.pulse))
          ..style = PaintingStyle.stroke
          ..strokeWidth = c * 0.06,
      );
    }
    // Base of the pawn.
    final base = Rect.fromCenter(
        center: p + Offset(0, r * 0.65), width: r * 1.7, height: r * 0.7);
    canvas.drawOval(
        base,
        Paint()
          ..color =
              Color.lerp(color, Colors.black, 0.35)!.withValues(alpha: alpha));
    // Body.
    final body = Path()
      ..moveTo(p.dx - r * 0.8, p.dy + r * 0.6)
      ..quadraticBezierTo(
          p.dx - r * 0.45, p.dy - r * 0.1, p.dx - r * 0.3, p.dy - r * 0.35)
      ..lineTo(p.dx + r * 0.3, p.dy - r * 0.35)
      ..quadraticBezierTo(
          p.dx + r * 0.45, p.dy - r * 0.1, p.dx + r * 0.8, p.dy + r * 0.6)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(colors: [
          Color.lerp(color, Colors.white, 0.35)!.withValues(alpha: alpha),
          color.withValues(alpha: alpha),
          Color.lerp(color, Colors.black, 0.3)!.withValues(alpha: alpha),
        ]).createShader(Rect.fromCircle(center: p, radius: r)),
    );
    // Head.
    final head = p - Offset(0, r * 0.55);
    canvas.drawCircle(
      head,
      r * 0.48,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.4),
          colors: [
            Color.lerp(color, Colors.white, 0.6)!.withValues(alpha: alpha),
            color.withValues(alpha: alpha),
            Color.lerp(color, Colors.black, 0.35)!.withValues(alpha: alpha),
          ],
        ).createShader(Rect.fromCircle(center: head, radius: r * 0.48)),
    );
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1, c * 0.025)
      ..color = Colors.white.withValues(alpha: 0.85 * alpha);
    canvas.drawCircle(head, r * 0.48, outline);
    canvas.drawPath(body, outline);
  }

  @override
  bool shouldRepaint(TokensPainter old) => old.layer != layer;
}

/// A single pawn for player panels and menus.
class PawnIcon extends StatelessWidget {
  const PawnIcon({super.key, required this.color, this.size = 32});

  final int color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: TokensPainter(
            TokenLayer([color], [const Offset(0.5, 0.62)]),
            unit: size,
          ),
          size: Size.square(size),
        ),
      );
}
