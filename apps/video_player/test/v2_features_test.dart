import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_app/src/player/effects.dart';
import 'package:video_player_app/src/settings.dart';

import 'support/fixtures.dart';

Future<Settings> fresh([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  return Settings.open();
}

/// Reopens from the same mock store, like an app restart.
Future<Settings> reopen() => Settings.open();

List<String> eqParts(String filter) {
  if (filter.isEmpty) return [];
  expect(filter, startsWith('lavfi=['));
  expect(filter, endsWith(']'));
  return filter.substring(7, filter.length - 1).split(',');
}

void main() {
  group('eqBands', () {
    test('ten ascending octave bands from 31 Hz to 16 kHz', () {
      expect(eqBands.length, 10);
      expect(eqBands.first, 31);
      expect(eqBands.last, 16000);
      for (var i = 1; i < eqBands.length; i++) {
        expect(eqBands[i], greaterThan(eqBands[i - 1]));
        expect(eqBands[i] / eqBands[i - 1], closeTo(2, 0.05));
      }
    });
  });

  group('eqPresets', () {
    test('Flat is first and all zero', () {
      expect(eqPresets.keys.first, 'Flat');
      expect(eqPresets['Flat'], everyElement(0));
    });
    test('has the nine named presets', () {
      expect(eqPresets.keys, [
        'Flat', 'Bass boost', 'Movie', 'Vocal', 'Rock', 'Pop', 'Jazz', 'Classical',
        'Treble boost',
      ]);
    });
    eqPresets.forEach((name, gains) {
      test('$name has one gain per band within the slider range', () {
        expect(gains.length, eqBands.length);
        for (final g in gains) {
          expect(g, inInclusiveRange(-12, 12));
        }
      });
      test('$name builds a filter with one equalizer per non-zero band', () {
        final parts = eqParts(audioFilter(gains, night: false));
        final nonZero = [for (var i = 0; i < 10; i++) if (gains[i] != 0) i];
        expect(parts.length, nonZero.length);
        for (var k = 0; k < nonZero.length; k++) {
          final i = nonZero[k];
          expect(parts[k],
              'equalizer=f=${eqBands[i]}:width_type=o:width=1:g=${gains[i].toStringAsFixed(1)}');
        }
      });
      test('$name with night mode ends with dynaudnorm', () {
        final parts = eqParts(audioFilter(gains, night: true));
        expect(parts.last, 'dynaudnorm=f=250:g=15');
        expect(parts.where((p) => p.startsWith('dynaudnorm')).length, 1);
      });
    });
    test('Bass boost lifts lows only', () {
      final g = eqPresets['Bass boost']!;
      expect(g.take(5), everyElement(greaterThan(0)));
      expect(g.skip(5), everyElement(0));
    });
    test('Treble boost lifts highs only', () {
      final g = eqPresets['Treble boost']!;
      expect(g.take(5), everyElement(0));
      expect(g.skip(5), everyElement(greaterThan(0)));
    });
  });

  group('audioFilter table', () {
    final z = List<double>.filled(10, 0);
    List<double> one(int i, double g) => [...z]..[i] = g;
    final cases = <String, (List<double>, bool, String)>{
      'flat, day': (z, false, ''),
      'flat, night': (z, true, 'lavfi=[dynaudnorm=f=250:g=15]'),
      'empty gains': (const [], false, ''),
      'empty gains night': (const [], true, 'lavfi=[dynaudnorm=f=250:g=15]'),
      '0.05 is below threshold': (one(0, 0.05), false, ''),
      '-0.09 is below threshold': (one(3, -0.09), false, ''),
      '0.1 counts': (one(0, 0.1), false, 'lavfi=[equalizer=f=31:width_type=o:width=1:g=0.1]'),
      '-0.1 counts': (one(9, -0.1), false,
          'lavfi=[equalizer=f=16000:width_type=o:width=1:g=-0.1]'),
      'whole dB gets .0': (one(5, 4), false,
          'lavfi=[equalizer=f=1000:width_type=o:width=1:g=4.0]'),
      'max boost': (one(2, 12), false, 'lavfi=[equalizer=f=125:width_type=o:width=1:g=12.0]'),
      'max cut': (one(7, -12), false,
          'lavfi=[equalizer=f=4000:width_type=o:width=1:g=-12.0]'),
      'eq then night': (one(1, 3), true,
          'lavfi=[equalizer=f=62:width_type=o:width=1:g=3.0,dynaudnorm=f=250:g=15]'),
      'short list uses first bands': (const [2, 0, -2], false,
          'lavfi=[equalizer=f=31:width_type=o:width=1:g=2.0,'
              'equalizer=f=125:width_type=o:width=1:g=-2.0]'),
      'extra gains are ignored': ([...z, 9, 9], false, ''),
    };
    cases.forEach((name, c) {
      test(name, () => expect(audioFilter(c.$1, night: c.$2), c.$3));
    });
  });

  group('audioFilter random gains', () {
    final r = Random(2024);
    for (var i = 0; i < 40; i++) {
      final gains = [
        for (var b = 0; b < 10; b++) r.nextInt(5) == 0 ? 0.0 : (r.nextInt(241) - 120) / 10
      ];
      final night = r.nextBool();
      test('#$i night=$night $gains', () {
        final parts = eqParts(audioFilter(gains, night: night));
        final bands = [for (var b = 0; b < 10; b++) if (gains[b].abs() >= 0.1) b];
        expect(parts.length, bands.length + (night ? 1 : 0));
        for (var k = 0; k < bands.length; k++) {
          final m = RegExp(r'^equalizer=f=(\d+):width_type=o:width=1:g=(-?\d+\.\d)$')
              .firstMatch(parts[k])!;
          expect(int.parse(m.group(1)!), eqBands[bands[k]]);
          expect(double.parse(m.group(2)!), closeTo(gains[bands[k]], 0.051));
        }
      });
    }
  });

  group('VideoAdjust', () {
    test('starts at default', () {
      final a = VideoAdjust();
      expect(a.isDefault, isTrue);
      expect([a.brightness, a.contrast, a.saturation, a.gamma, a.hue, a.rotate],
          everyElement(0));
      expect(a.mirror, isFalse);
    });
    final changes = <String, void Function(VideoAdjust, int)>{
      'brightness': (a, v) => a.brightness = v,
      'contrast': (a, v) => a.contrast = v,
      'saturation': (a, v) => a.saturation = v,
      'gamma': (a, v) => a.gamma = v,
      'hue': (a, v) => a.hue = v,
      'rotate': (a, v) => a.rotate = v,
    };
    changes.forEach((field, set) {
      for (final v in [-100, -5, 1, 90, 100]) {
        test('$field=$v is not default, back to 0 is', () {
          final a = VideoAdjust();
          set(a, v);
          expect(a.isDefault, isFalse);
          set(a, 0);
          expect(a.isDefault, isTrue);
        });
      }
    });
    test('mirror alone is not default', () {
      final a = VideoAdjust()..mirror = true;
      expect(a.isDefault, isFalse);
    });
  });

  group('v2 settings defaults', () {
    late Settings s;
    setUp(() async => s = await fresh());
    final checks = <String, void Function(Settings)>{
      'double tap seeks 10 s': (s) => expect(s.doubleTapSeconds, 10),
      'hardware decoding on': (s) => expect(s.hardwareDecoding, isTrue),
      'list view, not grid': (s) => expect(s.gridView, isFalse),
      'no hidden folders': (s) => expect(s.hiddenFolders, isEmpty),
      'no party name': (s) => expect(s.partyName, ''),
      'flat equalizer': (s) => expect(s.eqGains, List.filled(10, 0.0)),
      'night mode off': (s) => expect(s.nightMode, isFalse),
      'subtitle lift 0': (s) => expect(s.subtitleLift, 0),
      'no bookmarks': (s) => expect(s.bookmarksFor('any'), isEmpty),
    };
    checks.forEach((name, check) => test(name, () => check(s)));
  });

  group('v2 settings persist across reopen', () {
    for (final v in [5, 10, 15, 20, 30, 60]) {
      test('double tap $v s', () async {
        (await fresh()).setDoubleTapSeconds(v);
        expect((await reopen()).doubleTapSeconds, v);
      });
    }
    for (final v in [true, false]) {
      test('hardware decoding $v', () async {
        (await fresh({'hwdec': !v})).setHardwareDecoding(v);
        expect((await reopen()).hardwareDecoding, v);
      });
      test('grid view $v', () async {
        (await fresh({'grid': !v})).setGridView(v);
        expect((await reopen()).gridView, v);
      });
      test('night mode $v via setEq', () async {
        (await fresh()).setEq(List.filled(10, 0), night: v);
        expect((await reopen()).nightMode, v);
      });
    }
    for (final lift in [0.0, 12.5, 40.0, 100.0]) {
      test('subtitle lift $lift keeps size', () async {
        final s = await fresh();
        s.setSubtitleStyle(lift: lift);
        final again = await reopen();
        expect(again.subtitleLift, lift);
        expect(again.subtitleSize, 22);
      });
    }
    final names = <String, String>{
      'Rahul': 'Rahul',
      '  Asha  ': 'Asha',
      '\tMy Phone\n': 'My Phone',
      '   ': '',
      'राम का फ़ोन': 'राम का फ़ोन',
      'A & B': 'A & B',
    };
    names.forEach((input, stored) {
      test('party name "$input" stored as "$stored"', () async {
        final s = await fresh();
        s.setPartyName(input);
        expect(s.partyName, stored);
        expect((await reopen()).partyName, stored);
      });
    });
  });

  group('equalizer gains storage', () {
    test('setEq copies the list', () async {
      final s = await fresh();
      final g = List<double>.filled(10, 1);
      s.setEq(g);
      g[0] = 9;
      expect(s.eqGains[0], 1);
    });
    test('setEq without night keeps night mode', () async {
      final s = await fresh({'night': true});
      s.setEq(List.filled(10, 2));
      expect(s.nightMode, isTrue);
      expect((await reopen()).nightMode, isTrue);
    });
    final r = Random(7);
    for (var i = 0; i < 20; i++) {
      final gains = [for (var b = 0; b < 10; b++) (r.nextInt(2401) - 1200) / 100];
      test('#$i saved to one decimal and read back', () async {
        (await fresh()).setEq(gains);
        final back = (await reopen()).eqGains;
        expect(back.length, 10);
        for (var b = 0; b < 10; b++) {
          expect(back[b], double.parse(gains[b].toStringAsFixed(1)));
        }
      });
    }
    eqPresets.forEach((name, g) {
      test('preset $name survives a restart exactly', () async {
        (await fresh()).setEq(g);
        expect((await reopen()).eqGains, g);
      });
    });
    final stored = <String, (List<String>, List<double>)>{
      'wrong length resets to flat': (['1', '2', '3'], List.filled(10, 0)),
      'too many resets to flat': (List.filled(11, '1'), List.filled(10, 0)),
      'bad numbers become 0': (
        ['1.5', 'x', '', '-2', 'NaNx', '3', '4', '5', '6', '7'],
        [1.5, 0, 0, -2, 0, 3, 4, 5, 6, 7]
      ),
      'valid list loads': (
        ['0.0', '1.0', '2.0', '3.0', '4.0', '5.0', '6.0', '7.0', '8.0', '9.0'],
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
      ),
    };
    stored.forEach((name, c) {
      test(name, () async {
        expect((await fresh({'eq': c.$1})).eqGains, c.$2);
      });
    });
  });

  group('hidden folders', () {
    test('hide, unhide and persist', () async {
      final s = await fresh();
      s.setFolderHidden('a', true);
      s.setFolderHidden('b', true);
      s.setFolderHidden('a', false);
      expect(s.hiddenFolders, {'b'});
      expect((await reopen()).hiddenFolders, {'b'});
    });
    test('unhiding an unknown folder is harmless', () async {
      final s = await fresh();
      s.setFolderHidden('zzz', false);
      expect(s.hiddenFolders, isEmpty);
    });
    test('stored list loads as a set', () async {
      expect((await fresh({'hiddenFolders': ['x', 'y', 'x']})).hiddenFolders, {'x', 'y'});
    });
    for (var seed = 0; seed < 12; seed++) {
      test('random ops seed $seed match a reference set', () async {
        final r = Random(seed);
        final s = await fresh();
        final ref = <String>{};
        for (var i = 0; i < 40; i++) {
          final id = 'f${r.nextInt(8)}';
          final hide = r.nextBool();
          s.setFolderHidden(id, hide);
          hide ? ref.add(id) : ref.remove(id);
        }
        expect(s.hiddenFolders, ref);
        expect((await reopen()).hiddenFolders, ref);
      });
    }
  });

  group('bookmarks', () {
    test('kept sorted regardless of insert order', () async {
      final s = await fresh();
      for (final sec in [50, 10, 30, 20, 40]) {
        s.addBookmark('v', Duration(seconds: sec));
      }
      expect(s.bookmarksFor('v').map((d) => d.inSeconds), [10, 20, 30, 40, 50]);
    });
    test('keys are independent', () async {
      final s = await fresh();
      s.addBookmark('a', const Duration(seconds: 1));
      s.addBookmark('b', const Duration(seconds: 2));
      expect(s.bookmarksFor('a'), [const Duration(seconds: 1)]);
      expect(s.bookmarksFor('b'), [const Duration(seconds: 2)]);
    });
    test('millisecond precision survives a restart', () async {
      (await fresh()).addBookmark('v', const Duration(milliseconds: 61234));
      expect((await reopen()).bookmarksFor('v'), [const Duration(milliseconds: 61234)]);
    });
    test('removing the last one drops the key from storage', () async {
      final s = await fresh();
      s.addBookmark('v', const Duration(seconds: 3));
      s.removeBookmark('v', const Duration(seconds: 3));
      expect(s.bookmarksFor('v'), isEmpty);
      final p = await SharedPreferences.getInstance();
      expect(jsonDecode(p.getString('bookmarks')!), isEmpty);
    });
    test('removing a missing bookmark is harmless', () async {
      final s = await fresh();
      s.addBookmark('v', const Duration(seconds: 3));
      s.removeBookmark('v', const Duration(seconds: 4));
      s.removeBookmark('nope', const Duration(seconds: 4));
      expect(s.bookmarksFor('v'), [const Duration(seconds: 3)]);
    });
    test('returned list is a copy', () async {
      final s = await fresh();
      s.addBookmark('v', const Duration(seconds: 3));
      s.bookmarksFor('v').clear();
      expect(s.bookmarksFor('v'), hasLength(1));
    });
    test('at most 50 per video, dropping the earliest moment', () async {
      final s = await fresh();
      for (var i = 1; i <= 55; i++) {
        s.addBookmark('v', Duration(seconds: i));
      }
      final marks = s.bookmarksFor('v');
      expect(marks.length, 50);
      expect(marks.first, const Duration(seconds: 6));
      expect(marks.last, const Duration(seconds: 55));
    });
    test('at most 300 videos, dropping the oldest key', () async {
      final s = await fresh();
      for (var i = 0; i < 305; i++) {
        s.addBookmark('v$i', Duration(seconds: i));
      }
      final again = await reopen();
      for (var i = 0; i < 5; i++) {
        expect(again.bookmarksFor('v$i'), isEmpty, reason: 'v$i');
      }
      expect(again.bookmarksFor('v5'), [const Duration(seconds: 5)]);
      expect(again.bookmarksFor('v304'), [const Duration(seconds: 304)]);
    });
    test('stored json loads', () async {
      final s = await fresh({
        'bookmarks': jsonEncode({
          'a': [1000, 2000],
          'b': [5.5],
        })
      });
      expect(s.bookmarksFor('a'), [const Duration(seconds: 1), const Duration(seconds: 2)]);
      expect(s.bookmarksFor('b'), [const Duration(milliseconds: 5)]);
    });
    for (final bad in ['not json', '{', '']) {
      test('corrupt bookmarks "$bad" load as empty', () async {
        expect((await fresh({'bookmarks': bad})).bookmarksFor('a'), isEmpty);
      });
    }
    for (var seed = 0; seed < 25; seed++) {
      test('random ops seed $seed match a reference model', () async {
        final r = Random(seed);
        final s = await fresh();
        final ref = <String, List<int>>{};
        for (var i = 0; i < 80; i++) {
          final key = 'k${r.nextInt(4)}';
          final ms = r.nextInt(20) * 1000;
          if (r.nextInt(3) > 0) {
            s.addBookmark(key, Duration(milliseconds: ms));
            final l = ref.putIfAbsent(key, () => [])
              ..add(ms)
              ..sort();
            if (l.length > 50) l.removeAt(0);
          } else {
            s.removeBookmark(key, Duration(milliseconds: ms));
            ref[key]?.remove(ms);
            if (ref[key]?.isEmpty ?? false) ref.remove(key);
          }
        }
        final again = await reopen();
        for (var k = 0; k < 4; k++) {
          final want = [for (final ms in ref['k$k'] ?? <int>[]) Duration(milliseconds: ms)];
          expect(s.bookmarksFor('k$k'), want);
          expect(again.bookmarksFor('k$k'), want);
        }
      });
    }
  });

  group('v2 setters notify listeners', () {
    final setters = <String, void Function(Settings)>{
      'setDoubleTapSeconds': (s) => s.setDoubleTapSeconds(20),
      'setHardwareDecoding': (s) => s.setHardwareDecoding(false),
      'setGridView': (s) => s.setGridView(true),
      'setFolderHidden': (s) => s.setFolderHidden('x', true),
      'setPartyName': (s) => s.setPartyName('N'),
      'setEq': (s) => s.setEq(List.filled(10, 1)),
      'setEq night': (s) => s.setEq(List.filled(10, 0), night: true),
      'addBookmark': (s) => s.addBookmark('v', Duration.zero),
      'removeBookmark': (s) => s.removeBookmark('v', Duration.zero),
      'setSubtitleStyle lift': (s) => s.setSubtitleStyle(lift: 3),
    };
    setters.forEach((name, call) {
      test(name, () async {
        final s = await fresh();
        var n = 0;
        s.addListener(() => n++);
        call(s);
        expect(n, 1);
      });
    });
  });

  group('settings random restart round trip', () {
    for (var seed = 0; seed < 10; seed++) {
      test('seed $seed', () async {
        final r = Random(seed);
        final s = await fresh();
        final dt = [5, 10, 15, 30][r.nextInt(4)];
        final hw = r.nextBool(), grid = r.nextBool(), night = r.nextBool();
        final name = randomWord(r);
        final eq = [for (var b = 0; b < 10; b++) (r.nextInt(25) - 12).toDouble()];
        s
          ..setDoubleTapSeconds(dt)
          ..setHardwareDecoding(hw)
          ..setGridView(grid)
          ..setPartyName(name)
          ..setEq(eq, night: night);
        final a = await reopen();
        expect(a.doubleTapSeconds, dt);
        expect(a.hardwareDecoding, hw);
        expect(a.gridView, grid);
        expect(a.partyName, name.trim());
        expect(a.eqGains, eq);
        expect(a.nightMode, night);
      });
    }
  });
}
