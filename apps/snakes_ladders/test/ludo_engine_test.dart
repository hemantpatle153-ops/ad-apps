import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:snakes_ladders/ludo/bot.dart';
import 'package:snakes_ladders/ludo/engine.dart';
import 'package:snakes_ladders/ludo/match.dart';
import 'package:snakes_ladders/ludo/ui/geometry.dart';

LudoEngine twoPlayers({GameRules rules = const GameRules()}) => LudoEngine(
      players: const [
        Player(name: 'A', color: 3, kind: PlayerKind.human),
        Player(name: 'B', color: 1, kind: PlayerKind.human),
      ],
      rules: rules,
    );

void main() {
  test('board loop has 52 distinct squares and joins up', () {
    expect(Grid.loop.toSet().length, 52);
    for (var i = 0; i < 52; i++) {
      final (r1, c1) = Grid.loop[i];
      final (r2, c2) = Grid.loop[(i + 1) % 52];
      final step = (r1 - r2).abs() + (c1 - c2).abs();
      // Neighbours, except the diagonal hop around each inner corner.
      expect(
          step == 1 || ((r1 - r2).abs() == 1 && (c1 - c2).abs() == 1), isTrue,
          reason: 'square $i');
    }
    // Red turns into its home column from the square left of it.
    expect(Grid.loop[50], (7, 0));
    expect(Grid.homeColumn(0, 1), (7, 1));
  });

  test('a token needs a six to leave the yard', () {
    final g = twoPlayers();
    final r = g.roll(4);
    expect(r.passes, isTrue);
    expect(g.current, 1);
    final r2 = g.roll(6);
    expect(r2.movable, [0, 1, 2, 3]);
    final m = g.move(2);
    expect(m.to, 0);
    expect(m.extraTurn, isTrue);
    expect(g.current, 1);
  });

  test('landing on an opponent sends it home and earns a throw', () {
    final g = twoPlayers();
    // A (blue, starts at 39) on progress 5 = square 44.
    g.tokens[0][0] = 5;
    // B (green, starts at 13) on progress 31 = square 44 + ... set directly.
    g.tokens[1][0] = (44 - 13);
    g.tokens[0][0] = 2;
    final r = g.roll(3);
    expect(r.movable, [0]);
    final m = g.move(0);
    expect(m.captures.single.player, 1);
    expect(g.tokens[1][0], Track.yard);
    expect(m.extraTurn, isTrue);
    expect(g.current, 0);
  });

  test('no capture on a safe square', () {
    final g = twoPlayers();
    // Square 47 is a star.
    g.tokens[0][0] = 5; // 44
    g.tokens[1][0] = 47 - 13;
    g.roll(3);
    final m = g.move(0);
    expect(m.captures, isEmpty);
    expect(g.tokens[1][0], 34);
  });

  test('home needs an exact throw', () {
    final g = twoPlayers(rules: const GameRules(tokens: 2));
    g.tokens[0] = [53, Track.home];
    expect(g.roll(4).passes, isTrue);
    g.current = 0;
    final r = g.roll(3);
    expect(r.movable, [0]);
    final m = g.move(0);
    expect(m.finishedPlayer, isTrue);
    expect(m.gameOver, isTrue);
    expect(g.winner, 0);
    expect(g.standings, [0, 1]);
  });

  test('three sixes end the turn', () {
    final g = twoPlayers();
    g.tokens[0][0] = 10;
    g.roll(6);
    g.move(0);
    g.roll(6);
    g.move(0);
    final r = g.roll(6);
    expect(r.threeSixes, isTrue);
    expect(g.current, 1);
    expect(g.tokens[0][0], 22);
  });

  test('bots finish a 4 player game and replays stay in sync', () {
    final rnd = Random(5);
    final g = LudoEngine(players: [
      for (var c = 0; c < 4; c++)
        Player(name: 'P$c', color: c, kind: PlayerKind.human),
    ]);
    final log = <GameAction>[];
    var guard = 0;
    while (!g.isOver && guard++ < 20000) {
      final v = 1 + rnd.nextInt(6);
      final roll = RollAction(g.current, v);
      expect(roll.validFor(g), isTrue);
      log.add(roll);
      final r = g.roll(v);
      if (r.passes) continue;
      final t = chooseMove(g, r.movable, random: rnd);
      log.add(MoveAction(g.current, t));
      g.move(t);
    }
    expect(g.isOver, isTrue);
    expect(g.standings.length, 4);

    final copy = LudoEngine(players: g.players);
    for (final a in log) {
      final json = GameAction.fromJson(a.toJson());
      expect(json.validFor(copy), isTrue);
      switch (json) {
        case RollAction(:final value):
          copy.roll(value);
        case MoveAction(:final token):
          copy.move(token);
      }
    }
    expect(copy.toJson(), g.toJson());
    final restored = LudoEngine.fromJson(g.toJson());
    expect(restored.toJson(), g.toJson());
  });
}
