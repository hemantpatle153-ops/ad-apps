import 'package:daily_sudoku/sudoku_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sudoku_helpers.dart';

void main() {
  const seeds = 40;

  group('Difficulty', () {
    test('clue targets get strictly smaller as difficulty rises', () {
      final clues = Difficulty.values.map((d) => d.clues).toList();
      for (var i = 1; i < clues.length; i++) {
        expect(clues[i], lessThan(clues[i - 1]));
      }
    });
    const labels = {'easy': 'Easy', 'medium': 'Medium', 'hard': 'Hard', 'expert': 'Expert'};
    for (final d in Difficulty.values) {
      test('${d.name} has label ${labels[d.name]} and clues in 17..81', () {
        expect(d.label, labels[d.name]);
        expect(d.clues, inInclusiveRange(17, 81));
      });
    }
  });

  for (final d in Difficulty.values) {
    group('generate ${d.label}', () {
      for (var s = 0; s < seeds; s++) {
        final seed = s * 7919 + d.index;
        test('seed $seed: solution is a valid complete grid', () {
          expect(isValidSolution(puzzleFor(seed, d).solution), isTrue);
        });
        test('seed $seed: givens are 0 or match the solution', () {
          final p = puzzleFor(seed, d);
          expect(p.givens.length, 81);
          for (var i = 0; i < 81; i++) {
            expect(p.givens[i] == 0 || p.givens[i] == p.solution[i], isTrue,
                reason: 'cell $i');
          }
        });
        test('seed $seed: puzzle has exactly one solution', () {
          final p = puzzleFor(seed, d);
          expect(SudokuEngine.countSolutions(List.of(p.givens), 5), 1);
        });
        test('seed $seed: givens count fits ${d.clues}-clue target', () {
          final n = givenCount(puzzleFor(seed, d).givens);
          if (d == Difficulty.expert) {
            expect(n, inInclusiveRange(d.clues, Difficulty.hard.clues + 6));
          } else {
            expect(n, d.clues);
          }
        });
        test('seed $seed: same seed yields the same puzzle', () {
          final p = puzzleFor(seed, d);
          final q = SudokuEngine(seed).generate(d);
          expect(q.givens, p.givens);
          expect(q.solution, p.solution);
        });
        test('seed $seed: countSolutions leaves its input untouched', () {
          final g = List.of(puzzleFor(seed, d).givens);
          final copy = List.of(g);
          SudokuEngine.countSolutions(g);
          expect(g, copy);
        });
      }
    });
  }

  group('different seeds', () {
    for (var s = 0; s < 20; s++) {
      test('seeds $s and ${s + 1} give different easy solutions', () {
        expect(puzzleFor(s * 7919, Difficulty.easy).solution,
            isNot(puzzleFor((s + 1) * 7919, Difficulty.easy).solution));
      });
    }
  });
}
