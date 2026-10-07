import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snakes_ladders/game/board.dart';
import 'package:snakes_ladders/game/engine.dart' as sl;
import 'package:snakes_ladders/game/store.dart';
import 'package:snakes_ladders/game/themes.dart';
import 'package:snakes_ladders/ludo/bot.dart';
import 'package:snakes_ladders/ludo/engine.dart' as ludo;
import 'package:snakes_ladders/ludo/store.dart' as ls;
import 'package:snakes_ladders/ludo/themes.dart';

import 'support/gen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Snakes & Ladders settings', () {
    test('defaults', () async {
      final s = await Store.open();
      expect(s.sound, isTrue);
      expect(s.vibration, isTrue);
      expect(s.fastMoves, isFalse);
      expect(s.themeIndex, 0);
      expect(s.playerName, 'You');
      expect(s.played, 0);
      expect(s.fastestWin, 0);
      expect(s.savedGames, isEmpty);
    });

    for (final v in [true, false]) {
      test('sound/vibration/fastMoves = $v persist and notify', () async {
        final s = await Store.open();
        var calls = 0;
        s.addListener(() => calls++);
        s
          ..sound = v
          ..vibration = v
          ..fastMoves = v;
        expect(calls, 3);
        final again = await Store.open();
        expect([again.sound, again.vibration, again.fastMoves], [v, v, v]);
      });
    }

    for (var i = -3; i <= 8; i++) {
      test('theme index $i is clamped to a real theme', () async {
        final s = await Store.open();
        s.themeIndex = i;
        expect(s.themeIndex, i.clamp(0, BoardTheme.all.length - 1));
        expect(s.theme, BoardTheme.all[s.themeIndex]);
      });
    }

    for (final name in ['Asha', '', 'राहुल', 'A very long name indeed']) {
      test('player name "$name" persists', () async {
        final s = await Store.open();
        s.playerName = name;
        expect((await Store.open()).playerName, name);
      });
    }

    for (final r in slRuleCombos) {
      test('rules ${slRulesName(r)} persist', () async {
        final s = await Store.open();
        s.rules = r;
        final back = (await Store.open()).rules;
        expect(back.exactFinish, r.exactFinish);
        expect(back.sixExtraTurn, r.sixExtraTurn);
        expect(back.sixToStart, r.sixToStart);
      });
    }
  });

  group('Snakes & Ladders saved games', () {
    for (var seed = 0; seed < 30; seed++) {
      test('seed $seed: a half-played game saves and loads intact', () async {
        final store = await Store.open();
        final g = slGame(
            board: BoardLayout.random(seed),
            players: 2 + seed % 3,
            rules: slRuleCombos[seed % 8],
            seed: seed,
            bots: true);
        for (var i = 0; i < 10 + seed && !g.isOver; i++) {
          g.play(g.rollDie());
        }
        await store.save(g);
        final saved = store.savedGames;
        if (g.isOver) {
          expect(saved, isEmpty); // finished games are never listed
          return;
        }
        expect(saved.length, 1);
        expect(jsonEncode(saved.single.game.toJson()), jsonEncode(g.toJson()));
        expect(saved.single.game.board.isValid, isTrue);
      });
    }

    test('a corrupt entry is skipped without losing the saved list type',
        () async {
      SharedPreferences.setMockInitialValues({'savedGames': 'not json'});
      final store = await Store.open();
      expect(store.savedGames, isEmpty);
      await store.save(slGame());
      expect(store.savedGames.length, 1);
    });

    test('a corrupt legacy save is ignored', () async {
      SharedPreferences.setMockInitialValues({'saved': '{"oops":1}'});
      expect((await Store.open()).savedGames, isEmpty);
    });

    test('saved games come back newest first', () async {
      final store = await Store.open();
      final games = [for (var i = 0; i < 3; i++) slGame()];
      for (final g in games) {
        await store.save(g);
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      expect(store.savedGames.map((s) => s.game.id),
          games.reversed.map((g) => g.id));
    });
  });

  group('Snakes & Ladders stats', () {
    for (var seed = 0; seed < 20; seed++) {
      test('seed $seed: stats add up over three games', () async {
        final store = await Store.open();
        var played = 0, wins = 0, botGames = 0, bites = 0, ladders = 0;
        var fastest = 0;
        final rnd = Random(seed);
        for (var k = 0; k < 3; k++) {
          final vsBot = rnd.nextBool();
          final g = slGame(
              board: BoardLayout.presets[k], seed: seed * 7 + k, bots: vsBot);
          while (!g.isOver) {
            g.play(g.rollDie());
          }
          await store.recordGame(g);
          played++;
          for (var i = 0; i < g.players.length; i++) {
            if (g.players[i].isBot) continue;
            bites += g.snakeBites[i];
            ladders += g.laddersClimbed[i];
          }
          final w = g.winner!;
          if (vsBot) {
            botGames++;
            if (!g.players[w].isBot) wins++;
          }
          if (!g.players[w].isBot) {
            if (fastest == 0 || g.rolls[w] < fastest) fastest = g.rolls[w];
          }
        }
        expect(store.played, played);
        expect(store.wins, wins);
        expect(store.botGames, botGames);
        expect(store.snakeBites, bites);
        expect(store.laddersClimbed, ladders);
        expect(store.fastestWin, fastest);
      });
    }

    test('a computer win does not count as a win', () async {
      final store = await Store.open();
      final g = slGame(bots: true)..winner = 1;
      await store.recordGame(g);
      expect(store.wins, 0);
      expect(store.botGames, 1);
      expect(store.fastestWin, 0);
    });
  });

  group('Ludo settings', () {
    test('defaults', () async {
      final s = await ls.LudoStore.open();
      expect(s.themeIndex, 0);
      expect(s.playerName, 'You');
      expect(s.favouriteColor, 3);
      expect(s.rules.tokens, 4);
      expect(s.savedGames, isEmpty);
      expect([s.played, s.wins, s.botGames, s.onlineGames, s.captures],
          [0, 0, 0, 0, 0]);
    });

    for (var c = -2; c <= 6; c++) {
      test('favourite colour $c is kept within 0..3', () async {
        final s = await ls.LudoStore.open();
        s.favouriteColor = c;
        expect(s.favouriteColor, c.clamp(0, 3));
      });
    }

    for (var i = -2; i <= 7; i++) {
      test('Ludo theme index $i is clamped', () async {
        final s = await ls.LudoStore.open();
        s.themeIndex = i;
        expect(s.theme, LudoTheme.all[i.clamp(0, LudoTheme.all.length - 1)]);
      });
    }

    for (final tokens in [2, 4]) {
      for (final release in [true, false]) {
        for (final three in [true, false]) {
          test('Ludo rules tokens=$tokens release=$release three=$three',
              () async {
            final s = await ls.LudoStore.open();
            s.rules = ludo.GameRules(
                tokens: tokens, sixToRelease: release, threeSixes: three);
            final r = (await ls.LudoStore.open()).rules;
            expect([r.tokens, r.sixToRelease, r.threeSixes],
                [tokens, release, three]);
            final c = r.copyWith();
            expect([c.tokens, c.sixToRelease, c.threeSixes],
                [tokens, release, three]);
          });
        }
      }
    }

    test('Ludo keys do not clash with Snakes & Ladders keys', () async {
      final a = await Store.open();
      final b = await ls.LudoStore.open();
      a.playerName = 'Snake';
      b.playerName = 'Ludo';
      a.themeIndex = 2;
      b.themeIndex = 1;
      expect(a.playerName, 'Snake');
      expect(b.playerName, 'Ludo');
      expect(a.themeIndex, 2);
      expect(b.themeIndex, 1);
    });
  });

  group('Ludo saved games', () {
    for (var seed = 0; seed < 30; seed++) {
      test('seed $seed: a Ludo game saves and loads intact', () async {
        final store = await ls.LudoStore.open();
        final rnd = Random(seed);
        final g = ludoGame(
            players: 2 + seed % 3,
            rules: ludo.GameRules(tokens: seed.isEven ? 4 : 2));
        for (var i = 0; i < 20 + seed * 2 && !g.isOver; i++) {
          final r = g.roll(1 + rnd.nextInt(6));
          if (!r.passes) g.move(chooseMove(g, r.movable, random: rnd));
        }
        final id = 'g$seed';
        await store.save(id, g);
        final saved = store.savedGames;
        expect(saved.length, g.isOver ? 0 : 1);
        if (g.isOver) return;
        expect(saved.single.id, id);
        expect(
            jsonEncode(saved.single.engine.toJson()), jsonEncode(g.toJson()));
        final s2 = ludoSaveRoundTrip(saved.single);
        expect(s2.id, id);
        expect(s2.savedAt, saved.single.savedAt);
      });
    }

    test('keeps only the newest five', () async {
      final store = await ls.LudoStore.open();
      for (var i = 0; i < 8; i++) {
        await store.save('g$i', ludoGame());
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      expect(store.savedGames.map((s) => s.id), ['g7', 'g6', 'g5', 'g4', 'g3']);
    });

    test('saving a finished game removes it', () async {
      final store = await ls.LudoStore.open();
      final g = ludoGame();
      await store.save('x', g);
      g.tokens[0] = List.filled(4, ludo.Track.home);
      await store.save('x', g);
      expect(store.savedGames, isEmpty);
    });

    test('delete removes only that game', () async {
      final store = await ls.LudoStore.open();
      await store.save('a', ludoGame());
      await store.save('b', ludoGame());
      await store.deleteSaved('a');
      expect(store.savedGames.map((s) => s.id), ['b']);
    });

    test('an unreadable save is skipped', () async {
      SharedPreferences.setMockInitialValues({
        'ludo.savedGames': [
          '{bad',
          jsonEncode({'id': 'x'})
        ],
      });
      expect((await ls.LudoStore.open()).savedGames, isEmpty);
    });

    test('new game ids differ', () async {
      final ids = <String>{};
      for (var i = 0; i < 5; i++) {
        ids.add(ls.LudoStore.newGameId());
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(ids.length, 5);
    });
  });

  group('Ludo stats', () {
    final cases = <(int?, bool, bool, int)>[
      (null, false, false, -1),
      (0, false, false, 0),
      (0, true, false, 1),
      (1, false, true, 0),
      (0, false, true, 1),
      (1, true, true, 1),
    ];
    for (final (me, online, bots, winner) in cases) {
      test('me=$me online=$online bots=$bots winner=$winner', () async {
        final store = await ls.LudoStore.open();
        final g =
            ludoGame(kind: bots ? ludo.PlayerKind.bot : ludo.PlayerKind.human);
        g.captures[0] = 3;
        g.captures[1] = 5;
        if (winner >= 0) g.finishOrder.addAll([winner, 1 - winner]);
        await store.recordGame(g, me: me, online: online);
        expect(store.played, 1);
        expect(store.onlineGames, online ? 1 : 0);
        expect(store.botGames, bots ? 1 : 0);
        expect(store.captures, me == null ? 0 : g.captures[me]);
        expect(store.wins, me != null && winner == me ? 1 : 0);
      });
    }
  });

  group('themes', () {
    for (final t in BoardTheme.all) {
      test('board theme ${t.name} is complete', () {
        expect(t.background.length, greaterThanOrEqualTo(2));
        expect(t.cells, isNotEmpty);
        expect(t.snakes, isNotEmpty);
      });
    }
    for (final t in LudoTheme.all) {
      test('Ludo theme ${t.name} has four player colours', () {
        expect(t.colors.length, 4);
        expect(t.colors.toSet().length, 4);
      });
    }
    test('token colour names match the colours', () {
      expect(tokenColorNames.length, tokenColors.length);
      expect(colorNames.length, 4);
    });
    test('Snakes & Ladders players round trip with the store engine', () {
      const p = sl.Player(name: 'a', color: 1, kind: sl.PlayerKind.bot);
      expect(sl.Player.fromJson(p.toJson()).isBot, isTrue);
    });
  });
}

ls.SavedGame ludoSaveRoundTrip(ls.SavedGame s) => ls.SavedGame.fromJson(
    jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
