import 'package:daily_sudoku/sudoku_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool validSolution(List<int> g) {
    for (var i = 0; i < 9; i++) {
      final row = <int>{}, col = <int>{}, box = <int>{};
      for (var k = 0; k < 9; k++) {
        row.add(g[i * 9 + k]);
        col.add(g[k * 9 + i]);
        box.add(g[(i ~/ 3 * 3 + k ~/ 3) * 9 + i % 3 * 3 + k % 3]);
      }
      if (row.length != 9 || col.length != 9 || box.length != 9) return false;
    }
    return true;
  }

  for (final d in Difficulty.values) {
    test('${d.label} puzzle has one solution matching the givens', () {
      final p = SudokuEngine(42).generate(d);
      expect(validSolution(p.solution), isTrue);
      for (var i = 0; i < 81; i++) {
        if (p.givens[i] != 0) expect(p.givens[i], p.solution[i]);
      }
      expect(SudokuEngine.countSolutions(List.of(p.givens)), 1);
      expect(p.givens.where((v) => v != 0).length, greaterThanOrEqualTo(d.clues));
    });
  }

  test('daily puzzle is the same for the same day', () {
    final a = SudokuEngine.daily(DateTime(2026, 10, 5));
    final b = SudokuEngine.daily(DateTime(2026, 10, 5, 23));
    final c = SudokuEngine.daily(DateTime(2026, 10, 6));
    expect(a.givens, b.givens);
    expect(a.givens, isNot(c.givens));
  });
}
