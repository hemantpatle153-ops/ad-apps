import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner/src/history_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/generators.dart';

const _key = 'scan_history';

Future<List<String>> _persisted() async =>
    (await SharedPreferences.getInstance()).getStringList(_key) ?? const [];

void main() {
  group('ScanEntry json', () {
    final r = Random(21);
    final values = <String>{
      '',
      'https://example.com',
      'quote " and backslash \\',
      'line\nbreak\ttab',
      '🙂 emoji',
      'नमस्ते दुनिया',
      '{"v":"nested"}',
      'x' * 5000,
    };
    while (values.length < 60) {
      values.add(randomWord(r, 1, 30));
    }
    var i = 0;
    for (final v in values) {
      final ms = r.nextInt(1 << 31) * 1000 + r.nextInt(1000);
      final label = v.length > 20 ? '${v.substring(0, 20)}...' : v;
      final idx = i++;
      test('#$idx toJson keys for "${label.replaceAll('\n', r'\n')}"', () {
        final e = ScanEntry(
            value: v, at: DateTime.fromMillisecondsSinceEpoch(ms));
        expect(e.toJson(), {'v': v, 't': ms});
      });
      test('#$idx round-trips through jsonEncode/jsonDecode', () {
        final e = ScanEntry(
            value: v, at: DateTime.fromMillisecondsSinceEpoch(ms));
        final back = ScanEntry.fromJson(
            jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>);
        expect(back.value, v);
        expect(back.at, e.at);
        expect(back.at.millisecondsSinceEpoch, ms);
      });
    }
    test('round-trip drops sub-millisecond precision', () {
      final at = DateTime.fromMicrosecondsSinceEpoch(1700000000123456);
      final back = ScanEntry.fromJson(
          jsonDecode(jsonEncode(ScanEntry(value: 'a', at: at).toJson()))
              as Map<String, dynamic>);
      expect(back.at.microsecondsSinceEpoch, 1700000000123000);
    });
    test('fromJson rejects a missing value', () {
      expect(() => ScanEntry.fromJson({'t': 1}), throwsA(isA<TypeError>()));
    });
    test('fromJson rejects a non-int time', () {
      expect(() => ScanEntry.fromJson({'v': 'a', 't': '1'}),
          throwsA(isA<TypeError>()));
    });
  });

  // HistoryStore is a singleton; this file runs in its own isolate, so the
  // first test below is the store's first load.
  group('HistoryStore', () {
    final store = HistoryStore.instance;

    test('load reads entries saved by a previous run, in order', () async {
      final saved = [
        ScanEntry(value: 'newest', at: DateTime.fromMillisecondsSinceEpoch(3000)),
        ScanEntry(value: 'middle', at: DateTime.fromMillisecondsSinceEpoch(2000)),
        ScanEntry(value: 'oldest', at: DateTime.fromMillisecondsSinceEpoch(1000)),
      ];
      SharedPreferences.setMockInitialValues({
        _key: saved.map((e) => jsonEncode(e.toJson())).toList(),
      });
      var notified = 0;
      void l() => notified++;
      store.addListener(l);
      await store.load();
      store.removeListener(l);
      expect(store.entries.map((e) => e.value), ['newest', 'middle', 'oldest']);
      expect(store.entries.map((e) => e.at.millisecondsSinceEpoch),
          [3000, 2000, 1000]);
      expect(notified, 1);
    });

    test('second load is a no-op', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, const []);
      var notified = 0;
      void l() => notified++;
      store.addListener(l);
      await store.load();
      store.removeListener(l);
      expect(store.entries, hasLength(3));
      expect(notified, 0);
    });

    test('entries is unmodifiable', () {
      expect(() => store.entries.add(ScanEntry(value: 'x', at: DateTime(2020))),
          throwsUnsupportedError);
      expect(() => store.entries.clear(), throwsUnsupportedError);
    });

    test('clear empties memory and storage and notifies', () async {
      var notified = 0;
      void l() => notified++;
      store.addListener(l);
      await store.clear();
      store.removeListener(l);
      expect(store.entries, isEmpty);
      expect(await _persisted(), isEmpty);
      expect(notified, 1);
    });

    test('add puts the value first with a current timestamp', () async {
      await store.clear();
      final before = DateTime.now();
      await store.add('first');
      await store.add('second');
      final after = DateTime.now();
      expect(store.entries.map((e) => e.value), ['second', 'first']);
      for (final e in store.entries) {
        expect(e.at.isBefore(before), isFalse);
        expect(e.at.isAfter(after), isFalse);
      }
    });

    test('add notifies listeners once', () async {
      await store.clear();
      var notified = 0;
      void l() => notified++;
      store.addListener(l);
      await store.add('one');
      store.removeListener(l);
      expect(notified, 1);
    });

    test('re-adding an existing value moves it to the top without duplicates',
        () async {
      await store.clear();
      for (final v in ['a', 'b', 'c']) {
        await store.add(v);
      }
      await store.add('a');
      expect(store.entries.map((e) => e.value), ['a', 'c', 'b']);
    });

    test('values differing only by whitespace or case are kept apart',
        () async {
      await store.clear();
      for (final v in ['abc', 'ABC', ' abc', 'abc ']) {
        await store.add(v);
      }
      expect(store.entries.map((e) => e.value), ['abc ', ' abc', 'ABC', 'abc']);
    });

    test('history is capped at 300, dropping the oldest', () async {
      await store.clear();
      for (var i = 0; i < 305; i++) {
        await store.add('v$i');
      }
      expect(store.entries, hasLength(300));
      expect(store.entries.first.value, 'v304');
      expect(store.entries.last.value, 'v5');
      expect(await _persisted(), hasLength(300));
    });

    test('remove deletes only that entry and persists', () async {
      await store.clear();
      for (final v in ['a', 'b', 'c']) {
        await store.add(v);
      }
      await store.remove(store.entries[1]);
      expect(store.entries.map((e) => e.value), ['c', 'a']);
      final stored = (await _persisted())
          .map((s) => (jsonDecode(s) as Map<String, dynamic>)['v'])
          .toList();
      expect(stored, ['c', 'a']);
    });

    test('remove of an unknown entry changes nothing', () async {
      await store.clear();
      await store.add('a');
      await store.remove(ScanEntry(value: 'a', at: DateTime(2000)));
      expect(store.entries.map((e) => e.value), ['a']);
    });

    // Random add/remove sequences checked against a simple model:
    // newest first, no duplicate values, at most 300 entries.
    for (var seed = 0; seed < 40; seed++) {
      test('random sequence #$seed matches the reference model', () async {
        final r = Random(1000 + seed);
        await store.clear();
        final model = <String>[];
        final pool = List.generate(4 + r.nextInt(20), (i) => 'code$i');
        final ops = 5 + r.nextInt(40);
        for (var k = 0; k < ops; k++) {
          if (model.isNotEmpty && r.nextInt(5) == 0) {
            final idx = r.nextInt(model.length);
            await store.remove(store.entries[idx]);
            model.removeAt(idx);
          } else {
            final v = pool[r.nextInt(pool.length)];
            await store.add(v);
            model
              ..remove(v)
              ..insert(0, v);
          }
        }
        expect(store.entries.map((e) => e.value), model);
        final stored = (await _persisted())
            .map((s) => ScanEntry.fromJson(jsonDecode(s) as Map<String, dynamic>))
            .toList();
        expect(stored.map((e) => e.value), model);
        expect(stored.map((e) => e.at.millisecondsSinceEpoch),
            store.entries.map((e) => e.at.millisecondsSinceEpoch));
      });
    }
  });
}
