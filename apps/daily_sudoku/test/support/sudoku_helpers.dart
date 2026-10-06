import 'package:daily_sudoku/sudoku_engine.dart';

/// True if [g] is a complete grid where every row, column and box holds 1-9.
bool isValidSolution(List<int> g) {
  if (g.length != 81) return false;
  for (var i = 0; i < 9; i++) {
    final row = <int>{}, col = <int>{}, box = <int>{};
    for (var k = 0; k < 9; k++) {
      row.add(g[i * 9 + k]);
      col.add(g[k * 9 + i]);
      box.add(g[(i ~/ 3 * 3 + k ~/ 3) * 9 + i % 3 * 3 + k % 3]);
    }
    for (final s in [row, col, box]) {
      if (s.length != 9 || s.any((v) => v < 1 || v > 9)) return false;
    }
  }
  return true;
}

/// True if cells [a] and [b] share a row, column or box (a != b).
bool arePeers(int a, int b) {
  if (a == b) return false;
  final ar = a ~/ 9, ac = a % 9, br = b ~/ 9, bc = b % 9;
  return ar == br || ac == bc || (ar ~/ 3 == br ~/ 3 && ac ~/ 3 == bc ~/ 3);
}

int givenCount(List<int> g) => g.where((v) => v != 0).length;

final Map<String, Puzzle> _cache = {};

/// Memoised generator so several tests can inspect the same puzzle.
Puzzle puzzleFor(int seed, Difficulty d) =>
    _cache.putIfAbsent('$seed-${d.name}', () => SudokuEngine(seed).generate(d));

/// A fixed, hand-checked valid solution grid.
const List<int> knownSolution = [
  5, 3, 4, 6, 7, 8, 9, 1, 2, //
  6, 7, 2, 1, 9, 5, 3, 4, 8,
  1, 9, 8, 3, 4, 2, 5, 6, 7,
  8, 5, 9, 7, 6, 1, 4, 2, 3,
  4, 2, 6, 8, 5, 3, 7, 9, 1,
  7, 1, 3, 9, 2, 4, 8, 5, 6,
  9, 6, 1, 5, 3, 7, 2, 8, 4,
  2, 8, 7, 4, 1, 9, 6, 3, 5,
  3, 4, 5, 2, 8, 6, 1, 7, 9,
];
