import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/bi.dart';
import '../core/day.dart';
import '../core/models.dart';
import '../core/reminder_plan.dart';
import '../core/report.dart';
import '../core/session.dart';
import '../core/stats.dart';

/// String key-value storage: SharedPreferences in the app, a map in tests.
abstract class KeyValueStore {
  String? getString(String key);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
}

class MemoryKeyValueStore implements KeyValueStore {
  MemoryKeyValueStore([Map<String, String>? initial]) : values = {...?initial};
  final Map<String, String> values;

  @override
  String? getString(String key) => values[key];

  @override
  Future<void> setString(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);
}

class PrefsKeyValueStore implements KeyValueStore {
  PrefsKeyValueStore(this._prefs);
  final SharedPreferences _prefs;

  static Future<PrefsKeyValueStore> open() async =>
      PrefsKeyValueStore(await SharedPreferences.getInstance());

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  Future<void> setString(String key, String value) => _prefs.setString(key, value);

  @override
  Future<void> remove(String key) => _prefs.remove(key);
}

enum AppTheme { system, light, dark }

/// Timer choices in seconds per question; 0 = off.
const kTimerChoices = [0, 30, 45, 60, 90];

class Settings {
  Lang lang = Lang.en;
  AppTheme theme = AppTheme.system;
  int timerSeconds = 0;
  bool sound = true;
  bool haptics = true;
  bool dailyReminder = true;
  int reminderMinutes = kDefaultReminderMinutes;
  bool streakReminder = true;
  bool onboarded = false;
  List<String> targetExams = [];
  NegativeMarking mockNegative = NegativeMarking.quarter;

  Map<String, Object?> toJson() => {
        'lang': lang.name,
        'theme': theme.name,
        'timer': timerSeconds,
        'sound': sound,
        'haptics': haptics,
        'dailyReminder': dailyReminder,
        'reminderMinutes': reminderMinutes,
        'streakReminder': streakReminder,
        'onboarded': onboarded,
        'exams': targetExams,
        'mockNegative': mockNegative.name,
      };

  static Settings fromJson(Object? json) {
    final s = Settings();
    if (json is! Map) return s;
    s.lang = Lang.parse(json['lang']);
    s.theme = AppTheme.values
        .firstWhere((t) => t.name == json['theme'], orElse: () => AppTheme.system);
    final timer = json['timer'];
    s.timerSeconds = timer is int && kTimerChoices.contains(timer) ? timer : 0;
    s.sound = json['sound'] is bool ? json['sound'] as bool : true;
    s.haptics = json['haptics'] is bool ? json['haptics'] as bool : true;
    s.dailyReminder =
        json['dailyReminder'] is bool ? json['dailyReminder'] as bool : true;
    final m = json['reminderMinutes'];
    s.reminderMinutes =
        m is int && m >= 0 && m < 24 * 60 ? m : kDefaultReminderMinutes;
    s.streakReminder =
        json['streakReminder'] is bool ? json['streakReminder'] as bool : true;
    s.onboarded = json['onboarded'] == true;
    final exams = json['exams'];
    s.targetExams = exams is List
        ? [for (final e in kExams) if (exams.contains(e)) e]
        : [];
    s.mockNegative = NegativeMarking.parse(json['mockNegative']);
    return s;
  }
}

/// The Daily Quiz result of one day.
class DailyRecord {
  const DailyRecord(this.correct, this.total, this.timeMs, this.choices);
  final int correct;
  final int total;
  final int timeMs;

  /// Choice per question (null = not answered), for "Review answers".
  final List<int?> choices;

  double get fraction => total == 0 ? 0 : correct / total;

  List<Object?> toJson() => [correct, total, timeMs, choices];

  static DailyRecord? fromJson(Object? v) {
    if (v is! List || v.length < 3) return null;
    final c = v[0], t = v[1], ms = v[2];
    if (c is! int || t is! int || ms is! int || t <= 0 || c < 0 || c > t) {
      return null;
    }
    final raw = v.length > 3 && v[3] is List ? v[3] as List : const [];
    return DailyRecord(c, t, ms < 0 ? 0 : ms,
        [for (final x in raw) x is int && x >= 0 && x <= 3 ? x : null]);
  }
}

/// A question kept in Bookmarks or My mistakes. The question itself is
/// stored so the list works even after the cache is cleared.
class SavedQuestion {
  const SavedQuestion(this.question, this.savedAt, {this.count = 1});
  final Question question;
  final DateTime savedAt;

  /// Times answered wrongly (mistakes only).
  final int count;

  Map<String, Object?> toJson() => {
        'q': question.toJson(),
        'at': savedAt.toUtc().millisecondsSinceEpoch,
        'n': count,
      };

