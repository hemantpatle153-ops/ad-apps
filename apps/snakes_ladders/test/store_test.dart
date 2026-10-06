import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snakes_ladders/game/board.dart';
import 'package:snakes_ladders/game/engine.dart';
import 'package:snakes_ladders/game/store.dart';

GameEngine newGame() => GameEngine(
      board: BoardLayout.classic,
      players: const [
        Player(name: 'A', color: 0, kind: PlayerKind.human),
        Player(name: 'B', color: 1, kind: PlayerKind.bot),
      ],
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('keeps the 5 most recent unfinished games', () async {
    final store = await Store.open();
    final games = [for (var i = 0; i < 7; i++) newGame()];
    for (final g in games) {
      await store.save(g);
    }
    final ids = store.savedGames.map((s) => s.game.id).toList();
    expect(ids.length, Store.maxSaved);
    expect(ids, [for (final g in games.reversed.take(5)) g.id]);
  });

  test('saving a game again updates it in place and moves it first', () async {
    final store = await Store.open();
    final a = newGame(), b = newGame();
    await store.save(a);
    await store.save(b);
    a.play(4);
    await store.save(a);
    final saved = store.savedGames;
    expect(saved.length, 2);
    expect(saved.first.game.id, a.id);
    expect(saved.first.game.positions[0], 14); // ladder 4 -> 14
  });

  test('a finished game leaves the saved list', () async {
    final store = await Store.open();
    final g = newGame();
    await store.save(g);
    g.positions[0] = 97;
    g.play(3);
    await store.recordGame(g);
    expect(store.savedGames, isEmpty);
    expect(store.played, 1);
    expect(store.wins, 1);
  });

  test('delete removes one game', () async {
    final store = await Store.open();
    final a = newGame(), b = newGame();
    await store.save(a);
    await store.save(b);
    await store.deleteSaved(a.id);
    expect(store.savedGames.map((s) => s.game.id), [b.id]);
  });

  test('a game saved by version 1 still shows up', () async {
    final old = newGame()..play(1);
    final json = old.toJson()..remove('id');
    SharedPreferences.setMockInitialValues({'saved': jsonEncode(json)});
    final store = await Store.open();
    final saved = store.savedGames;
    expect(saved.length, 1);
    expect(saved.first.game.positions[0], 38);
    // Once anything is saved, the old key is folded into the new list.
    await store.save(newGame());
    expect(store.savedGames.length, 2);
  });
}
