import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/json_read.dart';
import '../logic/alerts.dart';
import '../logic/reminder_plan.dart';
import '../models/post.dart';
import '../models/profile.dart';
import 'kv_store.dart';

enum ThemeChoice { system, light, dark }

/// Everything the app remembers on the phone. Nothing here leaves the
/// device.
class AppSettings extends ChangeNotifier {
  AppSettings(this.store);
  final KeyValueStore store;

  static const _lang = 'lang';
  static const _theme = 'theme';
  static const _onboarded = 'onboarded';
  static const _profile = 'profile';
  static const _alerts = 'alerts';
  static const _saved = 'saved';
  static const _reminders = 'reminders';
  static const _reminderTime = 'reminderTime';
  static const _seen = 'seenIds';
  static const _lastCheck = 'lastAlertCheck';
  static const _permissionAsked = 'notifAsked';

  /// Parsed values, cleared on every write so reads stay cheap in lists.
  final Map<String, Object?> _memo = {};

  T _cached<T>(String key, T Function() read) {
    if (_memo.containsKey(key)) return _memo[key] as T;
    final v = read();
    _memo[key] = v;
    return v;
  }

  Object? _json(String key) {
    final raw = store.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  Future<void> _put(String key, Object? value) async {
    _memo.clear();
    await store.setString(key, jsonEncode(value));
    notifyListeners();
  }

  /// Null until the user picks a language on first run.
  AppLang? get langOrNull => AppLang.tryParse(store.getString(_lang));
  AppLang get lang => langOrNull ?? AppLang.en;
  Future<void> setLang(AppLang l) async {
    _memo.clear();
    await store.setString(_lang, l.name);
    notifyListeners();
  }

  ThemeChoice get theme => ThemeChoice.values
      .firstWhere((t) => t.name == store.getString(_theme), orElse: () => ThemeChoice.system);
  Future<void> setTheme(ThemeChoice t) async {
    await store.setString(_theme, t.name);
    notifyListeners();
  }

  bool get onboarded => store.getString(_onboarded) == 'true';
  Future<void> setOnboarded() async {
    await store.setString(_onboarded, 'true');
    notifyListeners();
  }

  UserProfile get profile =>
      _cached(_profile, () => UserProfile.fromJson(_json(_profile)));
  Future<void> setProfile(UserProfile p) => _put(_profile, p.toJson());

  AlertPrefs get alertPrefs =>
      _cached(_alerts, () => AlertPrefs.fromJson(_json(_alerts)));
  Future<void> setAlertPrefs(AlertPrefs p) => _put(_alerts, p.toJson());

  /// Saved jobs, most recently saved first. Stored as summaries so the list
  /// still works after a post leaves the feed.
  List<PostSummary> get saved => _cached(_saved, () => List<PostSummary>.unmodifiable([
        for (final e in readList(_json(_saved)))
          if (PostSummary.tryParse(e) != null) PostSummary.tryParse(e)!,
      ]));

  Set<String> get savedIds => _cached('$_saved.ids', () => {for (final p in saved) p.id});

  bool isSaved(String id) => savedIds.contains(id);

  Future<void> setSaved(PostSummary p, bool saved) async {
    final list = this.saved.where((e) => e.id != p.id).toList();
    if (saved) list.insert(0, p);
    await _put(_saved, [for (final e in list) e.toJson()]);
  }

  /// Refreshes stored summaries with newer copies from the feed (a changed
  /// last date, for example).
  Future<bool> refreshSaved(Iterable<PostSummary> fresh) async {
    final byId = {for (final p in fresh) p.id: p};
    var changed = false;
    final list = <PostSummary>[];
    for (final p in saved) {
      final f = byId[p.id];
      if (f != null && jsonEncode(f.toJson()) != jsonEncode(p.toJson())) {
        list.add(f);
        changed = true;
      } else {
        list.add(p);
      }
    }
    if (changed) await _put(_saved, [for (final e in list) e.toJson()]);
    return changed;
  }

  /// Posts with a last-date reminder.
  Set<String> get reminders => {
        ..._cached(_reminders, () => {
              for (final e in readList(_json(_reminders)))
                if (isValidPostId(e)) e as String,
            }),
      };

  bool hasReminder(String id) => reminders.contains(id);

  Future<void> setReminder(String id, bool on) {
    final set = reminders;
    on ? set.add(id) : set.remove(id);
    return _put(_reminders, set.toList()..sort());
  }

  /// Reminder time of day, India time, as (hour, minute).
  (int, int) get reminderTime {
    final m = readMap(_json(_reminderTime));
    final h = readInt(m?['h'], min: 0, max: 23);
    final min = readInt(m?['m'], min: 0, max: 59);
    if (h == null || min == null) return (defaultReminderHour, defaultReminderMinute);
    return (h, min);
  }

  Future<void> setReminderTime(int hour, int minute) =>
      _put(_reminderTime, {'h': hour, 'm': minute});

  /// Post ids already considered for alerts; null before the first check.
  List<String>? get seenIds {
    final v = _json(_seen);
    if (v is! List) return null;
    return [for (final e in v) if (e is String) e];
  }

  Future<void> setSeenIds(List<String> ids) async {
    // Written by the background check; no listeners to wake there.
    await store.setString(_seen, jsonEncode(ids));
  }

  DateTime? get lastAlertCheck => readInstant(store.getString(_lastCheck));
  Future<void> setLastAlertCheck(DateTime t) =>
      store.setString(_lastCheck, t.toUtc().toIso8601String());

  bool get notificationPermissionAsked => store.getString(_permissionAsked) == 'true';
  Future<void> setNotificationPermissionAsked() =>
      store.setString(_permissionAsked, 'true');

  Future<void> reload() async {
    _memo.clear();
    await store.reload();
    notifyListeners();
  }
}
