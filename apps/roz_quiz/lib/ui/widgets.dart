import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/streak.dart';
import 'theme.dart';

enum OptionState { idle, selected, correct, wrong, dimmed }

/// One big answer button: letter badge, text and, after answering, a tick
/// or cross. At least 64 dp tall; grows with long text and large fonts.
class OptionButton extends StatelessWidget {
  const OptionButton({
    super.key,
    required this.index,
    required this.text,
    required this.state,
    required this.semanticLabel,
    this.onTap,
  });

  final int index;
  final String text;
  final OptionState state;
  final String semanticLabel;
  final VoidCallback? onTap;

  static const letters = ['A', 'B', 'C', 'D'];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = context.quiz;
    final (Color bg, Color fg, Color border, Color badgeBg, Color badgeFg) =
        switch (state) {
      OptionState.idle => (c.surfaceContainerLow, c.onSurface, c.outlineVariant,
          c.surfaceContainerHighest, c.onSurfaceVariant),
      OptionState.selected => (c.primaryContainer, c.onPrimaryContainer, c.primary,
          c.primary, c.onPrimary),
      OptionState.correct => (q.correctSoft, c.onSurface, q.correct, q.correct,
          q.onCorrect),
      OptionState.wrong => (q.wrongSoft, c.onSurface, q.wrong, q.wrong, q.onWrong),
      OptionState.dimmed => (c.surfaceContainerLow, c.onSurface.withValues(alpha: 0.6),
          c.outlineVariant.withValues(alpha: 0.5), c.surfaceContainerHighest,
          c.onSurfaceVariant.withValues(alpha: 0.6)),
    };
    final icon = switch (state) {
      OptionState.correct => Icons.check_circle,
      OptionState.wrong => Icons.cancel,
      _ => null,
    };
    return Semantics(
      button: true,
      selected: state == OptionState.selected,
      enabled: onTap != null,
      label: semanticLabel,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: border, width: state == OptionState.idle ? 1 : 2),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: badgeBg, shape: BoxShape.circle),
                      child: Text(letters[index],
                          style: TextStyle(
                              color: badgeFg, fontWeight: FontWeight.w800, fontSize: 16)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(text,
                          style: TextStyle(
                              color: fg,
                              fontSize: 17,
                              height: 1.3,
                              fontWeight: FontWeight.w500)),
                    ),
                    if (icon != null) ...[
                      const SizedBox(width: 8),
                      Icon(icon, color: state == OptionState.correct ? q.correct : q.wrong),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Centered icon, title, text and an optional button: empty lists,
/// offline and error states.
class StateMessage extends StatelessWidget {
  const StateMessage({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.colors.primaryContainer.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: context.colors.primary),
            ),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            if (body != null) ...[
              const SizedBox(height: 8),
              Text(body!,
                  textAlign: TextAlign.center,
                  style: context.text.bodyMedium
                      ?.copyWith(color: context.colors.onSurfaceVariant)),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// A small number-and-label card.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final col = color ?? context.colors.primary;
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: col, size: 22),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 2),
              Text(label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall
                      ?.copyWith(color: context.colors.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(text,
                    style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

/// Grid of StatTiles that wraps to two columns on narrow screens.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children, this.minTileWidth = 150});
  final List<Widget> children;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final cols = math.max(2, (c.maxWidth / minTileWidth).floor());
        final w = (c.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [for (final child in children) SizedBox(width: w, child: child)],
        );
      });
}

/// Circular score with an animated sweep.
class ScoreRing extends StatelessWidget {
  const ScoreRing({
    super.key,
    required this.fraction,
    required this.center,
    this.size = 168,
    this.color,
    this.semanticLabel,
  });

  final double fraction;
  final Widget center;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final col = color ?? context.colors.primary;
    return Semantics(
      label: semanticLabel,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: fraction.clamp(0, 1).toDouble()),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, v, child) => CustomPaint(
          painter: _RingPainter(v, col, context.colors.surfaceContainerHighest),
          child: SizedBox.square(dimension: size, child: Center(child: child)),
        ),
        child: center,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.color, this.track);
  final double v;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.085;
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, p..color = track);
    if (v > 0) {
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * v, false, p..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.v != v || old.color != color;
}

/// Thin rounded progress bar.
class SoftProgress extends StatelessWidget {
  const SoftProgress({super.key, required this.value, this.color, this.height = 8});
  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: value.clamp(0, 1).toDouble()),
          duration: const Duration(milliseconds: 350),
          builder: (context, v, _) => LinearProgressIndicator(
            value: v,
            minHeight: height,
            color: color ?? context.colors.primary,
            backgroundColor: context.colors.surfaceContainerHighest,
          ),
        ),
      );
}

/// GitHub-style calendar of days played, one column per week.
class Heatmap extends StatelessWidget {
  const Heatmap({
    super.key,
    required this.weeks,
    required this.semanticLabel,
    this.lessLabel = 'Less',
    this.moreLabel = 'More',
  });

