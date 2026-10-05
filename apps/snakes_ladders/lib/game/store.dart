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
    await clearSaved();
    notifyListeners();
  }

  GameEngine? loadSaved() {
    final raw = _p.getString('saved');
    if (raw == null) return null;
    try {
      final g = GameEngine.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      return g.isOver ? null : g;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(GameEngine g) async {
    await _p.setString('saved', jsonEncode(g.toJson()));
    notifyListeners();
  }

  Future<void> clearSaved() async {
    await _p.remove('saved');
    notifyListeners();
  }

  void _set(Future<bool> Function() write) {
    write();
    notifyListeners();
  }
}
