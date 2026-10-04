import 'dart:math';

import 'package:flutter/material.dart';

import 'data.dart';

/// Category breakdown (donut) and spend per day of the month (bars).
class InsightsView extends StatelessWidget {
  const InsightsView({
    super.key,
    required this.items,
    required this.settings,
    required this.month,
  });

  final List<Expense> items;
  final Settings settings;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (items.isEmpty) {
      return const Center(child: Text('Nothing to show for this month yet.'));
    }
    final byCat = <String, int>{};
    for (final e in items) {
      byCat[e.category] = (byCat[e.category] ?? 0) + e.amount;
    }
    final cats = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = items.fold<int>(0, (a, e) => a + e.amount);

    final days = DateTime(month.year, month.month + 1, 0).day;
    final perDay = List<int>.filled(days, 0);
    for (final e in items) {
      perDay[e.date.day - 1] += e.amount;
    }
    final now = DateTime.now();
    final elapsed = month.year == now.year && month.month == now.month
        ? now.day
        : days;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('By category', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: CustomPaint(
            painter: _DonutPainter([
              for (final c in cats)
                (Category.byId(c.key).color, c.value / total),
            ]),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(settings.money(total),
                      style: theme.textTheme.titleLarge),
                  const Text('total'),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final c in cats)
          ListTile(
            dense: true,
            leading: Icon(Category.byId(c.key).icon,
                color: Category.byId(c.key).color),
            title: Text(Category.byId(c.key).label),
            subtitle: LinearProgressIndicator(
              value: c.value / total,
              color: Category.byId(c.key).color,
            ),
            trailing: Text(
                '${settings.money(c.value)}  ${(c.value * 100 / total).round()}%'),
          ),
        const SizedBox(height: 24),
        Text('Per day', style: theme.textTheme.titleMedium),
        Text('Average ${settings.money(total ~/ max(elapsed, 1))} a day'),
        const SizedBox(height: 12),
        SizedBox(
          height: 160,
          child: CustomPaint(
            size: Size.infinite,
            painter: _BarsPainter(perDay, theme.colorScheme.primary,
                theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.slices);
  final List<(Color, double)> slices;

  @override
  void paint(Canvas canvas, Size size) {
    final r = min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: r - 14);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 28;
    var start = -pi / 2;
    for (final (color, frac) in slices) {
      final sweep = frac * 2 * pi;
      canvas.drawArc(rect, start, sweep, false, paint..color = color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.slices != slices;
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.values, this.color, this.labelColor);
  final List<int> values;
  final Color color;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    final top = values.fold<int>(0, max);
    if (top == 0) return;
    const labelH = 16.0;
    final h = size.height - labelH;
    final w = size.width / values.length;
    final paint = Paint()..color = color;
    for (var i = 0; i < values.length; i++) {
      final bh = h * values[i] / top;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * w + w * .15, h - bh, w * .7, bh),
          const Radius.circular(2),
        ),
        paint,
      );
      final day = i + 1;
      if (day == 1 || day % 5 == 0) {
        final tp = TextPainter(
          text: TextSpan(
              text: '$day', style: TextStyle(fontSize: 10, color: labelColor)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(i * w + (w - tp.width) / 2, h + 2));
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.values != values;
}
