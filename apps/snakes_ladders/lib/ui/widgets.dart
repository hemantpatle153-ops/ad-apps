import 'dart:math';

import 'package:flutter/material.dart';

import '../game/themes.dart';

/// Theme gradient with slowly drifting dice and stars behind every screen.
class GameBackground extends StatefulWidget {
  const GameBackground({super.key, required this.theme, required this.child});

  final BoardTheme theme;
  final Widget child;

  @override
  State<GameBackground> createState() => _GameBackgroundState();
}

class _GameBackgroundState extends State<GameBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 40))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: t.background,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: _PatternPainter(_c, t.accent)),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter(this.anim, this.accent) : super(repaint: anim);

  final Animation<double> anim;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(3);
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.06);
    final star = Paint()..color = accent.withValues(alpha: 0.14);
    for (var i = 0; i < 18; i++) {
      final x = rng.nextDouble() * size.width;
      final speed = 0.3 + rng.nextDouble() * 0.7;
      final y =
          (rng.nextDouble() * size.height + anim.value * size.height * speed) %
                  (size.height + 80) -
              40;
      final s = 18 + rng.nextDouble() * 26;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(anim.value * 2 * pi * (rng.nextBool() ? 1 : -1) + i);
      if (i.isEven) {
        final r = RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: s, height: s),
            Radius.circular(s * 0.22));
        canvas.drawRRect(r, paint);
        final pip = Paint()..color = Colors.white.withValues(alpha: 0.1);
        for (final o in const [
          Offset(-0.25, -0.25),
          Offset(0, 0),
          Offset(0.25, 0.25)
        ]) {
          canvas.drawCircle(o * s, s * 0.08, pip);
        }
      } else {
        final p = Path();
        for (var k = 0; k < 10; k++) {
          final a = -pi / 2 + k * pi / 5;
          final rr = k.isEven ? s * 0.45 : s * 0.2;
          final q = Offset(cos(a) * rr, sin(a) * rr);
          k == 0 ? p.moveTo(q.dx, q.dy) : p.lineTo(q.dx, q.dy);
        }
        canvas.drawPath(p..close(), star);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PatternPainter old) => old.accent != accent;
}

/// Fade and slight zoom between screens, gentler than the platform slide.
Route<T> gameRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, a, __, child) {
        final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: c,
          child: ScaleTransition(
            scale: Tween(begin: 0.96, end: 1.0).animate(c),
            child: child,
          ),
        );
      },
    );

/// A rounded light panel on top of the background.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.theme,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final BoardTheme theme;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: theme.panel.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
                color: Colors.black26, blurRadius: 12, offset: Offset(0, 5)),
          ],
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: theme.onPanel),
          child: IconTheme.merge(
            data: IconThemeData(color: theme.onPanel),
            child: ListTileTheme.merge(
              textColor: theme.onPanel,
              iconColor: theme.onPanel,
              child: child,
            ),
          ),
        ),
      );
}

/// White heading over the background.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
          ),
        ),
      );
}

/// "5 min ago" style label.
String timeAgo(DateTime t, [DateTime? now]) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays == 1) return 'yesterday';
  return '${d.inDays} days ago';
}

/// A big glossy menu button.
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.color,
    required this.icon,
    required this.label,
    required this.sub,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Color.lerp(color, Colors.black, 0.3)!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(colors: [color, dark]),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.6), width: 2),
            boxShadow: [
              BoxShadow(color: dark, offset: const Offset(0, 5)),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 34),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w900)),
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
