import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What happens when the user leaves the app while a video plays.
enum LeaveAction { pause, pip, audio }

enum VideoSort { name, date, size, duration }

enum FolderSort { name, count, date }

/// One entry of the "Recently played" list.
class RecentItem {
  RecentItem({
    required this.key,
    required this.title,
    required this.uri,
    this.assetId,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    DateTime? playedAt,
  }) : playedAt = playedAt ?? DateTime.now();

  /// Asset id for library videos, the url or path otherwise.
  final String key;
  final String title;
  final String uri;
  final String? assetId;
  final Duration position;
  final Duration duration;
  final DateTime playedAt;

  bool get isNetwork => uri.startsWith('http');

  Map<String, Object?> toJson() => {
        'k': key,
        't': title,
        'u': uri,
        'a': assetId,
        'p': position.inMilliseconds,
        'd': duration.inMilliseconds,
        'at': playedAt.millisecondsSinceEpoch,
      };

  static RecentItem fromJson(Map<String, Object?> j) => RecentItem(
        key: j['k'] as String,
        title: j['t'] as String,
        uri: j['u'] as String,
        assetId: j['a'] as String?,
        position: Duration(milliseconds: (j['p'] as num?)?.toInt() ?? 0),
        duration: Duration(milliseconds: (j['d'] as num?)?.toInt() ?? 0),
        playedAt: DateTime.fromMillisecondsSinceEpoch(
            (j['at'] as num?)?.toInt() ?? 0),
      );
}

/// User settings, resume points and history, kept in SharedPreferences.
class Settings extends ChangeNotifier {
  Settings._(this._p) {
    _load();
  }

  static Future<Settings> open() async =>
      Settings._(await SharedPreferences.getInstance());

  final SharedPreferences _p;

  static const maxRecents = 50;
  static const maxPositions = 500;

  late ThemeMode themeMode;
  late LeaveAction leaveAction;
  late VideoSort videoSort;
  late bool videoSortDesc;
  late FolderSort folderSort;
  late double subtitleSize;
  late int subtitleColor;
  late bool subtitleBackground;
  late double lastSpeed;
  late bool rememberSpeed;
  late bool resume;
  late List<RecentItem> recents;
  late List<String> streamHistory;
  late Map<String, int> _positions;

  void _load() {
    themeMode = ThemeMode.values[_p.getInt('theme') ?? ThemeMode.dark.index];
    leaveAction = LeaveAction.values[_p.getInt('leave') ?? LeaveAction.pip.index];
    videoSort = VideoSort.values[_p.getInt('vsort') ?? VideoSort.date.index];
    videoSortDesc = _p.getBool('vsortDesc') ?? true;
    folderSort = FolderSort.values[_p.getInt('fsort') ?? FolderSort.name.index];
    subtitleSize = _p.getDouble('subSize') ?? 22;
    subtitleColor = _p.getInt('subColor') ?? 0xFFFFFFFF;
    subtitleBackground = _p.getBool('subBg') ?? false;
    lastSpeed = _p.getDouble('speed') ?? 1;
    rememberSpeed = _p.getBool('rememberSpeed') ?? false;
    resume = _p.getBool('resume') ?? true;
    recents = _decodeList('recents')
        .map((e) => RecentItem.fromJson(e.cast<String, Object?>()))
        .toList();
    streamHistory = _p.getStringList('streams') ?? [];
    _positions = (_tryDecode(_p.getString('positions')) as Map?)
            ?.map((k, v) => MapEntry(k as String, (v as num).toInt())) ??
        {};
  }

  static Object? _tryDecode(String? s) {
    if (s == null) return null;
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  List<Map> _decodeList(String key) =>
      ((_tryDecode(_p.getString(key)) as List?) ?? const []).whereType<Map>().toList();

  void setThemeMode(ThemeMode m) {
    themeMode = m;
    _p.setInt('theme', m.index);
    notifyListeners();
  }

  void setLeaveAction(LeaveAction a) {
    leaveAction = a;
    _p.setInt('leave', a.index);
    notifyListeners();
  }

  void setVideoSort(VideoSort s, bool desc) {
    videoSort = s;
    videoSortDesc = desc;
    _p.setInt('vsort', s.index);
    _p.setBool('vsortDesc', desc);
    notifyListeners();
  }

  void setFolderSort(FolderSort s) {
    folderSort = s;
    _p.setInt('fsort', s.index);
    notifyListeners();
  }

  void setSubtitleStyle({double? size, int? color, bool? background}) {
    if (size != null) _p.setDouble('subSize', subtitleSize = size);
    if (color != null) _p.setInt('subColor', subtitleColor = color);
    if (background != null) _p.setBool('subBg', subtitleBackground = background);
    notifyListeners();
  }

  void setSpeed(double speed) {
    lastSpeed = speed;
    _p.setDouble('speed', speed);
  }

  void setRememberSpeed(bool v) {
    rememberSpeed = v;
    _p.setBool('rememberSpeed', v);
    notifyListeners();
  }

  void setResume(bool v) {
    resume = v;
    _p.setBool('resume', v);
    notifyListeners();
  }

  // Resume points ----------------------------------------------------------

  Duration? positionFor(String key) {
    final ms = _positions[key];
    return ms == null ? null : Duration(milliseconds: ms);
  }

  /// Fraction watched (0..1) for the progress bar under a thumbnail.
  double progressFor(String key, Duration duration) {
    final p = _positions[key];
    if (p == null || duration.inMilliseconds <= 0) return 0;
    return (p / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  bool wasPlayed(String key) =>
      _positions.containsKey(key) || recents.any((r) => r.key == key);

  /// Stores where playback stopped. Near the start or end clears it, so a
  /// finished video starts from the beginning next time.
  void savePosition(String key, Duration position, Duration duration) {
    final nearEnd = duration > Duration.zero &&
        duration - position < const Duration(seconds: 5);
    if (position < const Duration(seconds: 5) || nearEnd) {
      _positions.remove(key);
      // Keep a marker that the video was watched to the end.
      if (nearEnd) _positions[key] = 0;
    } else {
      _positions.remove(key);
      _positions[key] = position.inMilliseconds;
    }
    while (_positions.length > maxPositions) {
      _positions.remove(_positions.keys.first);
    }
    _p.setString('positions', jsonEncode(_positions));
  }

  // Recently played --------------------------------------------------------

  void addRecent(RecentItem item) {
    recents.removeWhere((r) => r.key == item.key);
    recents.insert(0, item);
    if (recents.length > maxRecents) recents.removeRange(maxRecents, recents.length);
    _saveRecents();
  }

  void removeRecent(String key) {
    recents.removeWhere((r) => r.key == key);
    _saveRecents();
  }

  void clearRecents() {
    recents.clear();
    _saveRecents();
  }

  void _saveRecents() {
    _p.setString('recents', jsonEncode(recents.map((r) => r.toJson()).toList()));
    notifyListeners();
  }

  void addStream(String url) {
    streamHistory
      ..remove(url)
      ..insert(0, url);
    if (streamHistory.length > 8) streamHistory.removeLast();
    _p.setStringList('streams', streamHistory);
  }

  // Private folder PIN -----------------------------------------------------

  String? get pinHash => _p.getString('pinHash');
  String? get pinSalt => _p.getString('pinSalt');

  void setPin(String salt, String hash) {
    _p.setString('pinSalt', salt);
    _p.setString('pinHash', hash);
  }

  void clearPin() {
    _p.remove('pinSalt');
    _p.remove('pinHash');
  }
}
