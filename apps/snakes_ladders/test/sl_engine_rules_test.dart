import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:snakes_ladders/game/board.dart';
import 'package:snakes_ladders/game/engine.dart';

import 'support/gen.dart';

/// Applies one roll on a fresh 2-player game where player 0 stands on
/// [from], and checks the result against the rules worked out by hand.
void checkRoll(BoardLayout board, GameRules rules, int from, int roll) {
  final g = slGame(board: board, rules: rules)..positions[0] = from;
  final r = g.play(roll);
  final six = roll == 6;
  final extra = rules.sixExtraTurn && six;
  final why = 'from $from roll $roll';

  expect(r.player, 0, reason: why);
  expect(r.roll, roll, reason: why);
  expect(r.from, from, reason: why);
  expect(g.rolls[0], 1, reason: why);
  expect(g.turns, 1, reason: why);
  expect(r.threeSixes, isFalse, reason: why);

  if (from == 0 && rules.sixToStart && !six) {
    expect(r.blocked, isTrue, reason: why);
    expect(r.steps, isEmpty, reason: why);
    expect(g.positions[0], 0, reason: why);
    expect(g.current, 1, reason: why);
    return;
  }

  var target = from + roll;
  if (target > 100) {
    if (rules.exactFinish) {
      expect(r.blocked, isTrue, reason: why);
      expect(r.end, from, reason: why);
      expect(r.extraTurn, extra, reason: why);
      expect(g.positions[0], from, reason: why);
      expect(g.current, extra ? 0 : 1, reason: why);
      expect(g.isOver, isFalse, reason: why);
      return;
    }
    target = 100;
  }
  final end = board.ladders[target] ?? board.snakes[target] ?? target;
  expect(r.blocked, isFalse, reason: why);
  expect(r.steps, [for (var c = from + 1; c <= target; c++) c], reason: why);
  expect(r.end, end, reason: why);
  expect(g.positions[0], end, reason: why);
  expect(r.hitLadder, board.ladders.containsKey(target), reason: why);
  expect(r.hitSnake, board.snakes.containsKey(target), reason: why);
  expect(r.jumpFrom, end == target ? null : target, reason: why);
  expect(g.laddersClimbed[0], r.hitLadder ? 1 : 0, reason: why);
  expect(g.snakeBites[0], r.hitSnake ? 1 : 0, reason: why);
  final won = end == 100;
  expect(r.won, won, reason: why);
  expect(g.winner, won ? 0 : null, reason: why);
  expect(r.extraTurn, extra && !won, reason: why);
  expect(g.current, (won || extra) ? 0 : 1, reason: why);
}

