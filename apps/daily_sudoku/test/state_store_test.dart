import 'dart:convert';
import 'dart:math';

import 'package:daily_sudoku/game_state.dart';
import 'package:daily_sudoku/main.dart' show formatTime;
import 'package:daily_sudoku/sudoku_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/sudoku_helpers.dart';

GameState randomState(Random rng, int n) {
  final givens = [
    for (final v in knownSolution) rng.nextInt(3) == 0 ? 0 : v,
  ];
  final values = [
    for (var i = 0; i < 81; i++) givens[i] != 0 ? givens[i] : rng.nextInt(10),
  ];
  final notes = [
    for (var i = 0; i < 81; i++)
      {for (var v = 1; v <= 9; v++) if (rng.nextInt(4) == 0) v},
  ];
  return GameState(
    id: n.isEven ? 'daily_2026-01-${(n % 28 + 1).toString().padLeft(2, '0')}' : 'hard',
    title: 'Game "$n" é',
    givens: givens,
    solution: List.of(knownSolution),
    values: values,
    notes: notes,
    mistakes: rng.nextInt(4),
    seconds: rng.nextInt(100000),
    hintsUsed: rng.nextInt(6),
    completed: rng.nextBool(),
  );
}

void main() {
  group('formatTime', () {
    const cases = {
      0: '00:00', 1: '00:01', 9: '00:09', 10: '00:10', 59: '00:59', 60: '01:00',
      61: '01:01', 119: '01:59', 600: '10:00', 3599: '59:59', 3600: '60:00',
      5999: '99:59', 6000: '100:00', 36061: '601:01',
    };
    cases.forEach((s, want) {
      test('$s seconds -> $want', () => expect(formatTime(s), want));
    });
    for (var s = 0; s < 7200; s += 337) {
      test('$s seconds round-trips via mm:ss', () {
        final parts = formatTime(s).split(':');
        expect(parts[1].length, 2);
        expect(int.parse(parts[0]) * 60 + int.parse(parts[1]), s);
      });
    }
  });

  group('GameState', () {
    test('fromPuzzle starts with values = givens, empty notes, zero counters', () {
      final p = puzzleFor(1, Difficulty.easy);
      final g = GameState.fromPuzzle('easy', 'Easy', p);
      expect(g.values, p.givens);
      expect(identical(g.values, p.givens), isFalse);
      expect(g.notes.length, 81);
      expect(g.notes.every((n) => n.isEmpty), isTrue);
      expect([g.mistakes, g.seconds, g.hintsUsed], [0, 0, 0]);
      expect(g.completed, isFalse);
      expect(g.isSolved, isFalse);
    });
    test('notes sets are independent per cell', () {
      final g = GameState.fromPuzzle('e', 'E', puzzleFor(1, Difficulty.easy));
      g.notes[0].add(5);
      expect(g.notes[1], isEmpty);
    });
    test('isSolved when values equal solution', () {
      final g = GameState(id: 'x', title: 'X', givens: List.filled(81, 0),
          solution: List.of(knownSolution), values: List.of(knownSolution));
      expect(g.isSolved, isTrue);
    });
    for (var i = 0; i < 81; i += 5) {
      test('isSolved false when only cell $i is wrong', () {
        final values = List.of(knownSolution)..[i] = knownSolution[i] % 9 + 1;
        final g = GameState(id: 'x', title: 'X', givens: List.filled(81, 0),
            solution: List.of(knownSolution), values: values);
        expect(g.isSolved, isFalse);
      });
      test('isSolved false when only cell $i is empty', () {
        final values = List.of(knownSolution)..[i] = 0;
        final g = GameState(id: 'x', title: 'X', givens: List.filled(81, 0),
            solution: List.of(knownSolution), values: values);
        expect(g.isSolved, isFalse);
      });
    }
    final rng = Random(2026);
    for (var n = 0; n < 60; n++) {
      final s = randomState(rng, n);
      test('JSON round-trip of random state #$n', () {
        final back = GameState.fromJson(
            jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
        expect(back.id, s.id);
        expect(back.title, s.title);
        expect(back.givens, s.givens);
        expect(back.solution, s.solution);
        expect(back.values, s.values);
        expect(back.notes, s.notes);
        expect(back.mistakes, s.mistakes);
        expect(back.seconds, s.seconds);
        expect(back.hintsUsed, s.hintsUsed);
        expect(back.completed, s.completed);
        expect(back.isSolved, s.isSolved);
      });
    }
    test('fromJson defaults hintsUsed to 0 for older saves', () {
      final j = randomState(Random(1), 1).toJson()..remove('hintsUsed');
      expect(GameState.fromJson(j).hintsUsed, 0);
    });
  });

  group('Store.dayKey', () {
    final cases = {
      DateTime(2026, 1, 1): '2026-01-01',
      DateTime(2026, 12, 31): '2026-12-31',
      DateTime(2024, 2, 29): '2024-02-29',
      DateTime(999, 3, 4): '999-03-04',
      DateTime(2026, 10, 6, 23, 59): '2026-10-06',
      DateTime(2026, 10, 6, 0, 0, 1): '2026-10-06',
      DateTime(2030, 7, 9): '2030-07-09',
      DateTime(2026, 1, 32): '2026-02-01',
    };
    cases.forEach((d, want) {
      test('$d -> $want', () => expect(Store.dayKey(d), want));
    });
  });

  group('Store', () {
    Future<Store> fresh([Map<String, Object> init = const {}]) async {
      SharedPreferences.setMockInitialValues(init);
      return Store.open();
    }

    test('empty store has no current game, stats or streak', () async {
      final s = await fresh();
      expect(s.loadCurrent(), isNull);
      expect(s.solved, 0);
      expect(s.dailyDone, isEmpty);
      expect(s.dailyStreak(DateTime(2026, 10, 6)), 0);
      for (final d in Difficulty.values) {
        expect(s.bestSeconds(d.name), 0);
      }
    });

    final rng = Random(99);
    for (var n = 0; n < 10; n++) {
      final g = randomState(rng, n);
      test('save / load / clear current game #$n', () async {
        final s = await fresh();
        await s.saveCurrent(g);
        final back = s.loadCurrent()!;
        expect(back.values, g.values);
        expect(back.notes, g.notes);
        expect(back.seconds, g.seconds);
        await s.clearCurrent();
        expect(s.loadCurrent(), isNull);
      });
    }

    const corrupt = ['', 'not json', '[]', '{}', '{"id":1}', 'null', '42',
      '{"id":"a","title":"b"}', '{"id":"a","title":"b","givens":[],'
          '"solution":[],"values":[],"notes":[],"mistakes":"x","seconds":0,'
          '"completed":false}'];
    for (final c in corrupt) {
      test('corrupt saved game ${jsonEncode(c)} loads as null', () async {
        final s = await fresh({'current': c});
        expect(s.loadCurrent(), isNull);
      });
    }

    final winSeqs = [
      [100], [100, 90], [90, 100], [50, 50, 50], [300, 200, 250, 100, 400],
      [1], [7200, 3600, 1800, 900], [12, 11, 13, 10, 14, 9],
    ];
    for (final seq in winSeqs) {
      test('recordWin $seq keeps count and best time', () async {
        final s = await fresh();
        for (final t in seq) {
          await s.recordWin('hard', t);
        }
        expect(s.solved, seq.length);
        expect(s.bestSeconds('hard'), seq.reduce(min));
        expect(s.bestSeconds('easy'), 0);
      });
    }
    test('best time is tracked per level', () async {
      final s = await fresh();
      await s.recordWin('easy', 50);
      await s.recordWin('daily', 400);
      await s.recordWin('easy', 70);
      expect(s.bestSeconds('easy'), 50);
      expect(s.bestSeconds('daily'), 400);
      expect(s.solved, 3);
    });

    test('markDailyDone is idempotent', () async {
      final s = await fresh();
      await s.markDailyDone('2026-10-06');
      await s.markDailyDone('2026-10-06');
      await s.markDailyDone('2026-10-05');
      expect(s.dailyDone, {'2026-10-06', '2026-10-05'});
    });

    // Streak scenarios: offsets (days before "today") that are done.
    final today = DateTime(2026, 3, 2); // crosses Feb end
    final streaks = <List<int>, int>{
      []: 0,
      [0]: 1,
      [1]: 1,
      [2]: 0,
      [0, 1]: 2,
      [0, 1, 2, 3, 4]: 5,
      [1, 2, 3]: 3,
      [0, 2, 3]: 1,
      [1, 3, 4]: 1,
      [0, 1, 2, 4, 5, 6]: 3,
      [2, 3, 4]: 0,
      [for (var i = 0; i < 40; i++) i]: 40,
      [for (var i = 1; i <= 400; i++) i]: 400,
      [-1, 0]: 1,
    };
    streaks.forEach((offs, want) {
      test('streak with done days $offs ago is $want', () async {
        final keys = [
          for (final o in offs)
            Store.dayKey(DateTime(today.year, today.month, today.day - o)),
        ];
        final s = await fresh({'dailyDone': keys});
        expect(s.dailyStreak(today.add(const Duration(hours: 15))), want);
      });
    });
  });
}
