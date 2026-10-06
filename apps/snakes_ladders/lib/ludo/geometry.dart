import 'dart:ui';

import 'engine.dart';

/// Board geometry on a 15 x 15 grid, in cell units (x = column, y = row,
/// cell centres at .5). Red's yard is top-left; the other colours are the
/// same layout turned a quarter clockwise each.
abstract final class Grid {
  static const size = 15;

  /// The 52 loop squares as (row, col), starting at red's start square.
  static final List<(int, int)> loop = _buildLoop();

  static List<(int, int)> _buildLoop() {
    final red = <(int, int)>[
      for (var c = 1; c <= 5; c++) (6, c),
      for (var r = 5; r >= 0; r--) (r, 6),
      (0, 7),
      (0, 8),
    ];
    final out = <(int, int)>[];
    for (var q = 0; q < 4; q++) {
      for (final cell in red) {
        out.add(turn(cell, q));
      }
    }
    return out;
  }

  /// Turns a cell a quarter clockwise [q] times.
  static (int, int) turn((int, int) cell, int q) {
    var (r, c) = cell;
    for (var i = 0; i < q % 4; i++) {
      (r, c) = (c, size - 1 - r);
    }
    return (r, c);
  }

  /// Home column square k (1..5) for [color].
  static (int, int) homeColumn(int color, int k) => turn((7, k), color);

  static Offset center((int, int) cell) =>
      Offset(cell.$2 + 0.5, cell.$1 + 0.5);

  /// Where a finished token rests inside its colour's triangle.
  static Offset homeSpot(int color, int token, int count) {
    final base = rotate(const Offset(6.55, 7.5), color);
    final mid = const Offset(7.5, 7.5);
    final along = rotate(const Offset(0, 1), color, about: Offset.zero);
    final spread = (token - (count - 1) / 2) * 0.42;
    return Offset.lerp(base, mid, 0.05)! + along * spread;
  }

  /// The four circles inside a yard, in cell units.
  static Offset yardSpot(int color, int token) {
    const spots = [
      Offset(1.85, 1.85),
      Offset(4.15, 1.85),
      Offset(1.85, 4.15),
      Offset(4.15, 4.15),
    ];
    return rotate(spots[token % 4], color);
  }

  /// Rotates a point a quarter clockwise [q] times about the board centre.
  static Offset rotate(Offset p, int q,
      {Offset about = const Offset(7.5, 7.5)}) {
    var d = p - about;
    for (var i = 0; i < q % 4; i++) {
      d = Offset(-d.dy, d.dx);
    }
    return about + d;
  }

  /// Where a token is drawn, before any view rotation.
  static Offset tokenSpot(int color, int progress, int token, int count) {
    if (progress == Route.yard) return yardSpot(color, token);
    if (progress == Route.home) return homeSpot(color, token, count);
    if (progress > Route.lastTrack) {
      return center(homeColumn(color, progress - Route.lastTrack));
    }
    return center(loop[Route.square(color, progress)!]);
  }
}
