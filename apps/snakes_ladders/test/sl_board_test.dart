import 'package:flutter_test/flutter_test.dart';
import 'package:snakes_ladders/game/board.dart';
import 'package:snakes_ladders/ui/geometry.dart';

void expectSameLayout(BoardLayout a, BoardLayout b) {
  expect(a.id, b.id);
  expect(a.name, b.name);
  expect(a.description, b.description);
  expect(a.ladders, b.ladders);
  expect(a.snakes, b.snakes);
}

void main() {
  group('cell numbering', () {
    for (var cell = 1; cell <= 100; cell++) {
      test('cell $cell sits on the right row and column', () {
        final g = cellGrid(cell);
        expect(g.row, (cell - 1) ~/ 10);
        expect(g.col, inInclusiveRange(0, 9));
        // Even rows run left to right, odd rows right to left.
        final inRow = (cell - 1) % 10;
        expect(g.col, g.row.isEven ? inRow : 9 - inRow);
        final c = cellCenter(cell);
        expect(c.x, g.col + 0.5);
        expect(c.y, 9 - g.row + 0.5);
        if (cell < 100) {
          // Consecutive cells always touch: the path never jumps.
          final n = cellGrid(cell + 1);
          expect((n.col - g.col).abs() + (n.row - g.row).abs(), 1);
        }
        final u = unitCenter(cell);
        expect(u, Offset(c.x, c.y));
      });
    }

    test('every cell has its own square', () {
      final seen = {for (var c = 1; c <= 100; c++) cellGrid(c)};
      expect(seen.length, 100);
    });

    for (final (input, expected) in const [
      (0, 1),
      (-5, 1),
      (101, 100),
      (250, 100)
    ]) {
      test('cellCenter clamps out-of-range cell $input to $expected', () {
        expect(cellCenter(input), cellCenter(expected));
      });
    }

    test('a token not on the board waits beside cell 1', () {
      expect(unitCenter(0), const Offset(0.5, 9.5));
    });
  });

  group('preset boards', () {
    for (final b in BoardLayout.presets) {
      test('${b.name} is valid and tidy', () {
        expect(b.isValid, isTrue);
        expect(b.isTidy, isTrue);
      });

      test('${b.name} ladders climb and snakes bite via jumpFrom', () {
        for (var c = 1; c <= 100; c++) {
          final to = b.jumpFrom(c);
          if (b.ladders.containsKey(c)) {
            expect(to, greaterThan(c));
          } else if (b.snakes.containsKey(c)) {
            expect(to, lessThan(c));
          } else {
            expect(to, c);
          }
        }
      });

      test('${b.name} survives a JSON round trip', () {
        expectSameLayout(BoardLayout.fromJson(b.toJson()), b);
      });

      test('${b.name} has no snake on 100 and nothing on cell 1 or 100', () {
        expect(b.snakes.containsKey(100), isFalse);
        expect(b.ladders.containsKey(100), isFalse);
        expect(b.jumpFrom(100), 100);
      });

      for (final e in b.snakes.entries) {
        test('${b.name} snake ${e.key}->${e.value} path runs head to tail', () {
          final path = snakePath(e.key, e.value);
          expect(path.length, 65);
          expect((path.first - unitCenter(e.key)).distance, lessThan(1e-9));
          // The tail tapers but still wiggles a little (at most 0.22 * 0.4).
          expect((path.last - unitCenter(e.value)).distance,
              lessThanOrEqualTo(0.22 * 0.4 + 1e-9));
          expect(pointOnPath(path, 0), path.first);
          expect(pointOnPath(path, 1), path.last);
          expect(pointOnPath(path, -3), path.first);
          expect(pointOnPath(path, 7), path.last);
          for (final p in path) {
            expect(p.dx, inInclusiveRange(-0.5, 10.5));
            expect(p.dy, inInclusiveRange(-0.5, 10.5));
          }
        });
      }
    }

    test('preset ids are unique', () {
      expect(BoardLayout.presets.map((b) => b.id).toSet().length,
          BoardLayout.presets.length);
    });
  });

  group('isValid rejects broken layouts', () {
    BoardLayout b(Map<int, int> ladders, Map<int, int> snakes) => BoardLayout(
        id: 'x', name: 'x', description: '', ladders: ladders, snakes: snakes);
    final cases = <String, BoardLayout>{
      'ladder going down': b({50: 20}, {}),
      'ladder going nowhere': b({50: 50}, {}),
      'ladder past 100': b({95: 101}, {}),
      'ladder from cell 0': b({0: 20}, {}),
      'snake going up': b({}, {20: 50}),
      'snake going nowhere': b({}, {40: 40}),
      'snake on 100': b({}, {100: 3}),
      'snake below cell 1': b({}, {20: 0}),
      'snake and ladder share a start': b({30: 60}, {30: 5}),
      'ladder ends on a snake head': b({10: 40}, {40: 2}),
      'snake ends on a ladder foot': b({5: 25}, {60: 5}),
      'ladder ends on another ladder foot': b({3: 22, 22: 60}, {}),
      'snake ends on another snake head': b({}, {80: 50, 50: 10}),
    };
    cases.forEach((name, layout) {
      test(name, () => expect(layout.isValid, isFalse));
    });

    final good = <String, BoardLayout>{
      'empty board': b({}, {}),
      'one ladder to 100': b({90: 100}, {}),
      'one snake to 1': b({}, {99: 1}),
      'ladder and snake sharing an end cell': b({10: 40}, {70: 40}),
    };
    good.forEach((name, layout) {
      test('accepts $name', () => expect(layout.isValid, isTrue));
    });

    test('two crossing ladders are not tidy', () {
      // 1 -> 22 and 2 -> 21 form an X over the bottom-left corner.
      expect(b({1: 22, 2: 21}, {}).isTidy, isFalse);
    });

    test('two ladders far apart are tidy', () {
      expect(b({1: 21, 10: 30}, {}).isTidy, isTrue);
    });
  });

  group('surprise boards', () {
    for (var seed = 0; seed < 260; seed++) {
      test('seed $seed gives a fair, tidy, repeatable board', () {
        final board = BoardLayout.random(seed);
        expect(board.isValid, isTrue);
        expect(board.isTidy, isTrue);
        if (board.id == 'classic') return; // fallback is the classic board
        expect(board.id, 'random_$seed');
        expect(board.name, 'Surprise board');
        expect(board.ladders.length, 7);
        expect(board.snakes.length, 8);
        for (final e in [...board.ladders.entries, ...board.snakes.entries]) {
          expect(e.key, inExclusiveRange(1, 100));
          expect(e.value, inExclusiveRange(1, 100));
          final a = cellGrid(e.key), z = cellGrid(e.value);
          final rows = (a.row - z.row).abs();
          expect(rows, inInclusiveRange(1, 4), reason: '${e.key}->${e.value}');
          expect((a.col - z.col).abs(), lessThanOrEqualTo(2));
        }
        for (final e in board.ladders.entries) {
          expect(board.jumpFrom(e.key), greaterThan(e.key));
        }
        for (final e in board.snakes.entries) {
          expect(board.jumpFrom(e.key), lessThan(e.key));
        }
        // Same seed, same board.
        expectSameLayout(BoardLayout.random(seed), board);
        expectSameLayout(BoardLayout.fromJson(board.toJson()), board);
      });
    }

    test('different seeds give different boards', () {
      final keys = {
        for (var s = 0; s < 40; s++)
          (BoardLayout.random(s).ladders.toString() +
              BoardLayout.random(s).snakes.toString())
      };
      expect(keys.length, greaterThan(35));
    });
  });

  group('board JSON', () {
    test('missing description falls back to empty', () {
      final b = BoardLayout.fromJson({
        'id': 'a',
        'name': 'A',
        'ladders': {'3': 30},
        'snakes': {'40': 4},
      });
      expect(b.description, '');
      expect(b.ladders, {3: 30});
      expect(b.snakes, {40: 4});
    });

    test('keys are written as strings', () {
      final j = BoardLayout.classic.toJson();
      expect((j['ladders'] as Map).keys.every((k) => k is String), isTrue);
      expect((j['snakes'] as Map).keys.every((k) => k is String), isTrue);
    });
  });
}
