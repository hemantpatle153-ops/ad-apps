import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:snakes_ladders/game/board.dart';
import 'package:snakes_ladders/game/engine.dart';

import 'support/gen.dart';

/// Plays a whole seeded game, checking the engine's invariants after every
/// roll. Returns the rolls used so the game can be replayed.
List<int> playOut(GameEngine g, Random dice, {int limit = 30000}) {
  final rolls = <int>[];
  final n = g.players.length;
  var streak = 0;
  while (!g.isOver && rolls.length < limit) {
    final who = g.current;
    final before = List.of(g.positions);
    final roll = 1 + dice.nextInt(6);
    rolls.add(roll);
    final r = g.play(roll);
    streak = roll == 6 ? streak + 1 : 0;

    expect(r.player, who);
    expect(r.from, before[who]);
    // Only the mover's token changes.
    for (var p = 0; p < n; p++) {
      if (p != who) expect(g.positions[p], before[p]);
      expect(g.positions[p], inInclusiveRange(0, 100));
    }
    expect(r.end, g.positions[who]);
    if (r.steps.isNotEmpty) {
      expect(r.steps.first, r.from + 1);
      for (var i = 1; i < r.steps.length; i++) {
        expect(r.steps[i], r.steps[i - 1] + 1);
      }
      expect(r.end, g.board.jumpFrom(r.steps.last));
      expect(r.steps.length, lessThanOrEqualTo(roll));
    } else {
      expect(r.blocked, isTrue);
      expect(r.end, r.from);
    }
    // Nobody ever rests on a snake head or a ladder foot.
    expect(g.board.jumpFrom(g.positions[who]), g.positions[who]);
    if (r.threeSixes) {
      expect(g.rules.sixExtraTurn, isTrue);
      expect(streak, 3);
    }
    if (r.won) {
      expect(g.positions[who], 100);
      expect(g.winner, who);
    } else {
      expect(g.positions[who], lessThan(100));
      final expectNext = r.extraTurn ? who : (who + 1) % n;
      expect(g.current, expectNext);
    }
    if (!r.extraTurn || r.won) streak = 0;
    expect(g.sixStreak, lessThan(3));
  }
  return rolls;
}

void main() {
  group('seeded full games', () {
    var seed = 0;
    for (final rules in slRuleCombos) {
      for (var i = 0; i < 24; i++, seed++) {
        final s = seed;
        final players = 2 + s % 3;
        final board = s % 4 == 0
            ? BoardLayout.presets[s % 3]
            : BoardLayout.random(1000 + s);
        test('seed $s, $players players, ${board.id}, ${slRulesName(rules)}',
            () {
          final g =
              slGame(board: board, players: players, rules: rules, bots: true);
          final rolls = playOut(g, Random(s));
          expect(g.isOver, isTrue, reason: 'game must end');
          final w = g.winner!;
          expect(g.positions[w], 100);
          expect(g.standings.first, w);
          expect(g.standings.toSet().length, players);
          expect(g.turns, rolls.length);
          expect(g.rolls.reduce((a, b) => a + b), rolls.length);
          for (var p = 0; p < players; p++) {
            if (p != w) expect(g.positions[p], lessThan(100));
          }
          // Standings after the winner go by position.
          final rest = g.standings.skip(1).map((p) => g.positions[p]).toList();
          for (var k = 1; k < rest.length; k++) {
            expect(rest[k - 1], greaterThanOrEqualTo(rest[k]));
          }

          // Replaying the same rolls from a save midway gives the same game.
          final replay =
              slGame(board: board, players: players, rules: rules, bots: true);
          final half = rolls.length ~/ 2;
          for (final r in rolls.take(half)) {
            replay.play(r);
          }
          final resumed = GameEngine.fromJson(replay.toJson());
          expect(jsonEncode(resumed.toJson()), jsonEncode(replay.toJson()));
          for (final r in rolls.skip(half)) {
            resumed.play(r);
          }
          final a = resumed.toJson()..remove('id');
          final b = g.toJson()..remove('id');
          expect(jsonEncode(a), jsonEncode(b));
        });
      }
    }
  });
}
