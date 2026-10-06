import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'model.dart';

/// A log this phone has joined, with the last copy it saw. The copy keeps a
/// cleared hisab readable on the phone after the cloud copy is deleted.
class LocalLog {
  const LocalLog({
    required this.id,
    required this.side,
    required this.nameA,
    required this.nameB,
    this.snapshot,
    this.archived = false,
  });

  final String id;

  /// Which friend this phone is.
  final Side side;
  final String nameA;
  final String nameB;

  /// Last seen log, as stored in the database.
  final Map<String, Object?>? snapshot;

  /// The cloud copy is gone; only this phone's copy is left.
  final bool archived;

  String get myName => side == Side.a ? nameA : nameB;
  String get friendName => side == Side.a ? nameB : nameA;

  HisabLog? get log => HisabLog.fromJson(id, snapshot);

  LocalLog copyWith({
    Side? side,
    String? nameA,
    String? nameB,
    Map<String, Object?>? snapshot,
    bool? archived,
  }) =>
      LocalLog(
        id: id,
        side: side ?? this.side,
        nameA: nameA ?? this.nameA,
        nameB: nameB ?? this.nameB,
        snapshot: snapshot ?? this.snapshot,
        archived: archived ?? this.archived,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'side': side.name,
        'a': nameA,
        'b': nameB,
        if (snapshot != null) 'snap': snapshot,
        if (archived) 'archived': true,
      };

  static LocalLog? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String) return null;
    final side = Side.parse(raw['side']);
    if (side == null) return null;
    final snap = raw['snap'];
    return LocalLog(
      id: raw['id'] as String,
      side: side,
      nameA: '${raw['a'] ?? 'Friend 1'}',
      nameB: '${raw['b'] ?? 'Friend 2'}',
      snapshot: snap is Map ? snap.cast<String, Object?>() : null,
      archived: raw['archived'] == true,
    );
  }
}

/// The logs on this phone, newest first, in shared preferences.
class HisabStore extends ChangeNotifier {
  HisabStore(this._p);
  final SharedPreferences _p;

  static const _key = 'hisab_logs_v1';
  static const _nameKey = 'hisab_my_name';

  static Future<HisabStore> load() async =>
      HisabStore(await SharedPreferences.getInstance());

  List<LocalLog> all() {
    final raw = _p.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return [
        for (final x in list)
          if (LocalLog.fromJson(x) case final l?) l
      ];
    } on FormatException {
      return [];
    }
  }

  LocalLog? byId(String id) {
    for (final l in all()) {
      if (l.id == id) return l;
    }
    return null;
  }

  Future<void> _save(List<LocalLog> list) async {
    await _p.setString(_key, jsonEncode([for (final l in list) l.toJson()]));
    notifyListeners();
  }

  /// Adds or replaces, keeping the list order (new logs go first).
  Future<void> put(LocalLog log) {
    final list = all();
    final i = list.indexWhere((l) => l.id == log.id);
    if (i >= 0) {
      list[i] = log;
    } else {
      list.insert(0, log);
    }
    return _save(list);
  }

  Future<void> remove(String id) =>
      _save(all()..removeWhere((l) => l.id == id));

  /// Remembers the latest cloud copy of a log.
  Future<void> remember(String id, Side side, HisabLog log) {
    final old = byId(id);
    return put(LocalLog(
      id: id,
      side: side,
      nameA: log.nameA,
      nameB: log.nameB,
      snapshot: log.toJson(),
      archived: old?.archived ?? false,
    ));
  }

  /// The name this phone's owner used last, to fill in next time.
  String get myName => _p.getString(_nameKey) ?? '';
  set myName(String v) => _p.setString(_nameKey, v);
}
