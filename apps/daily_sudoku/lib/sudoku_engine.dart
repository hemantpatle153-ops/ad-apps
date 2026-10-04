import 'dart:math';

enum Difficulty {
  easy('Easy', 38),
  medium('Medium', 32),
  hard('Hard', 27),
  expert('Expert', 24);

  const Difficulty(this.label, this.clues);
  final String label;

  /// Target number of given cells (fewer clues means harder).
  final int clues;
}

/// A puzzle: 81 cells, 0 = empty, plus its unique solution.
class Puzzle {
  Puzzle(this.givens, this.solution);
  final List<int> givens;
  final List<int> solution;
}

class SudokuEngine {
  SudokuEngine(int seed) : _rng = Random(seed);
  final Random _rng;

  static bool canPlace(List<int> g, int i, int v) {
    final r = i ~/ 9, c = i % 9;
    for (var k = 0; k < 9; k++) {
      if (g[r * 9 + k] == v || g[k * 9 + c] == v) return false;
    }
    final br = r ~/ 3 * 3, bc = c ~/ 3 * 3;
    for (var y = br; y < br + 3; y++) {
      for (var x = bc; x < bc + 3; x++) {
        if (g[y * 9 + x] == v) return false;
      }
    }
    return true;
  }

  bool _fill(List<int> g) {
    final i = g.indexOf(0);
    if (i < 0) return true;
    final nums = [1, 2, 3, 4, 5, 6, 7, 8, 9]..shuffle(_rng);
    for (final v in nums) {
      if (canPlace(g, i, v)) {
        g[i] = v;
        if (_fill(g)) return true;
        g[i] = 0;
      }
    }
    return false;
  }

  /// Counts solutions, stopping at [limit].
  static int countSolutions(List<int> g, [int limit = 2]) {
    var best = -1, bestCount = 10;
    for (var i = 0; i < 81; i++) {
      if (g[i] != 0) continue;
      var n = 0;
      for (var v = 1; v <= 9; v++) {
        if (canPlace(g, i, v)) n++;
      }
      if (n < bestCount) {
        bestCount = n;
        best = i;
        if (n == 0) return 0;
      }
    }
    if (best < 0) return 1;
    var total = 0;
    for (var v = 1; v <= 9 && total < limit; v++) {
      if (canPlace(g, best, v)) {
        g[best] = v;
        total += countSolutions(g, limit - total);
        g[best] = 0;
      }
    }
    return total;
  }

  Puzzle generate(Difficulty d) {
    final solution = List<int>.filled(81, 0);
    _fill(solution);
    final g = List<int>.from(solution);
    final order = List<int>.generate(81, (i) => i)..shuffle(_rng);
    var filled = 81;
    for (final i in order) {
      if (filled <= d.clues) break;
      final keep = g[i];
      g[i] = 0;
      if (countSolutions(List<int>.from(g)) != 1) {
        g[i] = keep;
      } else {
        filled--;
      }
    }
    return Puzzle(g, solution);
  }

  /// Same puzzle for everyone on the same calendar day.
  static Puzzle daily(DateTime day) {
    final seed = day.year * 10000 + day.month * 100 + day.day;
    return SudokuEngine(seed).generate(Difficulty.medium);
  }
}
