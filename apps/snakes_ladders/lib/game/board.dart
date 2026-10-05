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

  static const classic = BoardLayout(
    id: 'classic',
    name: 'Classic',
    description: 'The board everyone grew up with',
    ladders: {
      1: 38,
      4: 14,
      9: 31,
      21: 42,
      28: 84,
      36: 44,
      51: 67,
      71: 91,
      80: 100
    },
    snakes: {
      16: 6,
      47: 26,
      49: 11,
      56: 53,
      62: 19,
      64: 60,
      87: 24,
      93: 73,
      95: 75,
      98: 78,
    },
  );

  static const jungle = BoardLayout(
    id: 'jungle',
    name: 'Jungle Rush',
    description: 'Lots of ladders, quick games',
    ladders: {
      3: 22,
      5: 8,
      11: 26,
      20: 29,
      27: 56,
      37: 58,
      42: 63,
      50: 69,
      61: 81,
      72: 91,
      79: 97,
    },
    snakes: {
      17: 4,
      19: 7,
      34: 12,
      54: 35,
      66: 45,
      76: 57,
      88: 65,
      94: 74,
      99: 41
    },
  );

  static const viper = BoardLayout(
    id: 'viper',
    name: 'Viper Pit',
    description: 'More snakes, long comebacks',
    ladders: {6: 27, 13: 35, 23: 44, 40: 59, 57: 77, 63: 84, 78: 96},
    snakes: {
      25: 3,
      32: 10,
      46: 14,
      52: 29,
      58: 39,
      69: 33,
      74: 54,
      83: 61,
      89: 51,
      92: 71,
      97: 64,
      99: 80,
    },
  );

  static const presets = [classic, jungle, viper];

  /// A fresh, fair board for the "Surprise" option.
  factory BoardLayout.random(int seed) {
    final rng = Random(seed);
    final used = <int>{1, lastCell};
    final ladders = <int, int>{};
    final snakes = <int, int>{};

    int pick(int lo, int hi) {
      for (var i = 0; i < 200; i++) {
        final c = lo + rng.nextInt(hi - lo + 1);
        if (!used.contains(c)) return c;
      }
      return -1;
    }

    while (ladders.length < 8) {
      final bottom = pick(2, 80);
      if (bottom < 0) break;
      final rowsUp = 1 + rng.nextInt(4);
      final top = min(99, bottom + rowsUp * 10 + rng.nextInt(9) - 4);
      if (top <= bottom + 5 || used.contains(top)) continue;
      used
        ..add(bottom)
        ..add(top);
      ladders[bottom] = top;
    }
    while (snakes.length < 9) {
      final head = pick(20, 99);
      if (head < 0) break;
      final rowsDown = 1 + rng.nextInt(4);
      final tail = max(2, head - rowsDown * 10 - rng.nextInt(9) + 4);
      if (tail >= head - 5 || used.contains(tail)) continue;
      used
        ..add(head)
        ..add(tail);
      snakes[head] = tail;
    }
    return BoardLayout(
      id: 'random_$seed',
      name: 'Surprise board',
      description: 'A new layout every game',
      ladders: ladders,
      snakes: snakes,
    );
  }
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
