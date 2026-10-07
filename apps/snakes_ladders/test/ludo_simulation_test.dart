import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:snakes_ladders/ludo/bot.dart';
import 'package:snakes_ladders/ludo/engine.dart';
import 'package:snakes_ladders/ludo/match.dart';

import 'support/gen.dart';

void checkState(LudoEngine g) {
  for (var p = 0; p < g.players.length; p++) {
    expect(g.tokens[p].length, g.rules.tokens);
    for (final t in g.tokens[p]) {
      expect(t, inInclusiveRange(Track.yard, Track.home));
    }
  }
  expect(g.finishOrder.toSet().length, g.finishOrder.length);
  if (!g.isOver) {
    expect(g.hasFinished(g.current), isFalse);
    for (final p in g.finishOrder) {
      expect(g.hasFinished(p), isTrue);
    }
  }
}

void main() {
  group('seeded bot-vs-bot Ludo games', () {
    var seed = 0;
    for (final players in [2, 3, 4]) {
      for (final tokens in [2, 4]) {
        for (final release in [true, false]) {
          for (final threeSixes in [true, false]) {
            for (var i = 0; i < 5; i++, seed++) {
              final s = seed;
              final rules = GameRules(
                  tokens: tokens,
                  sixToRelease: release,
                  threeSixes: threeSixes);
              test(
                  'seed $s: $players players, $tokens tokens, '
                  'sixToRelease=$release threeSixes=$threeSixes', () {
                final rnd = Random(s);
                final g = ludoGame(players: players, rules: rules);
                final log = <GameAction>[];
                var captureEvents = 0;
                var sixesRolled = List.filled(players, 0);
                var guard = 0;
                while (!g.isOver && guard++ < 40000) {
                  final p = g.current;
                  final v = 1 + rnd.nextInt(6);
                  final roll = RollAction(p, v);
                  expect(roll.validFor(g), isTrue);
                  log.add(roll);
                  if (v == 6) sixesRolled[p]++;
                  final r = g.roll(v);
                  expect(r.player, p);
                  if (r.passes) {
                    expect(g.phase, Phase.roll);
                    checkState(g);
                    continue;
                  }
                  expect(r.movable, g.movableFor(p, v));
                  expect(g.phase, Phase.move);
                  final homeCol = [
                    for (final t in g.tokens[p]) t > Track.lastTrack
                  ];
                  final t = chooseMove(g, r.movable, random: rnd);
                  expect(r.movable, contains(t));
                  final mv = MoveAction(p, t);
                  expect(mv.validFor(g), isTrue);
                  log.add(mv);
                  final m = g.move(t);
                  captureEvents += m.captures.length;
                  expect(m.player, p);
                  // A token in its home column or home never goes backwards.
                  for (var k = 0; k < g.tokens[p].length; k++) {
                    if (homeCol[k]) {
                      expect(g.tokens[p][k], greaterThan(Track.lastTrack));
                    }
                  }
                  for (final c in m.captures) {
                    expect(c.player, isNot(p));
                    expect(c.from, inInclusiveRange(0, Track.lastTrack));
                    expect(g.tokens[c.player][c.token], Track.yard);
                  }
                  if (!m.gameOver && !m.extraTurn) expect(g.current, isNot(p));
                  if (m.extraTurn) expect(g.current, p);
                  checkState(g);
                }
                expect(g.isOver, isTrue, reason: 'game must end');
                expect(
                    g.standings.toSet(), {for (var p = 0; p < players; p++) p});
                expect(g.finishOrder.length, players);
                expect(g.hasFinished(g.winner!), isTrue);
                expect(g.captures.reduce((a, b) => a + b), captureEvents);
                expect(g.sixes, sixesRolled);
                // Everyone but the last has every token home.
                for (final p in g.finishOrder.take(players - 1)) {
                  expect(g.hasFinished(p), isTrue);
                }

                // Another phone applying the logged actions ends identical.
                final copy = ludoGame(players: players, rules: rules);
                for (final a in log) {
                  final b = GameAction.fromJson(
                      jsonDecode(jsonEncode(a.toJson()))
                          as Map<String, dynamic>);
                  expect(b.validFor(copy), isTrue);
                  switch (b) {
                    case RollAction(:final value):
                      copy.roll(value);
                    case MoveAction(:final token):
                      copy.move(token);
                  }
                }
                expect(jsonEncode(copy.toJson()), jsonEncode(g.toJson()));
                final restored = LudoEngine.fromJson(
                    jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
                expect(jsonEncode(restored.toJson()), jsonEncode(g.toJson()));
                expect(restored.isOver, isTrue);
              });
            }
          }
        }
      }
    }
  });

  group('saving mid-game', () {
    for (var s = 0; s < 30; s++) {
      test('seed $s: a game saved halfway plays on identically', () {
        final rnd = Random(500 + s);
        final g = ludoGame(players: 2 + s % 3);
        for (var i = 0; i < 60 + s * 3 && !g.isOver; i++) {
          final r = g.roll(1 + rnd.nextInt(6));
          if (!r.passes) g.move(chooseMove(g, r.movable, random: rnd));
        }
        final copy = LudoEngine.fromJson(
            jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
        expect(copy.phase, g.phase);
        expect(copy.current, g.current);
        expect(copy.tokens, g.tokens);
        final d1 = Random(s), d2 = Random(s);
        for (var i = 0; i < 40 && !g.isOver; i++) {
          final a = g.roll(1 + d1.nextInt(6));
          final b = copy.roll(1 + d2.nextInt(6));
          expect(b.movable, a.movable);
          if (!a.passes) {
            g.move(a.movable.last);
            copy.move(b.movable.last);
          }
        }
        expect(jsonEncode(copy.toJson()), jsonEncode(g.toJson()));
      });
    }
  });

  group('bot choices', () {
    LudoEngine table(List<int> mine, List<int> theirs, int roll) {
      final g = ludoGame(); // blue (start 39) vs green (start 13)
      g.tokens[0] = List.of(mine);
      g.tokens[1] = List.of(theirs);
      g.roll(roll);
      return g;
    }

    for (var seed = 0; seed < 5; seed++) {
      test('seed $seed: prefers a capture', () {
        // Token 0 at p2 + 3 -> p5 (square 44); green p31 sits on 44.
        final g = table([2, 20, -1, -1], [31, -1, -1, -1], 3);
        expect(chooseMove(g, g.movableFor(0, 3), random: Random(seed)), 0);
      });

      test('seed $seed: prefers getting a token home', () {
        final g = table([20, 52, -1, -1], [-1, -1, -1, -1], 4);
        expect(chooseMove(g, g.movableFor(0, 4), random: Random(seed)), 1);
      });

      test('seed $seed: brings a token out on a six', () {
        final g = table([20, -1, -1, -1], [-1, -1, -1, -1], 6);
        expect(chooseMove(g, g.movableFor(0, 6), random: Random(seed)),
            isIn([1, 2, 3]));
      });

      test('seed $seed: runs from a nearby threat', () {
        // Token 1 at p10 (square 49) with green p33 (square 46) behind it;
        // a 4 carries it to square 1, out of reach.
        final g = table([20, 10, -1, -1], [33, -1, -1, -1], 4);
        expect(chooseMove(g, g.movableFor(0, 4), random: Random(seed)), 1);
      });

      test('seed $seed: only option is taken', () {
        final g = table([20, -1, -1, -1], [-1, -1, -1, -1], 3);
        expect(chooseMove(g, g.movableFor(0, 3), random: Random(seed)), 0);
      });
    }
  });

  group('stale and bad actions', () {
    final g = ludoGame()..tokens[0] = [10, -1, -1, -1];
    final cases = <String, (GameAction, bool)>{
      'roll by the player to move': (const RollAction(0, 4), true),
      'roll out of turn': (const RollAction(1, 4), false),
      'roll of 0': (const RollAction(0, 0), false),
      'roll of 7': (const RollAction(0, 7), false),
      'move before rolling': (const MoveAction(0, 0), false),
    };
    cases.forEach((name, c) {
      test('roll phase: $name', () => expect(c.$1.validFor(g), c.$2));
    });

    for (var t = 0; t < 4; t++) {
      test('move phase after a 3: token $t', () {
        final h = ludoGame()..tokens[0] = [10, -1, 40, 56];
        h.roll(3);
        expect(MoveAction(0, t).validFor(h), t == 0 || t == 2);
        expect(MoveAction(1, t).validFor(h), isFalse);
        expect(RollAction(0, 3).validFor(h), isFalse);
      });
    }

    test('nothing is valid once the game is over', () {
      final h = ludoGame()..tokens[0] = List.filled(4, Track.home);
      expect(const RollAction(0, 3).validFor(h), isFalse);
      expect(const RollAction(1, 3).validFor(h), isFalse);
    });
  });
}