  static SavedQuestion? fromJson(Object? v) {
    if (v is! Map) return null;
    final q = Question.tryParse(v['q']);
    final at = v['at'];
    if (q == null || at is! int) return null;
    final n = v['n'];
    return SavedQuestion(q, DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
        count: n is int && n > 0 ? n : 1);
  }
}

/// Everything about the user that lives on the phone: settings, played
/// days, stats, XP, badges, bookmarks, mistakes, seen questions and the
/// report history. Each part is its own key, saved when it changes; a
/// damaged value falls back to its default instead of failing.
class UserStore {
  UserStore(this.kv) {
    _load();
  }

  final KeyValueStore kv;

  late Settings settings;
  final Map<String, DailyRecord> days = {};
  late StatsBook stats;
  int xp = 0;
  final Set<Achievement> badges = {};
  final Map<String, SavedQuestion> bookmarks = {};
  final Map<String, SavedQuestion> mistakes = {};
  final Set<String> seen = {};
  List<(String, DateTime)> reportHistory = [];

  static const maxSeen = 20000;
  static const maxSaved = 1000;

  static const _kSettings = 'settings.v1';
  static const _kDays = 'days.v1';
  static const _kStats = 'stats.v1';
  static const _kXp = 'xp.v1';
  static const _kBadges = 'badges.v1';
  static const _kBookmarks = 'bookmarks.v1';
  static const _kMistakes = 'mistakes.v1';
  static const _kSeen = 'seen.v1';
  static const _kReports = 'reports.v1';

  Object? _json(String key) {
    final raw = kv.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  void _load() {
    settings = Settings.fromJson(_json(_kSettings));
    final d = _json(_kDays);
    if (d is Map) {
      for (final e in d.entries) {
        final rec = DailyRecord.fromJson(e.value);
        if (e.key is String && Day.tryParse(e.key) != null && rec != null) {
          days[e.key as String] = rec;
        }
      }
    }
    stats = StatsBook.fromJson(_json(_kStats));
    final x = _json(_kXp);
    xp = x is int && x >= 0 ? x : 0;
    final b = _json(_kBadges);
    if (b is List) {
      for (final name in b) {
        final badge = Achievement.parse(name);
        if (badge != null) badges.add(badge);
      }
    }
    _loadSaved(_kBookmarks, bookmarks);
    _loadSaved(_kMistakes, mistakes);
    final s = _json(_kSeen);
    if (s is List) seen.addAll(s.whereType<String>());
    reportHistory = ReportRateLimiter.historyFromJson(_json(_kReports));
  }

  void _loadSaved(String key, Map<String, SavedQuestion> into) {
    final v = _json(key);
    if (v is! List) return;
    for (final e in v) {
      final sq = SavedQuestion.fromJson(e);
      if (sq != null) into[sq.question.id] = sq;
    }
  }

  Set<Day> get playedDays =>
      {for (final k in days.keys) Day.tryParse(k)!};

  Future<void> saveSettings() =>
      kv.setString(_kSettings, jsonEncode(settings.toJson()));

  Future<void> saveDays() => kv.setString(
      _kDays, jsonEncode({for (final e in days.entries) e.key: e.value.toJson()}));

  Future<void> saveStats() => kv.setString(_kStats, jsonEncode(stats.toJson()));

  Future<void> saveXp() => kv.setString(_kXp, jsonEncode(xp));

  Future<void> saveBadges() => kv.setString(
      _kBadges, jsonEncode([for (final b in badges) b.name]..sort()));

  List<SavedQuestion> _newestFirst(Map<String, SavedQuestion> m) =>
      m.values.toList()..sort((a, b) => b.savedAt.compareTo(a.savedAt));

  List<SavedQuestion> get bookmarkList => _newestFirst(bookmarks);
  List<SavedQuestion> get mistakeList => _newestFirst(mistakes);

  void _cap(Map<String, SavedQuestion> m) {
    if (m.length <= maxSaved) return;
    final oldest = _newestFirst(m).skip(maxSaved).map((s) => s.question.id).toList();
    oldest.forEach(m.remove);
  }

  Future<void> saveBookmarks() {
    _cap(bookmarks);
    return kv.setString(
        _kBookmarks, jsonEncode([for (final s in bookmarks.values) s.toJson()]));
  }

  Future<void> saveMistakes() {
    _cap(mistakes);
    return kv.setString(
        _kMistakes, jsonEncode([for (final s in mistakes.values) s.toJson()]));
  }

  Future<void> saveSeen() {
    if (seen.length > maxSeen) {
      final keep = seen.skip(seen.length - maxSeen).toList();
      seen
        ..clear()
        ..addAll(keep);
    }
    return kv.setString(_kSeen, jsonEncode(seen.toList()));
  }

  Future<void> saveReports(ReportRateLimiter limiter) {
    reportHistory = limiter.history;
    return kv.setString(_kReports, jsonEncode(limiter.toJson()));
  }
}
