import 'dart:math';
import 'dart:ui';

import '../game/board.dart';

/// Board geometry in board units: the board is 10 x 10 units, (0, 0) at the
/// top-left. Painters multiply by the cell size in pixels.

Offset unitCenter(int cell) {
  if (cell <= 0) return const Offset(0.5, 9.5);
  final c = cellCenter(cell);
  return Offset(c.x, c.y);
}

/// Points along a snake's body from head (index 0) to tail (last index).
/// The token follows the same curve when it gets bitten.
List<Offset> snakePath(int head, int tail, {int samples = 64}) {
  final a = unitCenter(head);
  final b = unitCenter(tail);
  final d = b - a;
  final len = d.distance;
  final perp = Offset(-d.dy, d.dx) / len;
  // Longer snakes wiggle more; direction alternates per snake for variety.
  final waves = (len / 1.7).clamp(1.2, 4.0);
  final sign = head.isEven ? 1.0 : -1.0;
  return [
    for (var i = 0; i <= samples; i++)
      () {
        final t = i / samples;
        final taper = min(1.0, t * 5) * (1 - 0.6 * t);
        return a +
            d * t +
            perp * (sign * sin(t * waves * 2 * pi) * 0.36 * taper);
      }(),
  ];
}

/// Point at [t] (0..1) along a sampled path.
Offset pointOnPath(List<Offset> path, double t) {
  final f = t.clamp(0.0, 1.0) * (path.length - 1);
  final i = f.floor();
  if (i >= path.length - 1) return path.last;
  return Offset.lerp(path[i], path[i + 1], f - i)!;
}