  final List<List<HeatCell>> weeks;
  final String semanticLabel;
  final String lessLabel;
  final String moreLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.quiz.heat;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: LayoutBuilder(builder: (context, c) {
        const gap = 3.0;
        final cell = math.min(18.0, (c.maxWidth - gap * (weeks.length - 1)) / weeks.length);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var w = 0; w < weeks.length; w++) ...[
                  if (w > 0) const SizedBox(width: gap),
                  Column(children: [
                    for (var d = 0; d < 7; d++) ...[
                      if (d > 0) const SizedBox(height: gap),
                      Container(
                        width: cell,
                        height: cell,
                        decoration: BoxDecoration(
                          color: weeks[w][d].future
                              ? Colors.transparent
                              : colors[weeks[w][d].level],
                          borderRadius: BorderRadius.circular(cell * 0.25),
                        ),
                      ),
                    ],
                  ]),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(lessLabel, style: context.text.labelSmall),
              const SizedBox(width: 4),
              for (final col in colors)
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                      color: col, borderRadius: BorderRadius.circular(2.5)),
                ),
              const SizedBox(width: 4),
              Text(moreLabel, style: context.text.labelSmall),
            ]),
          ],
        );
      }),
    );
  }
}

/// Simple vertical bars with labels underneath (answers per day).
class MiniBarChart extends StatelessWidget {
  const MiniBarChart({
    super.key,
    required this.values,
    required this.highlights,
    required this.labels,
    required this.semanticLabel,
    this.height = 120,
  });

  /// Bar heights (any scale).
  final List<double> values;

  /// Part of each bar drawn in the strong colour (e.g. correct answers).
  final List<double> highlights;
  final List<String> labels;
  final String semanticLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Column(
        children: [
          SizedBox(
            height: height,
            width: double.infinity,
            child: CustomPaint(
              painter: _BarsPainter(values, highlights, context.colors.primary,
                  context.colors.primaryContainer),
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            for (final l in labels)
              Expanded(
                child: Text(l,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: context.text.labelSmall
                        ?.copyWith(color: context.colors.onSurfaceVariant, fontSize: 10)),
              ),
          ]),
        ],
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.values, this.highlights, this.strong, this.soft);
  final List<double> values;
  final List<double> highlights;
  final Color strong;
  final Color soft;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV = values.fold<double>(1, math.max);
    final slot = size.width / values.length;
    final w = slot * 0.6;
    for (var i = 0; i < values.length; i++) {
      final x = slot * i + (slot - w) / 2;
      final h = size.height * (values[i] / maxV);
      final hh = size.height * (math.min(highlights[i], values[i]) / maxV);
      final r = Radius.circular(w * 0.3);
      if (h > 0) {
        canvas.drawRRect(
            RRect.fromRectAndCorners(Rect.fromLTWH(x, size.height - h, w, h),
                topLeft: r, topRight: r),
            Paint()..color = soft);
      }
      if (hh > 0) {
        canvas.drawRRect(
            RRect.fromRectAndCorners(Rect.fromLTWH(x, size.height - hh, w, hh),
                topLeft: r, topRight: r),
            Paint()..color = strong);
      }
      if (h == 0) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(x, size.height - 3, w, 3), const Radius.circular(2)),
            Paint()..color = soft);
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.values != values || old.highlights != highlights || old.strong != strong;
}

/// A labelled horizontal bar: subject accuracy.
class AccuracyRow extends StatelessWidget {
  const AccuracyRow({
    super.key,
    required this.icon,
    required this.label,
    required this.fraction,
    required this.trailing,
    required this.color,
  });

  final IconData icon;
  final String label;
  final double fraction;
  final String trailing;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$label: $trailing',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                        child: Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600))),
                    Text(trailing, style: context.text.bodySmall),
                  ]),
                  const SizedBox(height: 4),
                  SoftProgress(value: fraction, color: color, height: 7),
                ],
              ),
            ),
          ]),
        ),
      );
}

/// Falling confetti, drawn once when the result screen opens.
class Confetti extends StatefulWidget {
  const Confetti({super.key, this.pieces = 70, this.seed = 7});
  final int pieces;
  final int seed;

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2600))
    ..forward();
  late final List<_Piece> _pieces;

  @override
  void initState() {
    super.initState();
    final r = math.Random(widget.seed);
    _pieces = List.generate(
        widget.pieces,
        (_) => _Piece(
              x: r.nextDouble(),
              delay: r.nextDouble() * 0.35,
              speed: 0.7 + r.nextDouble() * 0.6,
              drift: (r.nextDouble() - 0.5) * 0.25,
              spin: r.nextDouble() * math.pi * 4,
              size: 6 + r.nextDouble() * 6,
              color: _palette[r.nextInt(_palette.length)],
            ));
  }

  static const _palette = [
    Color(0xFF0E9F7E),
    Color(0xFFFFB547),
    Color(0xFFFF6B6E),
    Color(0xFF5B8CFF),
    Color(0xFFB39DFF),
    Color(0xFF3CCB86),
  ];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ExcludeSemantics(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => _c.isCompleted
                ? const SizedBox.expand()
                : CustomPaint(
                    size: Size.infinite, painter: _ConfettiPainter(_pieces, _c.value)),
          ),
        ),
      );
}

class _Piece {
  _Piece({
    required this.x,
    required this.delay,
    required this.speed,
    required this.drift,
    required this.spin,
    required this.size,
    required this.color,
  });
  final double x, delay, speed, drift, spin, size;
  final Color color;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.t);
  final List<_Piece> pieces;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in pieces) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final y = -20 + (size.height + 40) * local * p.speed;
      final x = size.width * (p.x + p.drift * local) +
          math.sin(local * math.pi * 3 + p.spin) * 12;
      final opacity = local > 0.85 ? (1 - local) / 0.15 : 1.0;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * local);
      canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5),
          Paint()..color = p.color.withValues(alpha: opacity));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

/// A rounded chip showing a small label (subject, difficulty, PYQ).
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.icon, this.color});
  final String text;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final col = color ?? context.colors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: col),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: col, fontWeight: FontWeight.w700, fontSize: 12)),
        ),
      ]),
    );
  }
}
