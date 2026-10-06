import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine.dart';
import 'themes.dart';

/// An unfinished game kept on the device.
class SavedGame {
  const SavedGame(
      {required this.id, required this.savedAt, required this.engine});

  final String id;
  final DateTime savedAt;
  final LudoEngine engine;

  Map<String, dynamic> toJson() => {
        'id': id,
        'savedAt': savedAt.millisecondsSinceEpoch,
        'game': engine.toJson(),
      };

  factory SavedGame.fromJson(Map<String, dynamic> j) => SavedGame(
        id: j['id'] as String,
        savedAt: DateTime.fromMillisecondsSinceEpoch(j['savedAt'] as int),
        engine: LudoEngine.fromJson(j['game'] as Map<String, dynamic>),
      );
}

/// Settings, lifetime stats and saved games, kept on the device.
class LudoStore extends ChangeNotifier {
  LudoStore._(this._p);

  final SharedPreferences _p;

  /// How many unfinished games are kept; the oldest drops off.
  static const maxSaved = 5;

  static Future<LudoStore> open() async =>
      LudoStore._(await SharedPreferences.getInstance());

  bool get sound => _p.getBool('sound') ?? true;
  set sound(bool v) => _set(() => _p.setBool('sound', v));

  bool get vibration => _p.getBool('vibration') ?? true;
  set vibration(bool v) => _set(() => _p.setBool('vibration', v));

  bool get fastMoves => _p.getBool('fastMoves') ?? false;
  set fastMoves(bool v) => _set(() => _p.setBool('fastMoves', v));

  int get themeIndex =>
      (_p.getInt('ludo.theme') ?? 0).clamp(0, LudoTheme.all.length - 1);
  set themeIndex(int v) => _set(() => _p.setInt('ludo.theme', v));
  LudoTheme get theme => LudoTheme.all[themeIndex];

  String get playerName => _p.getString('ludo.playerName') ?? 'You';
  set playerName(String v) => _set(() => _p.setString('ludo.playerName', v));

  /// The colour the player likes to play, 0..3.
  int get favouriteColor => (_p.getInt('ludo.color') ?? 3).clamp(0, 3);
  set favouriteColor(int v) => _set(() => _p.setInt('ludo.color', v));

  GameRules get rules {
    final raw = _p.getString('ludo.rules');
    return raw == null
        ? const GameRules()
        : GameRules.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  set rules(GameRules r) =>
      _set(() => _p.setString('ludo.rules', jsonEncode(r.toJson())));

  // Stats.
  int get played => _p.getInt('ludo.played') ?? 0;
  int get wins => _p.getInt('ludo.wins') ?? 0;
  int get botGames => _p.getInt('ludo.botGames') ?? 0;
  int get onlineGames => _p.getInt('ludo.onlineGames') ?? 0;
  int get captures => _p.getInt('ludo.captures') ?? 0;

  /// Records a finished game. [me] is this phone's player in a vs-computer
  /// or online game; pass-and-play games only count as played.
  Future<void> recordGame(LudoEngine g, {int? me, bool online = false}) async {
    await _p.setInt('ludo.played', played + 1);
    if (online) await _p.setInt('ludo.onlineGames', onlineGames + 1);
    if (g.players.any((p) => p.isBot)) {
      await _p.setInt('ludo.botGames', botGames + 1);
    }
    if (me != null) {
      await _p.setInt('ludo.captures', captures + g.captures[me]);
      if (g.winner == me) await _p.setInt('ludo.wins', wins + 1);
    }
    notifyListeners();
  }

  /// Unfinished games, newest first.
  List<SavedGame> get savedGames {
    final out = <SavedGame>[];
    for (final raw in _p.getStringList('ludo.savedGames') ?? const <String>[]) {
      try {
        final s = SavedGame.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (!s.engine.isOver) out.add(s);
      } catch (_) {
        // Skip a save from an older version that no longer parses.
      }
    }
    out.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return out;
  }

  Future<void> save(String id, LudoEngine g) async {
    final games = savedGames.where((s) => s.id != id).toList();
    if (!g.isOver) {
      games.insert(0, SavedGame(id: id, savedAt: DateTime.now(), engine: g));
    }
    await _writeSaved(games.take(maxSaved).toList());
  }

  Future<void> deleteSaved(String id) async =>
      _writeSaved(savedGames.where((s) => s.id != id).toList());

  Future<void> _writeSaved(List<SavedGame> games) async {
    await _p.setStringList(
        'ludo.savedGames', [for (final s in games) jsonEncode(s.toJson())]);
    notifyListeners();
  }

  static String newGameId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  void _set(Future<bool> Function() write) {
    write();
    notifyListeners();
  }
}
