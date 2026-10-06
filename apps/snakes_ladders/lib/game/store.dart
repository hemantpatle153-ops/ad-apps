import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine.dart';
import 'themes.dart';

/// Settings, lifetime stats and the saved game, kept on the device.
class Store extends ChangeNotifier {
  Store._(this._p);

  final SharedPreferences _p;

  static Future<Store> open() async =>
      Store._(await SharedPreferences.getInstance());

  bool get sound => _p.getBool('sound') ?? true;
  set sound(bool v) => _set(() => _p.setBool('sound', v));

  bool get vibration => _p.getBool('vibration') ?? true;
  set vibration(bool v) => _set(() => _p.setBool('vibration', v));

  bool get fastMoves => _p.getBool('fastMoves') ?? false;
  set fastMoves(bool v) => _set(() => _p.setBool('fastMoves', v));

  int get themeIndex =>
      (_p.getInt('theme') ?? 0).clamp(0, BoardTheme.all.length - 1);
  set themeIndex(int v) => _set(() => _p.setInt('theme', v));
  BoardTheme get theme => BoardTheme.all[themeIndex];

  String get playerName => _p.getString('playerName') ?? 'You';
  set playerName(String v) => _set(() => _p.setString('playerName', v));

  GameRules get rules {
    final raw = _p.getString('rules');
    return raw == null
        ? const GameRules()
        : GameRules.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  set rules(GameRules r) =>
      _set(() => _p.setString('rules', jsonEncode(r.toJson())));

  // Stats.
  int get played => _p.getInt('played') ?? 0;
  int get wins => _p.getInt('wins') ?? 0;
  int get botGames => _p.getInt('botGames') ?? 0;
  int get snakeBites => _p.getInt('snakeBites') ?? 0;
  int get laddersClimbed => _p.getInt('ladders') ?? 0;

  /// Fewest rolls a human needed to win, 0 if never.
  int get fastestWin => _p.getInt('fastestWin') ?? 0;

  /// Records a finished game. Wins only count against the computer, since in
  /// pass-and-play every winner is "you".
  Future<void> recordGame(GameEngine g) async {
    final vsBot = g.players.any((p) => p.isBot);
    await _p.setInt('played', played + 1);
    for (var i = 0; i < g.players.length; i++) {
      if (g.players[i].isBot) continue;
      await _p.setInt('snakeBites', snakeBites + g.snakeBites[i]);
      await _p.setInt('ladders', laddersClimbed + g.laddersClimbed[i]);
    }
    final w = g.winner;
    if (vsBot) {
      await _p.setInt('botGames', botGames + 1);
      if (w != null && !g.players[w].isBot) {
        await _p.setInt('wins', wins + 1);
      }
    }
    if (w != null && !g.players[w].isBot) {
      final r = g.rolls[w];
      if (fastestWin == 0 || r < fastestWin) await _p.setInt('fastestWin', r);
    }
    await deleteSaved(g.id);
  }

  /// How many unfinished games are kept; saving one more drops the oldest.
  static const maxSaved = 5;

  /// Unfinished games, most recently played first.
  List<SavedGame> get savedGames {
    final out = <SavedGame>[];
    final raw = _p.getString('savedGames');
    if (raw != null) {
      try {
        for (final e in jsonDecode(raw) as List) {
          final m = e as Map<String, dynamic>;
          final g = GameEngine.fromJson(m['game'] as Map<String, dynamic>);
          if (g.isOver) continue;
          out.add(SavedGame(
              g, DateTime.fromMillisecondsSinceEpoch(m['savedAt'] as int)));
        }
      } catch (_) {
        // A corrupt entry must not lose the rest; keep what parsed.
      }
    }
    // Games saved by version 1, which kept only one.
    final legacy = _p.getString('saved');
    if (legacy != null) {
      try {
        final g =
            GameEngine.fromJson(jsonDecode(legacy) as Map<String, dynamic>);
        if (!g.isOver) out.add(SavedGame(g, DateTime.now()));
      } catch (_) {}
    }
    out.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return out;
  }

  Future<void> save(GameEngine g) async {
    final list = savedGames.where((s) => s.game.id != g.id).toList()
      ..insert(0, SavedGame(g, DateTime.now()));
    await _writeSaved(list.take(maxSaved).toList());
  }

  Future<void> deleteSaved(String id) =>
      _writeSaved(savedGames.where((s) => s.game.id != id).toList());

  Future<void> _writeSaved(List<SavedGame> list) async {
    await _p.setString(
      'savedGames',
      jsonEncode([
        for (final s in list)
          {
            'savedAt': s.savedAt.millisecondsSinceEpoch,
            'game': s.game.toJson(),
          },
      ]),
    );
    await _p.remove('saved');
    notifyListeners();
  }

  void _set(Future<bool> Function() write) {
    write();
    notifyListeners();
  }
}

class SavedGame {
  const SavedGame(this.game, this.savedAt);

  final GameEngine game;
  final DateTime savedAt;
}
