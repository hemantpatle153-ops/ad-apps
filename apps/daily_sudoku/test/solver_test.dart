import 'dart:math';

import 'package:daily_sudoku/sudoku_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sudoku_helpers.dart';

void main() {
  test('known solution grid is valid', () {
    expect(isValidSolution(knownSolution), isTrue);
  });

  group('canPlace on a solved grid with one hole', () {
    for (var i = 0; i < 81; i++) {
      test('cell $i (r${i ~/ 9} c${i % 9}) accepts only ${knownSolution[i]}', () {
        final g = List.of(knownSolution)..[i] = 0;
        for (var v = 1; v <= 9; v++) {
          expect(SudokuEngine.canPlace(g, i, v), v == knownSolution[i],
              reason: 'value $v');
        }
      });
    }
  });

  group('canPlace with a single digit on an empty grid', () {
    for (var p = 0; p < 81; p++) {
      final v = p % 9 + 1;
      test('$v at cell $p blocks exactly its 20 peers', () {
        final g = List.filled(81, 0)..[p] = v;
        var blocked = 0;
        for (var i = 0; i < 81; i++) {
          if (i == p) continue;
          final ok = SudokuEngine.canPlace(g, i, v);
          expect(ok, !arePeers(p, i), reason: 'cell $i');
          if (!ok) blocked++;
          // Other digits are never blocked by it.
          expect(SudokuEngine.canPlace(g, i, v % 9 + 1), isTrue);
        }
        expect(blocked, 20);
      });
    }
  });

  group('countSolutions', () {
    test('a full valid grid has one solution', () {
      expect(SudokuEngine.countSolutions(List.of(knownSolution)), 1);
    });
    for (var limit = 1; limit <= 6; limit++) {
      test('empty grid stops at limit $limit', () {
        expect(SudokuEngine.countSolutions(List.filled(81, 0), limit), limit);
      });
    }
    test('default limit is 2', () {
      expect(SudokuEngine.countSolutions(List.filled(81, 0)), 2);
    });
    // Contradictions: an empty cell with no candidate.
    for (var i = 0; i < 81; i += 4) {
      test('cell $i with no legal digit gives 0 solutions', () {
        // Fill cell i's row and column with all nine digits except via peers.
        final g = List.of(knownSolution)..[i] = 0;
        // Put the missing digit into a peer to make it impossible.
        final peer = List.generate(81, (k) => k).firstWhere((k) => arePeers(i, k));
        g[peer] = knownSolution[i];
        // Grid is now inconsistent but cell i has no candidate.
        expect(SudokuEngine.countSolutions(g), 0);
      });
    }
    // Unavoidable rectangle: swapping two digits in a 2x2 pattern -> 2 solutions.
    test('removing a deadly rectangle leaves 2 solutions', () {
      // In knownSolution, rows 0 & 1 (same band) cols 0 & 2? find a rectangle.
      final g = List.of(knownSolution);
      int? found;
      for (var r1 = 0; r1 < 9 && found == null; r1++) {
        for (var r2 = r1 + 1; r2 < 9 && found == null; r2++) {
          if (r1 ~/ 3 != r2 ~/ 3) continue;
          for (var c1 = 0; c1 < 9 && found == null; c1++) {
            for (var c2 = c1 + 1; c2 < 9 && found == null; c2++) {
              final a = g[r1 * 9 + c1], b = g[r1 * 9 + c2];
              if (g[r2 * 9 + c1] == b && g[r2 * 9 + c2] == a) {
                for (final k in [r1 * 9 + c1, r1 * 9 + c2, r2 * 9 + c1, r2 * 9 + c2]) {
                  g[k] = 0;
                }
                found = 1;
              }
            }
          }
        }
      }
      expect(found, isNotNull);
      expect(SudokuEngine.countSolutions(g, 5), 2);
    });
    final rng = Random(7);
    for (var t = 0; t < 30; t++) {
      final holes = 5 + t;
      final cells = (List.generate(81, (i) => i)..shuffle(rng)).take(holes).toList();
      test('solved grid with $holes random holes (#$t) has >= 1 solution and '
          'the original fills it', () {
        final g = List.of(knownSolution);
        for (final c in cells) {
          g[c] = 0;
        }
        expect(SudokuEngine.countSolutions(List.of(g), 1), 1);
        for (final c in cells) {
          expect(SudokuEngine.canPlace(g, c, knownSolution[c]), isTrue);
        }
      });
    }
  });

  group('daily puzzle', () {
    final start = DateTime(2025, 12, 20);
    for (var k = 0; k < 40; k++) {
      final day = DateTime(start.year, start.month, start.day + k * 3);
      final label =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      test('$label: stable through the day', () {
        final a = SudokuEngine.daily(day);
        final b = SudokuEngine.daily(day.add(const Duration(hours: 23, minutes: 59)));
        expect(b.givens, a.givens);
        expect(b.solution, a.solution);
      });
      test('$label: medium-sized, valid and unique', () {
        final p = SudokuEngine.daily(day);
        expect(givenCount(p.givens), Difficulty.medium.clues);
        expect(isValidSolution(p.solution), isTrue);
        expect(SudokuEngine.countSolutions(List.of(p.givens)), 1);
      });
      test('$label: equals SudokuEngine(yyyymmdd).generate(medium)', () {
        final seed = day.year * 10000 + day.month * 100 + day.day;
        expect(SudokuEngine.daily(day).givens,
            SudokuEngine(seed).generate(Difficulty.medium).givens);
      });
      test('$label: differs from the next day', () {
        final next = DateTime(day.year, day.month, day.day + 1);
        expect(SudokuEngine.daily(day).givens,
            isNot(SudokuEngine.daily(next).givens));
      });
    }
  });
}
