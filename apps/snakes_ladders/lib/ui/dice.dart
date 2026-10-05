import 'dart:math';

import 'package:flutter/material.dart';

/// A tappable die that tumbles before landing on its value.
///
/// The game screen owns the outcome: it calls [DiceViewState.roll] with the
/// value already decided by the engine and waits for the animation.
class DiceView extends StatefulWidget {
  const DiceView({
    super.key,
    required this.value,
    required this.color,
    this.size = 60,
    this.enabled = false,
    this.dim = false,
    this.onTap,
  });

  final int value;
  final Color color;
  final double size;

  /// Glows and bounces gently to invite a tap.
  final bool enabled;

  /// Greyed out while it is another player's turn.
  final bool dim;
  final VoidCallback? onTap;

  @override
  State<DiceView> createState() => DiceViewState();
}

class DiceViewState extends State<DiceView> with TickerProviderStateMixin {
  late final AnimationController _roll = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 750));
  late final AnimationController _idle = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
  final _rng = Random();
  int _face = 1;
  int _lastSwap = 0;

  @override
  void initState() {
    super.initState();
    _face = widget.value;
    _roll.addListener(_tumble);
    if (widget.enabled) _idle.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(DiceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_idle.isAnimating) {
      _idle.repeat(reverse: true);
    } else if (!widget.enabled && _idle.isAnimating) {
      _idle.stop();
      _idle.value = 0;
    }
    if (!_roll.isAnimating && oldWidget.value != widget.value) {
      _face = widget.value;
    }
  }

  void _tumble() {
    // Swap faces quickly at first, then slower as the die settles.
    final v = _roll.value;
    final step = (v * 14).floor();
    if (step != _lastSwap && v < 0.85) {
      _lastSwap = step;
      var f = _face;
      while (f == _face) {
        f = 1 + _rng.nextInt(6);
      }
      setState(() => _face = f);
    }
  }

  /// Plays the tumble and lands on [value].
  Future<void> roll(int value) async {
    _lastSwap = -1;
    try {
      await _roll.forward(from: 0).orCancel;
    } on TickerCanceled {
      return;
    }
    if (mounted) setState(() => _face = value);
  }

  @override
  void dispose() {
    _roll.dispose();
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.enabled ? widget.onTap : null,
      child: AnimatedBuilder(
        animation: Listenable.merge([_roll, _idle]),
        builder: (context, _) {
          final v = _roll.value;
          final rolling = _roll.isAnimating;
          final spin = rolling ? (1 - v) * (1 - v) * 4 * pi : 0.0;
          final hop = rolling ? sin(v * pi * 3) * (1 - v) * 0.35 : 0.0;
          final breathe = widget.enabled ? _idle.value * 0.06 : 0.0;
          return Transform.translate(
            offset: Offset(0, -hop.abs() * widget.size * 0.5),
            child: Transform.rotate(
              angle: spin,
              child: Transform.scale(
                scale: 1 + breathe + (rolling ? 0.1 : 0),
                child: SizedBox.square(
                  dimension: widget.size,
                  child: CustomPaint(
                    painter: _DiePainter(
                      face: _face,
                      color: widget.color,
                      glow: widget.enabled ? 0.5 + _idle.value * 0.5 : 0,
                      dim: widget.dim && !rolling,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DiePainter extends CustomPainter {
  _DiePainter({
    required this.face,
    required this.color,
    required this.glow,
    required this.dim,
  });

  final int face;
  final Color color;
  final double glow;
  final bool dim;

  static const _pips = {
    1: [(0.5, 0.5)],
    2: [(0.27, 0.27), (0.73, 0.73)],
    3: [(0.27, 0.27), (0.5, 0.5), (0.73, 0.73)],
    4: [(0.27, 0.27), (0.73, 0.27), (0.27, 0.73), (0.73, 0.73)],
    5: [(0.27, 0.27), (0.73, 0.27), (0.5, 0.5), (0.27, 0.73), (0.73, 0.73)],
    6: [
      (0.27, 0.25),
      (0.73, 0.25),
      (0.27, 0.5),
      (0.73, 0.5),
      (0.27, 0.75),
      (0.73, 0.75),
    ],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(
        rect.deflate(s * 0.04), Radius.circular(s * 0.2));
    if (glow > 0) {
      canvas.drawRRect(
        rr.inflate(s * 0.06),
        Paint()
          ..color = color.withValues(alpha: 0.55 * glow)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.08),
      );
    }
    canvas.drawRRect(
      rr.shift(Offset(0, s * 0.05)),
      Paint()..color = Colors.black.withValues(alpha: 0.3),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFE9E9EF), Color(0xFFCFCFD8)],
        ).createShader(rect),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.05
        ..color = color,
    );
    final pipColor =
        face == 1 ? const Color(0xFFD32F2F) : const Color(0xFF212121);
    final pr = s * (face == 1 ? 0.12 : 0.085);
    for (final (x, y) in _pips[face]!) {
      final c = Offset(x * s, y * s);
      canvas.drawCircle(
          c + Offset(0, s * 0.012), pr, Paint()..color = Colors.white);
      canvas.drawCircle(c, pr, Paint()..color = pipColor);
    }
    if (dim) {
      canvas.drawRRect(
          rr, Paint()..color = Colors.black.withValues(alpha: 0.25));
    }
  }

  @override
  bool shouldRepaint(_DiePainter old) =>
      old.face != face ||
      old.color != color ||
      old.glow != glow ||
      old.dim != dim;
}
