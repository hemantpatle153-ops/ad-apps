import 'dart:math';

import 'package:flutter/material.dart';

import '../themes.dart';

/// Theme gradient with a soft radial glow and faint drifting shapes.
class LudoBackground extends StatefulWidget {
  const LudoBackground({super.key, required this.theme, required this.child});

  final LudoTheme theme;
  final Widget child;

  @override
  State<LudoBackground> createState() => _LudoBackgroundState();
}

class _LudoBackgroundState extends State<LudoBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 50))
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
        gradient: RadialGradient(
          center: const Alignment(0, -0.35),
          radius: 1.2,
          colors: [
            Color.lerp(t.background.first, Colors.white, 0.12)!,
            t.background.first,
            t.background.last,
          ],
          stops: const [0, 0.45, 1],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: _Drift(_c)),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _Drift extends CustomPainter {
  _Drift(this.anim) : super(repaint: anim);

  final Animation<double> anim;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(11);
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.05);
    for (var i = 0; i < 12; i++) {
      final x = rng.nextDouble() * size.width;
      final speed = 0.2 + rng.nextDouble() * 0.5;
      final y =
          (rng.nextDouble() * size.height + anim.value * size.height * speed) %
                  (size.height + 80) -
              40;
      final s = 16 + rng.nextDouble() * 22;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(anim.value * 2 * pi + i);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: s, height: s),
              Radius.circular(s * 0.25)),
          paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_Drift old) => false;
}

/// A rounded light card on top of the background.
class LudoPanel extends StatelessWidget {
  const LudoPanel({
    super.key,
    required this.theme,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final LudoTheme theme;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: theme.panel.withValues(alpha: 0.96),
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
class LudoHeading extends StatelessWidget {
  const LudoHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w900,
            shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
          ),
        ),
      );
}

/// Screen scaffold for menus: background, back button and title.
class LudoPage extends StatelessWidget {
  const LudoPage({
    super.key,
    required this.theme,
    required this.title,
    required this.children,
    this.bottom,
  });

  final LudoTheme theme;
  final String title;
  final List<Widget> children;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) => Scaffold(
        bottomNavigationBar: bottom,
        body: LudoBackground(
          theme: theme,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
                  child: Row(
                    children: [
                      const BackButton(color: Colors.white),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: children,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// Chunky rounded button with a pressed-in bottom edge.
class ChunkyButton extends StatelessWidget {
  const ChunkyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = const Color(0xFF43A047),
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = onPressed == null ? Colors.grey : color;
    final dark = Color.lerp(c, Colors.black, 0.3)!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color.lerp(c, Colors.white, 0.15)!, c],
            ),
            boxShadow: [BoxShadow(color: dark, offset: const Offset(0, 4))],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, color: Colors.white),
                const SizedBox(width: 8),
              ],
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A selectable square tile (player count, colour).
class ChoiceTile extends StatelessWidget {
  const ChoiceTile({
    required this.selected,
    required this.color,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.all(4),
          height: 56,
          constraints: const BoxConstraints(minWidth: 56),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.18) : null,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selected ? color : Colors.transparent, width: 3),
          ),
          child: child,
        ),
      );
}
