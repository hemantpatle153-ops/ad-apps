import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:snakes_ladders/game/board.dart';
import 'package:snakes_ladders/game/engine.dart';

/// A fixed board so these tests don't depend on the preset layouts.
const testBoard = BoardLayout(
  id: 'test',
  name: 'Test',
  description: '',
  ladders: {1: 38, 4: 14},
  snakes: {16: 6},
);

GameEngine game({GameRules rules = const GameRules(), int players = 2}) =>
    GameEngine(
      board: testBoard,
      players: [
        for (var i = 0; i < players; i++)
          Player(name: 'P$i', color: i, kind: PlayerKind.human),
      ],
      rules: rules,
    );

void main() {
  test('preset boards are valid and nothing crosses', () {
    for (final b in BoardLayout.presets) {
      expect(b.isValid, isTrue, reason: b.name);
      expect(b.isTidy, isTrue, reason: b.name);
    }
  });

  test('random boards are valid', () {
    for (var seed = 0; seed < 300; seed++) {
      final b = BoardLayout.random(seed);
      expect(b.isValid, isTrue, reason: 'seed $seed');
      expect(b.isTidy, isTrue, reason: 'seed $seed');
      expect(b.ladders.length, greaterThanOrEqualTo(6));
      expect(b.snakes.length, greaterThanOrEqualTo(6));
    }
  });

  test('cells snake back and forth', () {
    expect(cellGrid(1), (col: 0, row: 0));
    expect(cellGrid(10), (col: 9, row: 0));
    expect(cellGrid(11), (col: 9, row: 1));
    expect(cellGrid(20), (col: 0, row: 1));
    expect(cellGrid(100), (col: 0, row: 9));
  });

  test('ladder at 1 climbs to 38 and turn passes', () {
    final g = game();
    final r = g.play(1);
    expect(r.steps, [1]);
    expect(r.hitLadder, isTrue);
    expect(r.end, 38);
    expect(g.positions[0], 38);
    expect(g.current, 1);
  });

  test('snake at 16 bites down to 6', () {
    final g = game()..positions[0] = 12;
    final r = g.play(4);
    expect(r.hitSnake, isTrue);
    expect(r.end, 6);
    expect(g.snakeBites[0], 1);
  });

  test('six gives another roll, third six ends the turn', () {
    final g = game()..positions[0] = 2;
    expect(g.play(6).extraTurn, isTrue); // 2 -> 8
    expect(g.current, 0);
    expect(g.play(6).extraTurn, isTrue); // 8 -> 14
    final third = g.play(6);
    expect(third.threeSixes, isTrue);
    expect(g.positions[0], 14);
    expect(g.current, 1);
  });

  test('exact finish blocks an overshoot', () {
    final g = game()..positions[0] = 97;
    final r = g.play(5);
    expect(r.blocked, isTrue);
    expect(g.positions[0], 97);
    expect(g.current, 1);
  });

  test('without exact finish an overshoot wins', () {
    final g = game(rules: const GameRules(exactFinish: false))
      ..positions[0] = 97;
    final r = g.play(5);
    expect(r.won, isTrue);
    expect(g.winner, 0);
  });

  test('rolling exactly 100 wins', () {
    final g = game()..positions[0] = 97;
    expect(g.play(3).won, isTrue);
    expect(g.isOver, isTrue);
    expect(g.standings.first, 0);
  });

  test('six to start keeps the token off the board', () {
    final g = game(rules: const GameRules(sixToStart: true));
    expect(g.play(3).blocked, isTrue);
    expect(g.positions[0], 0);
    expect(g.current, 1);
  });

  test('save and restore keeps the game state', () {
    final g = game(players: 3)
      ..play(1)
      ..play(4);
    final copy = GameEngine.fromJson(g.toJson());
    expect(copy.positions, g.positions);
    expect(copy.current, g.current);
    expect(copy.players.map((p) => p.name), ['P0', 'P1', 'P2']);
    expect(copy.board.ladders, g.board.ladders);
  });

  test('random games always finish', () {
    for (var seed = 0; seed < 200; seed++) {
      final g = GameEngine(
        board: BoardLayout.random(seed),
        players: [
          for (var i = 0; i < 4; i++)
            Player(name: 'B$i', color: i, kind: PlayerKind.bot),
        ],
        random: Random(seed),
      );
      var turns = 0;
      while (!g.isOver && turns < 20000) {
        g.play(g.rollDie());
        turns++;
      }
      expect(g.isOver, isTrue, reason: 'seed $seed');
    }
  });
}
