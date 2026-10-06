import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_app/src/player/player_sheets.dart'
    show speeds, subtitleColors;
import 'package:video_player_app/src/settings.dart';

import 'support/fixtures.dart';

Future<Settings> fresh([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  return Settings.open();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RecentItem json round trip', () {
    final r = Random(11);
    for (var i = 0; i < 60; i++) {
      final key = i.isEven
          ? '${1000 + i}'
          : 'https://cdn.example.com/v/${randomWord(r)}.mp4';
      final title = '${randomWord(r)} ${i % 3 == 0 ? 'é✓ 日本' : ''}'.trim();
      final assetId = i % 4 == 0 ? null : '${r.nextInt(99999)}';
      final pos = Duration(milliseconds: r.nextInt(7200000));
      final dur = Duration(milliseconds: r.nextInt(7200000));
      final at = DateTime.fromMillisecondsSinceEpoch(
          1600000000000 + r.nextInt(1 << 31));
      test('item #$i ($key) survives toJson/jsonEncode/fromJson', () {
        final item = RecentItem(
            key: key,
            title: title,
            uri: key,
            assetId: assetId,
            position: pos,
            duration: dur,
            playedAt: at);
        final back = RecentItem.fromJson(
            (jsonDecode(jsonEncode(item.toJson())) as Map)
                .cast<String, Object?>());
        expect(back.key, key);
        expect(back.title, title);
        expect(back.uri, key);
        expect(back.assetId, assetId);
        expect(back.position, pos);
        expect(back.duration, dur);
        expect(back.playedAt, at);
        expect(back.isNetwork, key.startsWith('http'));
      });
    }

    test('missing numbers default to zero', () {
      final r = RecentItem.fromJson({'k': 'a', 't': 'A', 'u': 'u'});
      expect(r.position, Duration.zero);
      expect(r.duration, Duration.zero);
      expect(r.playedAt.millisecondsSinceEpoch, 0);
      expect(r.assetId, isNull);
    });

    test('double numbers are truncated to int ms', () {
      final r = RecentItem.fromJson(
          {'k': 'a', 't': 'A', 'u': 'u', 'p': 1500.7, 'd': 9000.2, 'at': 5.9});
      expect(r.position, const Duration(milliseconds: 1500));
      expect(r.duration, const Duration(milliseconds: 9000));
      expect(r.playedAt.millisecondsSinceEpoch, 5);
    });

    test('playedAt defaults to now', () {
      final before = DateTime.now();
      final r = RecentItem(key: 'a', title: 'A', uri: 'u');
      expect(r.playedAt.isBefore(before), isFalse);
      expect(r.playedAt.isAfter(DateTime.now()), isFalse);
    });

    test('toJson uses the short keys', () {
      final j =
          RecentItem(key: 'a', title: 'A', uri: 'u', assetId: '9').toJson();
      expect(j.keys.toSet(), {'k', 't', 'u', 'a', 'p', 'd', 'at'});
    });
  });

  group('RecentItem.isNetwork', () {
    const table = {
      'http://a.com/x.mp4': true,
      'https://a.com/x.m3u8': true,
      'HTTP://A.COM': false,
      'content://media/external/video/media/1': false,
      '/storage/emulated/0/Movies/a.mp4': false,
      'file:///sdcard/a.mkv': false,
      'rtsp://cam/stream': false,
      '': false,
    };
    table.forEach((uri, expected) {
      test('"$uri" -> $expected', () {
        expect(RecentItem(key: uri, title: 't', uri: uri).isNetwork, expected);
      });
    });
  });

  group('Settings defaults', () {
    late Settings s;
    setUp(() async => s = await fresh());
    final checks = <String, void Function(Settings)>{
      'theme is dark': (s) => expect(s.themeMode, ThemeMode.dark),
      'leave action is pip': (s) => expect(s.leaveAction, LeaveAction.pip),
      'video sort is date': (s) => expect(s.videoSort, VideoSort.date),
      'video sort is descending': (s) => expect(s.videoSortDesc, isTrue),
      'folder sort is name': (s) => expect(s.folderSort, FolderSort.name),
      'subtitle size is 22': (s) => expect(s.subtitleSize, 22),
      'subtitle colour is white': (s) => expect(s.subtitleColor, 0xFFFFFFFF),
      'subtitle background off': (s) => expect(s.subtitleBackground, isFalse),
      'speed is 1x': (s) => expect(s.lastSpeed, 1),
      'remember speed off': (s) => expect(s.rememberSpeed, isFalse),
      'resume on': (s) => expect(s.resume, isTrue),
      'no recents': (s) => expect(s.recents, isEmpty),
      'no stream history': (s) => expect(s.streamHistory, isEmpty),
      'no PIN': (s) => expect(s.pinHash, isNull),
      'no salt': (s) => expect(s.pinSalt, isNull),
      'no resume point': (s) => expect(s.positionFor('x'), isNull),
    };
    checks.forEach((name, check) => test(name, () => check(s)));
  });

  group('Settings persist across reopen', () {
    for (final m in ThemeMode.values) {
      test('theme $m', () async {
        final s = await fresh();
        var n = 0;
        s.addListener(() => n++);
        s.setThemeMode(m);
        expect(n, 1);
        expect((await Settings.open()).themeMode, m);
      });
    }
    for (final a in LeaveAction.values) {
      test('leave action $a', () async {
        final s = await fresh();
        var n = 0;
        s.addListener(() => n++);
        s.setLeaveAction(a);
        expect(n, 1);
        expect((await Settings.open()).leaveAction, a);
      });
    }
    for (final v in VideoSort.values) {
      for (final desc in [true, false]) {
        test('video sort $v desc=$desc', () async {
          final s = await fresh();
          s.setVideoSort(v, desc);
          final again = await Settings.open();
          expect(again.videoSort, v);
          expect(again.videoSortDesc, desc);
        });
      }
    }
    for (final f in FolderSort.values) {
      test('folder sort $f', () async {
        final s = await fresh();
        s.setFolderSort(f);
        expect((await Settings.open()).folderSort, f);
      });
    }
    for (final size in [12.0, 16.0, 18.5, 22.0, 28.0, 36.0, 48.0]) {
      test('subtitle size $size leaves colour and background alone', () async {
        final s = await fresh();
        s.setSubtitleStyle(size: size);
        final again = await Settings.open();
        expect(again.subtitleSize, size);
        expect(again.subtitleColor, 0xFFFFFFFF);
        expect(again.subtitleBackground, isFalse);
      });
    }
    for (final c in subtitleColors) {
      test('subtitle colour 0x${c.toRadixString(16)}', () async {
        final s = await fresh();
        s.setSubtitleStyle(color: c);
        final again = await Settings.open();
        expect(again.subtitleColor, c);
        expect(again.subtitleSize, 22);
      });
    }
    for (final bg in [true, false]) {
      test('subtitle background $bg', () async {
        final s = await fresh({'subBg': !bg});
        var n = 0;
        s.addListener(() => n++);
        s.setSubtitleStyle(background: bg);
        expect(n, 1);
        expect((await Settings.open()).subtitleBackground, bg);
      });
    }
    for (final sp in speeds) {
      test('speed $sp persists without notifying', () async {
        final s = await fresh();
        var n = 0;
        s.addListener(() => n++);
        s.setSpeed(sp);
        expect(n, 0);
        expect(s.lastSpeed, sp);
        expect((await Settings.open()).lastSpeed, sp);
      });
    }
    for (final v in [true, false]) {
      test('remember speed $v', () async {
        final s = await fresh({'rememberSpeed': !v});
        s.setRememberSpeed(v);
        expect((await Settings.open()).rememberSpeed, v);
      });
      test('resume $v', () async {
        final s = await fresh({'resume': !v});
        s.setResume(v);
        expect((await Settings.open()).resume, v);
      });
    }
  });

  group('Settings loads stored prefs', () {
    for (final m in ThemeMode.values) {
      test('stored theme index ${m.index}', () async {
        expect((await fresh({'theme': m.index})).themeMode, m);
      });
    }
    for (final a in LeaveAction.values) {
      test('stored leave index ${a.index}', () async {
        expect((await fresh({'leave': a.index})).leaveAction, a);
      });
    }
    for (final bad in ['not json', '{', '[1,', '']) {
      test('corrupt recents "$bad" load as empty', () async {
        expect((await fresh({'recents': bad})).recents, isEmpty);
      });
      test('corrupt positions "$bad" load as empty', () async {
        expect((await fresh({'positions': bad})).positionFor('a'), isNull);
      });
    }
    test('non-map entries in recents are skipped', () async {
      final s = await fresh({
        'recents': jsonEncode([
          1,
          'x',
          {'k': 'a', 't': 'A', 'u': 'u'},
          null,
        ])
      });
      expect(s.recents.map((r) => r.key), ['a']);
    });
    test('stored positions are read', () async {
      final s = await fresh({
        'positions': jsonEncode({'a': 12000, 'b': 0})
      });
      expect(s.positionFor('a'), const Duration(seconds: 12));
      expect(s.positionFor('b'), Duration.zero);
      expect(s.wasPlayed('b'), isTrue);
    });
  });

  group('savePosition table', () {
    // (position s, duration s) -> expected stored position (null = none).
    const cases = <(int, int), int?>{
      (0, 600): null,
      (4, 600): null,
      (5, 600): 5,
      (180, 600): 180,
      (594, 600): 594,
      (595, 600): 595,
      (596, 600): 0,
      (600, 600): 0,
      (700, 600): 0,
      (30, 0): 30,
      (3, 0): null,
      (6, 12): 6,
      (6, 10): 0,
      (5, 9): 0,
      (7, 8): 0,
    };
    cases.forEach((pd, expected) {
      test('pos ${pd.$1}s of ${pd.$2}s -> $expected', () async {
        final s = await fresh();
        s.savePosition('k', Duration(seconds: pd.$1), Duration(seconds: pd.$2));
        final got = s.positionFor('k');
        expect(got, expected == null ? isNull : Duration(seconds: expected));
        expect(s.wasPlayed('k'), expected != null);
        final again = await Settings.open();
        expect(again.positionFor('k'), got);
      });
    });
  });

  group('savePosition random', () {
    final r = Random(5);
    for (var i = 0; i < 60; i++) {
      final durMs = r.nextInt(3) == 0 ? 0 : 1000 + r.nextInt(7200000);
      final posMs = r.nextInt(max(durMs, 60000) + 20000);
      test('case $i: $posMs ms of $durMs ms', () async {
        final s = await fresh();
        final pos = Duration(milliseconds: posMs),
            dur = Duration(milliseconds: durMs);
        s.savePosition('k', pos, dur);
        final nearEnd = durMs > 0 && durMs - posMs < 5000;
        if (nearEnd) {
          expect(s.positionFor('k'), Duration.zero);
          expect(s.progressFor('k', dur), 0);
        } else if (posMs < 5000) {
          expect(s.positionFor('k'), isNull);
          expect(s.progressFor('k', dur), 0);
        } else {
          expect(s.positionFor('k'), pos);
          if (durMs > 0) {
            expect(s.progressFor('k', dur), closeTo(posMs / durMs, 1e-9));
          } else {
            expect(s.progressFor('k', dur), 0);
          }
        }
      });
    }
  });

  group('progressFor', () {
    for (final (pos, dur, expected) in [
      (60, 600, 0.1),
      (300, 600, 0.5),
      (590, 600, 590 / 600),
      (120, 60, 1.0),
      (60, 0, 0.0),
      (60, -10, 0.0),
    ]) {
      test('$pos s stored, asked with $dur s -> $expected', () async {
        final s = await fresh({
          'positions': jsonEncode({'a': pos * 1000})
        });
        expect(s.progressFor('a', Duration(seconds: dur)),
            closeTo(expected, 1e-9));
      });
    }
    test('unknown key -> 0', () async {
      expect((await fresh()).progressFor('zz', const Duration(minutes: 5)), 0);
    });
  });

  group('resume point limits', () {
    test('keeps only the newest ${Settings.maxPositions}', () async {
      final s = await fresh();
      const d = Duration(hours: 1);
      for (var i = 0; i < Settings.maxPositions + 7; i++) {
        s.savePosition('v$i', const Duration(minutes: 1), d);
      }
      for (var i = 0; i < 7; i++) {
        expect(s.positionFor('v$i'), isNull, reason: 'v$i');
      }
      expect(s.positionFor('v7'), const Duration(minutes: 1));
      expect(s.positionFor('v${Settings.maxPositions + 6}'),
          const Duration(minutes: 1));
    });
    test('saving again refreshes recency so it is not evicted', () async {
      final s = await fresh();
      const d = Duration(hours: 1);
      for (var i = 0; i < Settings.maxPositions; i++) {
        s.savePosition('v$i', const Duration(minutes: 1), d);
      }
      s.savePosition('v0', const Duration(minutes: 2), d);
      s.savePosition('new', const Duration(minutes: 1), d);
      expect(s.positionFor('v0'), const Duration(minutes: 2));
      expect(s.positionFor('v1'), isNull);
    });
    test('clearing near the start removes an old point', () async {
      final s = await fresh();
      s.savePosition(
          'a', const Duration(minutes: 3), const Duration(minutes: 10));
      s.savePosition(
          'a', const Duration(seconds: 1), const Duration(minutes: 10));
      expect(s.positionFor('a'), isNull);
    });
  });

  group('recents model check', () {
    for (var seed = 0; seed < 30; seed++) {
      test('random ops seed $seed match a reference list', () async {
        final s = await fresh();
        final r = Random(seed);
        final model = <String>[];
        var notified = 0;
        s.addListener(() => notified++);
        var ops = 0;
        for (var i = 0; i < 80; i++) {
          final op = r.nextInt(10);
          final key = 'k${r.nextInt(70)}';
          if (op < 7) {
            s.addRecent(RecentItem(key: key, title: key, uri: 'u'));
            model
              ..remove(key)
              ..insert(0, key);
            if (model.length > Settings.maxRecents) {
              model.removeRange(Settings.maxRecents, model.length);
            }
          } else if (op < 9) {
            s.removeRecent(key);
            model.remove(key);
          } else {
            s.clearRecents();
            model.clear();
          }
          ops++;
        }
        expect(s.recents.map((e) => e.key).toList(), model);
        expect(notified, ops);
        expect(
            (await Settings.open()).recents.map((e) => e.key).toList(), model);
        for (final k in model) {
          expect(s.wasPlayed(k), isTrue);
        }
      });
    }
    test('caps at ${Settings.maxRecents}', () async {
      final s = await fresh();
      for (var i = 0; i < 75; i++) {
        s.addRecent(RecentItem(key: '$i', title: '$i', uri: 'u'));
      }
      expect(s.recents.length, Settings.maxRecents);
      expect(s.recents.first.key, '74');
      expect(s.recents.last.key, '25');
    });
  });

  group('stream history model check', () {
    for (var seed = 0; seed < 30; seed++) {
      test('random urls seed $seed keep 8 newest unique', () async {
        final s = await fresh();
        final r = Random(100 + seed);
        final model = <String>[];
        for (var i = 0; i < 25; i++) {
          final url = 'https://host${r.nextInt(12)}.tv/live.m3u8';
          s.addStream(url);
          model
            ..remove(url)
            ..insert(0, url);
          if (model.length > 8) model.removeLast();
        }
        expect(s.streamHistory, model);
        expect(s.streamHistory.toSet().length, s.streamHistory.length);
        expect((await Settings.open()).streamHistory, model);
      });
    }
  });

  group('PIN storage', () {
    test('setPin stores salt and hash', () async {
      final s = await fresh();
      s.setPin('salt', 'hash');
      final again = await Settings.open();
      expect(again.pinSalt, 'salt');
      expect(again.pinHash, 'hash');
    });
    test('clearPin removes both', () async {
      final s = await fresh({'pinSalt': 'a', 'pinHash': 'b'});
      s.clearPin();
      expect(s.pinSalt, isNull);
      expect(s.pinHash, isNull);
      expect((await Settings.open()).pinHash, isNull);
    });
  });
}
