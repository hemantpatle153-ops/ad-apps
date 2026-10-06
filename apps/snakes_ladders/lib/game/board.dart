import 'dart:math';

/// A 10x10 board: where every snake and ladder starts and ends.
///
/// Cells are numbered 1 to 100, left to right on the bottom row, then
/// snaking back and forth upward (the classic "boustrophedon" layout).
class BoardLayout {
  const BoardLayout({
    required this.id,
    required this.name,
    required this.description,
    required this.ladders,
    required this.snakes,
  });

  final String id;
  final String name;
  final String description;

  /// Ladder bottom -> ladder top.
  final Map<int, int> ladders;

  /// Snake head -> snake tail.
  final Map<int, int> snakes;

  static const int lastCell = 100;

  /// Where a token that lands on [cell] ends up (itself if nothing there).
  int jumpFrom(int cell) => ladders[cell] ?? snakes[cell] ?? cell;

  /// True if every snake goes down, every ladder goes up, no cell holds two
  /// things, and no jump lands on another jump's start.
  bool get isValid {
    final starts = {...ladders.keys, ...snakes.keys};
    if (starts.length != ladders.length + snakes.length) return false;
    for (final e in ladders.entries) {
      if (e.key < 1 || e.value > lastCell || e.value <= e.key) return false;
      if (starts.contains(e.value)) return false;
    }
    for (final e in snakes.entries) {
      if (e.key >= lastCell || e.value < 1 || e.value >= e.key) return false;
      if (starts.contains(e.value)) return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'ladders': {for (final e in ladders.entries) '${e.key}': e.value},
        'snakes': {for (final e in snakes.entries) '${e.key}': e.value},
      };

  factory BoardLayout.fromJson(Map<String, dynamic> j) => BoardLayout(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String? ?? '',
        ladders: {
          for (final e in (j['ladders'] as Map).entries)
            int.parse(e.key as String): e.value as int,
        },
        snakes: {
          for (final e in (j['snakes'] as Map).entries)
            int.parse(e.key as String): e.value as int,
        },
      );

  // Preset layouts were picked so that no two snakes or ladders cross or
  // touch, which keeps the board easy to read on a phone (see [isTidy]).
  static const classic = BoardLayout(
    id: 'classic',
    name: 'Classic',
    description: 'A balanced board for any game',
    ladders: {2: 21, 13: 48, 17: 37, 31: 50, 40: 78, 45: 85, 72: 91},
    snakes: {35: 5, 43: 3, 47: 7, 52: 12, 75: 66, 95: 68, 97: 57, 98: 61},
  );

  static const jungle = BoardLayout(
    id: 'jungle',
    name: 'Jungle Rush',
    description: 'More ladders, quicker games',
    ladders: {
      6: 46,
      11: 51,
      16: 25,
      28: 53,
      45: 83,
      62: 99,
      66: 85,
      68: 89,
      70: 90
    },
    snakes: {32: 9, 37: 4, 42: 3, 54: 34, 80: 40, 95: 74},
  );

  static const viper = BoardLayout(
    id: 'viper',
    name: 'Viper Pit',
    description: 'More snakes, long comebacks',
    ladders: {10: 31, 18: 57, 34: 73, 62: 99, 70: 92},
    snakes: {
      25: 7,
      42: 2,
      52: 12,
      55: 46,
      61: 21,
      65: 36,
      78: 63,
      95: 66,
      98: 76
    },
  );

  static const presets = [classic, jungle, viper];

  /// Closest two snakes or ladders may come, in cells, measured between
  /// the straight lines joining their ends.
  static const minGap = 1.0;

  /// True when no two snakes or ladders cross or come closer than [minGap].
  bool get isTidy {
    final segs = [
      for (final e in [...ladders.entries, ...snakes.entries])
        (cellCenter(e.key), cellCenter(e.value)),
    ];
    for (var i = 0; i < segs.length; i++) {
      for (var j = i + 1; j < segs.length; j++) {
        if (_segmentGap(segs[i].$1, segs[i].$2, segs[j].$1, segs[j].$2) <
            minGap) {
          return false;
        }
      }
    }
    return true;
  }

  /// A fresh, tidy board for the "Surprise" option.
  factory BoardLayout.random(int seed) {
    final rng = Random(seed);
    for (var attempt = 0; attempt < 50; attempt++) {
      final b = _tryRandom(rng, 7, 8);
      if (b != null) return b._named(seed);
    }
    return classic;
  }

  BoardLayout _named(int seed) => BoardLayout(
        id: 'random_$seed',
        name: 'Surprise board',
        description: 'A new layout every game',
        ladders: ladders,
        snakes: snakes,
      );

  static BoardLayout? _tryRandom(Random rng, int nLadders, int nSnakes) {
    final used = <int>{1, lastCell};
    final segs = <(({double x, double y}), ({double x, double y}))>[];
    final ladders = <int, int>{};
    final snakes = <int, int>{};

    bool fits(int a, int b) {
      if (used.contains(a) || used.contains(b)) return false;
      final ga = cellGrid(a), gb = cellGrid(b);
      final rows = (ga.row - gb.row).abs();
      if (rows < 1 || rows > 4 || (ga.col - gb.col).abs() > 2) return false;
      final pa = cellCenter(a), pb = cellCenter(b);
      for (final s in segs) {
        if (_segmentGap(pa, pb, s.$1, s.$2) < minGap) return false;
      }
      return true;
    }

    void add(Map<int, int> into, int a, int b) {
      into[a] = b;
      used
        ..add(a)
        ..add(b);
      segs.add((cellCenter(a), cellCenter(b)));
    }

    for (var tries = 0;
        tries < 4000 && (ladders.length < nLadders || snakes.length < nSnakes);
        tries++) {
      final ladderTurn = ladders.length < nLadders &&
          (snakes.length >= nSnakes || rng.nextBool());
      if (ladderTurn) {
        final a = 2 + rng.nextInt(84);
        final b = a + 9 + rng.nextInt(32);
        if (b < lastCell && fits(a, b)) add(ladders, a, b);
      } else {
        final h = 15 + rng.nextInt(85);
        final t = h - 9 - rng.nextInt(32);
        if (h < lastCell && t >= 2 && fits(h, t)) add(snakes, h, t);
      }
    }
    if (ladders.length < nLadders || snakes.length < nSnakes) return null;
    return BoardLayout(
      id: 'random',
      name: 'Surprise board',
      description: '',
      ladders: ladders,
      snakes: snakes,
    );
  }
}

/// Shortest distance between segments p1-p2 and q1-q2 (0 if they cross).
double _segmentGap(({double x, double y}) p1, ({double x, double y}) p2,
    ({double x, double y}) q1, ({double x, double y}) q2) {
  double cross(({double x, double y}) a, ({double x, double y}) b,
          ({double x, double y}) c) =>
      (c.y - a.y) * (b.x - a.x) - (b.y - a.y) * (c.x - a.x);
  if (cross(p1, q1, q2) * cross(p2, q1, q2) < 0 &&
      cross(p1, p2, q1) * cross(p1, p2, q2) < 0) {
    return 0;
  }
  double toSeg(({double x, double y}) p, ({double x, double y}) a,
      ({double x, double y}) b) {
    final dx = b.x - a.x, dy = b.y - a.y;
    final len = dx * dx + dy * dy;
    final t = len == 0
        ? 0.0
        : (((p.x - a.x) * dx + (p.y - a.y) * dy) / len).clamp(0.0, 1.0);
    final ex = p.x - a.x - t * dx, ey = p.y - a.y - t * dy;
    return sqrt(ex * ex + ey * ey);
  }

  return [
    toSeg(p1, q1, q2),
    toSeg(p2, q1, q2),
    toSeg(q1, p1, p2),
    toSeg(q2, p1, p2),
  ].reduce(min);
}

/// Column and row (0..9, row 0 at the bottom) of a cell 1..100.
({int col, int row}) cellGrid(int cell) {
  final i = cell - 1;
  final row = i ~/ 10;
  final inRow = i % 10;
  return (col: row.isEven ? inRow : 9 - inRow, row: row);
}

/// Centre of a cell in board units, where the board is 10 x 10 units with
/// (0, 0) at the top-left corner.
({double x, double y}) cellCenter(int cell) {
  final g = cellGrid(cell.clamp(1, 100));
  return (x: g.col + 0.5, y: 9 - g.row + 0.5);
}
