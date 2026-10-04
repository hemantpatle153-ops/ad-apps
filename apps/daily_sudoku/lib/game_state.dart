import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'sudoku_engine.dart';

/// Everything needed to resume a game.
class GameState {
  GameState({
    required this.id,
    required this.title,
    required this.givens,
    required this.solution,
    List<int>? values,
    List<Set<int>>? notes,
    this.mistakes = 0,
    this.seconds = 0,
    this.hintsUsed = 0,
    this.completed = false,
  })  : values = values ?? List<int>.from(givens),
        notes = notes ?? List.generate(81, (_) => <int>{});

  final String id;
  final String title;
  final List<int> givens;
  final List<int> solution;
  final List<int> values;
  final List<Set<int>> notes;
  int mistakes;
  int seconds;
  int hintsUsed;
  bool completed;

  bool get isSolved {
    for (var i = 0; i < 81; i++) {
      if (values[i] != solution[i]) return false;
    }
    return true;
  }

  factory GameState.fromPuzzle(String id, String title, Puzzle p) =>
      GameState(id: id, title: title, givens: p.givens, solution: p.solution);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'givens': givens,
        'solution': solution,
        'values': values,
        'notes': notes.map((s) => s.toList()).toList(),
        'mistakes': mistakes,
        'seconds': seconds,
        'hintsUsed': hintsUsed,
        'completed': completed,
      };

  factory GameState.fromJson(Map<String, dynamic> j) => GameState(
        id: j['id'] as String,
        title: j['title'] as String,
        givens: List<int>.from(j['givens'] as List),
        solution: List<int>.from(j['solution'] as List),
        values: List<int>.from(j['values'] as List),
        notes: (j['notes'] as List)
            .map((e) => Set<int>.from(e as List))
            .toList(),
        mistakes: j['mistakes'] as int,
        seconds: j['seconds'] as int,
        hintsUsed: j['hintsUsed'] as int? ?? 0,
        completed: j['completed'] as bool,
      );
}

/// Local storage: the game in progress, finished daily puzzles and stats.
class Store {
  Store(this._p);
  final SharedPreferences _p;

  static Future<Store> open() async =>
      Store(await SharedPreferences.getInstance());

  GameState? loadCurrent() {
    final s = _p.getString('current');
    if (s == null) return null;
    try {
      return GameState.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveCurrent(GameState g) =>
      _p.setString('current', jsonEncode(g.toJson()));

  Future<void> clearCurrent() => _p.remove('current');

  Set<String> get dailyDone => (_p.getStringList('dailyDone') ?? []).toSet();

  Future<void> markDailyDone(String key) =>
      _p.setStringList('dailyDone', {...dailyDone, key}.toList());

  int get solved => _p.getInt('solved') ?? 0;
  int bestSeconds(String level) => _p.getInt('best_$level') ?? 0;

  Future<void> recordWin(String level, int seconds) async {
    await _p.setInt('solved', solved + 1);
    final best = bestSeconds(level);
    if (best == 0 || seconds < best) await _p.setInt('best_$level', seconds);
  }

  /// Consecutive days, ending today or yesterday, with the daily solved.
  int dailyStreak(DateTime today) {
    final done = dailyDone;
    var day = DateTime(today.year, today.month, today.day);
    if (!done.contains(dayKey(day))) day = day.subtract(const Duration(days: 1));
    var n = 0;
    while (done.contains(dayKey(day))) {
      n++;
      day = day.subtract(const Duration(days: 1));
    }
    return n;
  }

  static String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
