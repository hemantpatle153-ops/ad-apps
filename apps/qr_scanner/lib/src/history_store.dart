import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScanEntry {
  const ScanEntry({required this.value, required this.at});

  final String value;
  final DateTime at;

  Map<String, Object> toJson() => {'v': value, 't': at.millisecondsSinceEpoch};

  static ScanEntry fromJson(Map<String, dynamic> json) => ScanEntry(
        value: json['v'] as String,
        at: DateTime.fromMillisecondsSinceEpoch(json['t'] as int),
      );
}

/// Scan history kept on the device only, newest first.
class HistoryStore extends ChangeNotifier {
  HistoryStore._();

  static final HistoryStore instance = HistoryStore._();

  static const _key = 'scan_history';
  static const _max = 300;

  List<ScanEntry> _entries = [];
  bool _loaded = false;

  List<ScanEntry> get entries => List.unmodifiable(_entries);

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const [];
    _entries = raw
        .map((s) => ScanEntry.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
    _loaded = true;
    notifyListeners();
  }

  Future<void> add(String value) async {
    await load();
    _entries.removeWhere((e) => e.value == value);
    _entries.insert(0, ScanEntry(value: value, at: DateTime.now()));
    if (_entries.length > _max) _entries = _entries.sublist(0, _max);
    await _save();
  }

  Future<void> remove(ScanEntry entry) async {
    _entries.remove(entry);
    await _save();
  }

  Future<void> clear() async {
    _entries = [];
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      _entries.map((e) => jsonEncode(e.toJson())).toList(),
    );
    notifyListeners();
  }
}