void main() {
  group('every square, every roll (classic board)', () {
    for (final rules in const [
      GameRules(),
      GameRules(exactFinish: false),
      GameRules(sixExtraTurn: false),
    ]) {
      for (var from = 0; from < 100; from++) {
        if (BoardLayout.classic.ladders.containsKey(from) ||
            BoardLayout.classic.snakes.containsKey(from)) {
          continue; // a token never rests on a snake head or ladder foot
        }
        test('${slRulesName(rules)}: from $from', () {
          for (var roll = 1; roll <= 6; roll++) {
            checkRoll(BoardLayout.classic, rules, from, roll);
          }
        });
      }
    }
  });

  group('six to start', () {
    for (var roll = 1; roll <= 6; roll++) {
      for (final board in BoardLayout.presets) {
        test('${board.name}: off the board, roll $roll', () {
          checkRoll(board, const GameRules(sixToStart: true), 0, roll);
          checkRoll(board,
              const GameRules(sixToStart: true, sixExtraTurn: false), 0, roll);
        });
      }
    }
  });

  group('six streaks', () {
    for (final players in [2, 3, 4]) {
      test('$players players: third six passes the turn without moving', () {
        final g = slGame(board: testBoard, players: players)..positions[0] = 50;
        expect(g.play(6).extraTurn, isTrue);
        expect(g.play(6).extraTurn, isTrue);
        final before = g.positions[0];
        final third = g.play(6);
        expect(third.threeSixes, isTrue);
        expect(third.blocked, isTrue);
        expect(third.steps, isEmpty);
        expect(g.positions[0], before);
        expect(g.current, 1);
        expect(g.sixStreak, 0);
      });

      test('$players players: a non-six resets the streak', () {
        final g = slGame(board: testBoard, players: players)..positions[0] = 50;
        g.play(6);
        expect(g.sixStreak, 1);
        g.play(2);
        expect(g.sixStreak, 0);
        expect(g.current, 1);
      });

      test('$players players: without the six rule sixes never chain', () {
        final g = slGame(
            board: testBoard,
            players: players,
            rules: const GameRules(sixExtraTurn: false))
          ..positions[0] = 50;
        for (var i = 0; i < players * 3; i++) {
          final who = g.current;
          final r = g.play(6);
          expect(r.extraTurn, isFalse);
          expect(r.threeSixes, isFalse);
          expect(g.current, (who + 1) % players);
        }
      });
    }

    test('overshooting six still earns the bonus roll', () {
      final g = slGame(board: testBoard)..positions[0] = 97;
      final r = g.play(6);
      expect(r.blocked, isTrue);
      expect(r.extraTurn, isTrue);
      expect(g.current, 0);
      expect(g.play(3).won, isTrue);
    });

    test('a winning six does not grant an extra roll', () {
      final g = slGame(board: testBoard)..positions[0] = 94;
      final r = g.play(6);
      expect(r.won, isTrue);
      expect(r.extraTurn, isFalse);
    });
  });

  group('turn order', () {
    for (final players in [2, 3, 4]) {
      test('$players players take turns in a circle', () {
        final g = slGame(board: testBoard, players: players)
          ..positions.fillRange(0, players, 20);
        for (var i = 0; i < players * 4; i++) {
          expect(g.current, i % players);
          expect(g.currentPlayer.name, 'P${i % players}');
          g.play(2);
        }
      });
    }
  });

  group('standings', () {
    final cases = <(List<int>, int?, List<int>)>[
      ([10, 50, 30], null, [1, 2, 0]),
      ([100, 50, 30], 0, [0, 1, 2]),
      ([40, 100, 70, 5], 1, [1, 2, 0, 3]),
      ([0, 0], null, [0, 1]),
      ([99, 98, 97, 96], null, [0, 1, 2, 3]),
      ([1, 2, 3, 4], null, [3, 2, 1, 0]),
    ];
    for (final (pos, winner, order) in cases) {
      test('positions $pos winner $winner', () {
        final g = GameEngine(
          board: testBoard,
          players: [
            for (var i = 0; i < pos.length; i++)
              Player(name: '$i', color: i, kind: PlayerKind.human),
          ],
          positions: List.of(pos),
          winner: winner,
        );
        expect(g.standings, order);
        expect(g.isOver, winner != null);
      });
    }
  });

  group('JSON pieces', () {
    for (final kind in PlayerKind.values) {
      for (var color = 0; color < 4; color++) {
        test('player $kind colour $color round trips', () {
          final p = Player(name: 'N$color', color: color, kind: kind);
          final q = Player.fromJson(p.toJson());
          expect(q.name, p.name);
          expect(q.color, color);
          expect(q.kind, kind);
          expect(q.isBot, kind == PlayerKind.bot);
        });
      }
    }
    for (final r in slRuleCombos) {
      test('rules ${slRulesName(r)} round trip', () {
        final q = GameRules.fromJson(r.toJson());
        expect(q.exactFinish, r.exactFinish);
        expect(q.sixExtraTurn, r.sixExtraTurn);
        expect(q.sixToStart, r.sixToStart);
      });
    }
    test('missing rule keys fall back to defaults', () {
      final r = GameRules.fromJson({});
      expect(r.exactFinish, isTrue);
      expect(r.sixExtraTurn, isTrue);
      expect(r.sixToStart, isFalse);
    });
    test('new games get distinct ids', () {
      final ids = {for (var i = 0; i < 50; i++) slGame().id};
      expect(ids.length, 50);
    });
    test('rollDie stays within 1..6 and hits every face', () {
      final g = slGame(seed: 3);
      final seen = <int>{};
      for (var i = 0; i < 600; i++) {
        final v = g.rollDie();
        expect(v, inInclusiveRange(1, 6));
        seen.add(v);
      }
      expect(seen, {1, 2, 3, 4, 5, 6});
    });
    test('seeded dice repeat', () {
      final a = GameEngine(
          board: testBoard, players: slGame().players, random: Random(9));
      final b = GameEngine(
          board: testBoard, players: slGame().players, random: Random(9));
      expect([for (var i = 0; i < 30; i++) a.rollDie()],
          [for (var i = 0; i < 30; i++) b.rollDie()]);
    });
  });
}

const testBoard = BoardLayout(
  id: 'plain',
  name: 'Plain',
  description: '',
  ladders: {3: 30},
  snakes: {90: 9},
);
