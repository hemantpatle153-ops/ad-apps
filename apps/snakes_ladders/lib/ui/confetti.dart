import 'dart:math';

import 'package:flutter/material.dart';

/// Falling confetti for the winner. Ignores touches.
class Confetti extends StatefulWidget {
  const Confetti({super.key, required this.colors});

  final List<Color> colors;

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _Piece {
  _Piece(Random r, this.color)
      : x = r.nextDouble(),
        delay = r.nextDouble() * 0.5,
        speed = 0.5 + r.nextDouble() * 0.7,
        drift = (r.nextDouble() - 0.5) * 0.3,
        spin = (r.nextDouble() - 0.5) * 12,
        w = 6 + r.nextDouble() * 6,
        h = 4 + r.nextDouble() * 4;

  final double x, delay, speed, drift, spin, w, h;
  final Color color;
}

class _ConfettiState extends State<Confetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))
        ..forward();
  late final List<_Piece> _pieces;

  @override
  void initState() {
    super.initState();
    final r = Random();
    _pieces = [
      for (var i = 0; i < 140; i++)
        _Piece(r, widget.colors[i % widget.colors.length]),
    ];
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(_pieces, _c),
        ),
      );
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.anim) : super(repaint: anim);

  final List<_Piece> pieces;
  final Animation<double> anim;

  @override
  void paint(Canvas canvas, Size size) {
    final t = anim.value * 1.5;
    for (final p in pieces) {
      final lt = t - p.delay;
      if (lt <= 0) continue;
      final y = -20 + lt * p.speed * size.height * 1.2;
      if (y > size.height + 20) continue;
      final x =
          (p.x + p.drift * lt + sin(lt * 6 + p.x * 10) * 0.02) * size.width;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(lt * p.spin);
      canvas.drawRect(
        Rect.fromCenter(
            center: Offset.zero,
            width: p.w,
            height: p.h * cos(lt * 8).abs() + 1),
        Paint()
          ..color = p.color
              .withValues(alpha: (1 - anim.value).clamp(0.0, 1.0) * 0.4 + 0.6),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}
