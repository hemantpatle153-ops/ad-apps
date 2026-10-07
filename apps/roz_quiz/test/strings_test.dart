import 'package:flutter_test/flutter_test.dart';
import 'package:roz_quiz/core/bi.dart';
import 'package:roz_quiz/core/models.dart';
import 'package:roz_quiz/core/session.dart';
import 'package:roz_quiz/core/stats.dart';
import 'package:roz_quiz/l10n/strings.dart';

/// Strings that are the same in both languages on purpose.
const _sameInHindi = {T.xp, T.xpGained, T.examSsc, T.examUpsc};

/// The "view in the other language" button is written in the language it
/// switches to.
const _crossLanguage = {T.viewOther};

void main() {
  final devanagari = RegExp(r'[ऀ-ॿ]');

  test('every key has a translation pair', () {
    final missing = [for (final k in T.values) if (!kStrings.containsKey(k)) k.name];
    expect(missing, isEmpty);
  });

  group('each string', () {
    for (final k in T.values) {
      test(k.name, () {
        final pair = kStrings[k];
        expect(pair, isNotNull);
        final (en, hi) = pair!;
        expect(en.trim(), isNotEmpty, reason: 'en');
        expect(hi.trim(), isNotEmpty, reason: 'hi');
        expect(en, en.trim(), reason: 'no stray spaces in en');
        expect(hi, hi.trim(), reason: 'no stray spaces in hi');
        expect(S.placeholders(hi), S.placeholders(en), reason: 'placeholders');
        if (_crossLanguage.contains(k)) {
          expect(devanagari.hasMatch(en), isTrue);
          expect(devanagari.hasMatch(hi), isFalse);
          return;
        }
        expect(devanagari.hasMatch(en), isFalse, reason: 'Hindi text in the English string');
        if (_sameInHindi.contains(k)) {
          expect(hi, en);
        } else {
          expect(devanagari.hasMatch(hi), isTrue, reason: 'Hindi string not in Devanagari: $hi');
        }
      });
    }
  });

  group('S', () {
    test('t picks the language', () {
      expect(S.en.t(T.justNow), 'just now');
      expect(S.hi.t(T.justNow), 'अभी-अभी');
    });
    test('f fills placeholders', () {
      expect(S.en.f(T.minutesAgo, {'n': 5}), '5 min ago');
      expect(S.hi.f(T.minutesAgo, {'n': 5}), '5 मिनट पहले');
    });
    test('f leaves unknown placeholders alone', () {
      expect(S.en.f(T.minutesAgo, {}), '{n} min ago');
    });
    test('placeholders', () {
      expect(S.placeholders('{a} and {b} and {a}'), {'a', 'b'});
      expect(S.placeholders('none'), isEmpty);
    });
    for (final s in [S.en, S.hi]) {
      final l = s.lang.name;
      test('$l: every subject has a name', () {
        for (final id in kSubjects) {
          expect(s.subject(id), isNot(id), reason: id);
        }
        expect(s.subject('unknown'), 'unknown');
      });
      test('$l: every exam has a name', () {
        for (final id in kExams) {
          expect(s.exam(id), isNot(id), reason: id);
        }
        expect(s.exam('zzz'), 'zzz');
      });
      test('$l: difficulties', () {
        final names = {for (final d in [null, ...Difficulty.values]) s.difficulty(d)};
        expect(names.length, 4);
      });
      test('$l: negative marking', () {
        expect(s.negative(NegativeMarking.quarter), '1/4');
        expect(s.negative(NegativeMarking.none), s.t(T.noNegative));
      });
      test('$l: every badge has a distinct name and description', () {
        final names = {for (final a in Achievement.values) s.badge(a).$1};
        final descs = {for (final a in Achievement.values) s.badge(a).$2};
        expect(names.length, Achievement.values.length);
        expect(descs.length, Achievement.values.length);
      });
      test('$l: dates', () {
        for (var m = 1; m <= 12; m++) {
          expect(s.date(2026, m, 7), matches(RegExp(r'^7 \S+ 2026$')));
          expect(s.date(2026, m, 7, withYear: false), isNot(contains('2026')));
        }
      });
    }
    test('English and Hindi month names', () {
      expect(S.en.date(2026, 10, 7), '7 Oct 2026');
      expect(S.hi.date(2026, 10, 7), '7 अक्टू 2026');
    });
    test('ago', () {
      final now = DateTime.utc(2026, 10, 7, 12);
      expect(S.en.ago(now.subtract(const Duration(seconds: 30)), now), 'just now');
      expect(S.en.ago(now.subtract(const Duration(minutes: 5)), now), '5 min ago');
      expect(S.en.ago(now.subtract(const Duration(hours: 3)), now), '3 h ago');
      expect(S.en.ago(now.subtract(const Duration(days: 2)), now), '2 days ago');
      expect(S.hi.ago(now.subtract(const Duration(days: 2)), now), '2 दिन पहले');
    });
    test('ago with a clock in the past says just now', () {
      final now = DateTime.utc(2026, 10, 7, 12);
      expect(S.en.ago(now.add(const Duration(hours: 1)), now), 'just now');
    });
    test('S.lang', () {
      expect(S.en.lang, Lang.en);
      expect(S.hi.lang, Lang.hi);
    });
  });
}
