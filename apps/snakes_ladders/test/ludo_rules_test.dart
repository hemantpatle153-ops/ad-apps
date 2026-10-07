import 'package:flutter_test/flutter_test.dart';
import 'package:snakes_ladders/ludo/engine.dart';
import 'package:snakes_ladders/ludo/ui/geometry.dart';

import 'support/gen.dart';

/// Where a token at [from] goes with [roll], worked out from the rules.
int? expectedTarget(int from, int roll, bool sixToRelease) {
  if (from == Track.home) return null;
  if (from == Track.yard) {
    return roll == 6 || (!sixToRelease && roll == 1) ? 0 : null;
  }
  return from + roll <= Track.home ? from + roll : null;
}

/// Progress for colour [c] that sits on loop square [sq], or null when that
/// colour can't stand there (the square just before its own start).
int? progressOn(int c, int sq) {
  final p = (sq - Track.startOf(c) + Track.loop) % Track.loop;
  return p <= Track.lastTrack ? p : null;
}

void main() {
  group('track squares', () {
    for (var p = -1; p <= Track.home; p++) {
      test('progress $p maps to the right loop square for every colour', () {
        for (var c = 0; c < 4; c++) {
          final sq = Track.square(c, p);
          if (p < 0 || p > Track.lastTrack) {
            expect(sq, isNull);
          } else {
            expect(sq, (13 * c + p) % 52);
            expect(progressOn(c, sq!), p);
          }
        }
      });
    }

    for (var sq = 0; sq < 52; sq++) {
      test('square $sq is ${Track.isSafe(sq) ? '' : 'not '}a safe square', () {
        final starts = {for (var c = 0; c < 4; c++) Track.startOf(c)};
        final stars = {for (var c = 0; c < 4; c++) Track.startOf(c) + 8};
        expect(Track.isSafe(sq), starts.contains(sq) || stars.contains(sq));
      });
    }
  });

  group('which tokens may move', () {
    for (final release in [true, false]) {
      for (var from = -1; from <= Track.home; from++) {
        test('sixToRelease=$release, token at $from', () {
          for (var roll = 1; roll <= 6; roll++) {
            final g = ludoGame(rules: GameRules(sixToRelease: release));
            g.tokens[0] = [from, Track.home, Track.home, Track.home];
            final t = expectedTarget(from, roll, release);
            expect(g.movableFor(0, roll), t == null ? isEmpty : [0],
                reason: 'roll $roll');
            if (from == Track.home) {
              expect(g.isOver, isTrue); // all four home: nothing to throw
              continue;
            }
            final r = g.roll(roll);
            expect(r.player, 0);
            expect(r.value, roll);
            expect(r.passes, t == null, reason: 'roll $roll');
            if (t == null) {
              // A six with nothing to move still keeps the turn.
              expect(g.current, roll == 6 ? 0 : 1, reason: 'roll $roll');
              expect(g.phase, Phase.roll);
              continue;
            }
            expect(g.phase, Phase.move);
            final m = g.move(0);
            expect(m.from, from);
            expect(m.to, t);
            expect(g.tokens[0][0], t);
            expect(
                m.steps,
                from == Track.yard
                    ? [0]
                    : [for (var s = from + 1; s <= t; s++) s]);
            expect(m.finishedToken, t == Track.home);
            expect(m.finishedPlayer, t == Track.home);
            expect(m.gameOver, t == Track.home);
            if (t == Track.home) {
              expect(g.winner, 0);
              expect(g.standings, [0, 1]);
            } else {
              expect(m.extraTurn, roll == 6);
              expect(g.current, roll == 6 ? 0 : 1);
            }
          }
        });
      }
    }

    test('a token that is home can never move', () {
      final g = ludoGame()..tokens[0] = List.filled(4, Track.home);
      for (var roll = 1; roll <= 6; roll++) {
        expect(g.movableFor(0, roll), isEmpty);
      }
    });

    test('moving a token that cannot move throws', () {
      final g = ludoGame()..tokens[0] = [10, -1, -1, -1];
      g.roll(3);
      expect(() => g.move(1), throwsArgumentError);
      expect(g.tokens[0][1], Track.yard);
    });
  });

  group('captures on every loop square', () {
    for (var sq = 0; sq < 52; sq++) {
      final mover = 3; // blue, seat 0 in a two player game
      final p = progressOn(mover, sq);
      if (p == null) continue;
      test('blue lands on square $sq', () {
        // Pick an opponent colour that can stand on this square.
        final oc = [0, 1, 2].firstWhere((c) => progressOn(c, sq) != null);
        final g = LudoEngine(players: [
          const Player(name: 'B', color: 3, kind: PlayerKind.human),
          Player(name: 'O', color: oc, kind: PlayerKind.human),
        ]);
        g.tokens[1] = [progressOn(oc, sq)!, progressOn(oc, sq)!, -1, -1];
        final int roll;
        if (p == 0) {
          g.tokens[0] = [Track.yard, -1, -1, -1];
          roll = 6;
        } else {
          roll = p >= 4 ? 4 : p;
          g.tokens[0] = [p - roll, Track.home, Track.home, Track.home];
        }
        final r = g.roll(roll);
        expect(r.movable, contains(0));
        final m = g.move(0);
        expect(Track.square(3, m.to), sq);
        if (Track.isSafe(sq)) {
          expect(m.captures, isEmpty);
          expect(g.tokens[1].take(2), everyElement(progressOn(oc, sq)));
          expect(m.extraTurn, roll == 6);
        } else {
          // Both tokens on the square are sent back to the yard.
          expect(m.captures.length, 2);
          expect(m.captures.map((c) => c.player), everyElement(1));
          expect(
              m.captures.map((c) => c.from), everyElement(progressOn(oc, sq)));
          expect(g.tokens[1].take(2), everyElement(Track.yard));
          expect(g.captures[0], 2);
          expect(m.extraTurn, isTrue);
          expect(g.current, 0);
        }
      });
    }

    for (var k = 1; k <= 5; k++) {
      test('home column step $k is out of reach of opponents', () {
        final g = ludoGame();
        // Blue enters its home column; green sits on the loop square that
        // number would map to if the loop carried on.
        g.tokens[0] = [Track.lastTrack, -1, -1, -1];
        g.tokens[1][0] = progressOn(1, (39 + 50 + k) % 52) ?? 0;
        final before = g.tokens[1][0];
        g.roll(k);
        final m = g.move(0);
        expect(m.to, Track.lastTrack + k);
        expect(m.captures, isEmpty);
        expect(g.tokens[1][0], before);
      });
    }

    test('own tokens are never captured', () {
      final g = ludoGame()..tokens[0] = [2, 5, -1, -1];
      g.roll(3);
      final m = g.move(0);
      expect(m.captures, isEmpty);
      expect(g.tokens[0].take(2), [5, 5]);
    });

    test('captures hit every opponent on the square in a 4 player game', () {
      final g = ludoGame(players: 4);
      // Square 44 (not safe): blue p5, red p44, green p31, yellow p18.
      g.tokens[0][0] = 2;
      g.tokens[1][0] = 44;
      g.tokens[2][0] = 31;
      g.tokens[3][0] = 18;
      g.roll(3);
      final m = g.move(0);
      expect(m.captures.map((c) => c.player).toSet(), {1, 2, 3});
      expect(g.captures[0], 3);
    });
  });

  group('exact finish', () {
    for (var from = 45; from <= 55; from++) {
      for (var roll = 1; roll <= 6; roll++) {
        test('token at $from rolls $roll', () {
          final g = ludoGame()..tokens[0] = [from, 30, -1, -1];
          final can = g.movableFor(0, roll).contains(0);
          expect(can, from + roll <= Track.home);
          if (!can) return;
          g.roll(roll);
          final m = g.move(0);
          expect(m.to, from + roll);
          final done = from + roll == Track.home;
          expect(m.finishedToken, done);
          expect(m.finishedPlayer, isFalse); // other tokens still out
          // Reaching home earns another throw.
          expect(m.extraTurn, done || roll == 6 || m.captures.isNotEmpty);
        });
      }
    }
  });

  group('turns and game end', () {
    test('three sixes in a row cancel the turn', () {
      final g = ludoGame()..tokens[0][0] = 10;
      g.roll(6);
      g.move(0);
      g.roll(6);
      g.move(0);
      final r = g.roll(6);
      expect(r.threeSixes, isTrue);
      expect(r.passes, isTrue);
      expect(g.current, 1);
      expect(g.sixStreak, 0);
      expect(g.sixes[0], 3);
    });

    test('without the three sixes rule a third six moves', () {
      final g = ludoGame(rules: const GameRules(threeSixes: false))
        ..tokens[0][0] = 10;
      for (var i = 0; i < 3; i++) {
        g.roll(6);
        g.move(0);
      }
      expect(g.tokens[0][0], 28);
      expect(g.current, 0);
    });

    test('a finished player is skipped', () {
      final g = ludoGame(players: 3, rules: const GameRules(tokens: 2));
      g.tokens[1] = [Track.home, Track.home];
      g.roll(2); // nothing out, turn passes from 0
      expect(g.current, 2);
    });

    test('the second last finisher ends the game and the rest are ranked', () {
      final g = ludoGame(players: 3, rules: const GameRules(tokens: 2));
      g.tokens[0] = [Track.home, 55];
      g.tokens[1] = [Track.home, Track.home];
      g.finishOrder.add(1);
      g.tokens[2] = [20, 30];
      g.roll(1);
      final m = g.move(1);
      expect(m.finishedPlayer, isTrue);
      expect(m.gameOver, isTrue);
      expect(m.extraTurn, isFalse);
      expect(g.finishOrder, [1, 0, 2]);
      expect(g.winner, 1);
      expect(g.isOver, isTrue);
    });

    final overCases = <String, (List<PlayerKind>, List<bool>, bool)>{
      'two people, nobody done': (
        [PlayerKind.human, PlayerKind.human],
        [false, false],
        false
      ),
      'one person left': (
        [PlayerKind.human, PlayerKind.human],
        [true, false],
        true
      ),
      'only computers left': (
        [PlayerKind.human, PlayerKind.bot, PlayerKind.bot],
        [true, false, false],
        true
      ),
      'person and computer still playing': (
        [PlayerKind.human, PlayerKind.bot, PlayerKind.bot],
        [false, true, false],
        false
      ),
      'all-computer table': (
        [PlayerKind.bot, PlayerKind.bot],
        [false, false],
        true
      ),
      'remote friends still playing': (
        [PlayerKind.remote, PlayerKind.remote, PlayerKind.remote],
        [true, false, false],
        false
      ),
    };
    overCases.forEach((name, c) {
      test('isOver: $name', () {
        final (kinds, done, over) = c;
        final g = LudoEngine(
          players: [
            for (var i = 0; i < kinds.length; i++)
              Player(name: '$i', color: i, kind: kinds[i]),
          ],
          rules: const GameRules(tokens: 2),
        );
        for (var i = 0; i < done.length; i++) {
          if (done[i]) g.tokens[i] = [Track.home, Track.home];
        }
        expect(g.isOver, over);
      });
    });

    final scoreCases = <(List<int>, int)>[
      ([-1, -1, -1, -1], 0),
      ([0, -1, -1, -1], 1),
      ([56, 56, 56, 56], 228),
      ([10, 20, -1, 55], 11 + 21 + 56),
      ([50, 51], 51 + 52),
    ];
    for (final (tokens, score) in scoreCases) {
      test('score of $tokens is $score', () {
        final g = ludoGame(rules: GameRules(tokens: tokens.length))
          ..tokens[0] = List.of(tokens);
        expect(g.score(0), score);
        expect(g.progress(0), score / (tokens.length * 57));
      });
    }
  });

  group('board geometry', () {
    for (var p = Track.yard; p <= Track.home; p++) {
      test('progress $p is drawn on the board for every colour', () {
        final spots = <Offset>[];
        for (var c = 0; c < 4; c++) {
          for (var t = 0; t < 4; t++) {
            final o = Grid.tokenSpot(c, p, t, 4);
            expect(o.dx, inInclusiveRange(0, 15));
            expect(o.dy, inInclusiveRange(0, 15));
            spots.add(o);
          }
          if (p >= 0 && p <= Track.lastTrack) {
            expect(Grid.tokenSpot(c, p, 0, 4),
                Grid.center(Grid.loop[Track.square(c, p)!]));
          }
          if (p > Track.lastTrack && p < Track.home) {
            final cell = Grid.homeColumn(c, p - Track.lastTrack);
            expect(Grid.loop.contains(cell), isFalse);
          }
        }
        if (p == Track.yard) {
          // Sixteen distinct yard circles.
          expect(spots.toSet().length, 16);
        }
      });
    }

    for (var q = 0; q < 8; q++) {
      test('turning $q quarters keeps cells on the board', () {
        for (var r = 0; r < 15; r++) {
          for (var c = 0; c < 15; c++) {
            final (r2, c2) = Grid.turn((r, c), q);
            expect(r2, inInclusiveRange(0, 14));
            expect(c2, inInclusiveRange(0, 14));
            expect(Grid.turn((r, c), q + 4), (r2, c2));
          }
        }
      });
    }
  });
}
