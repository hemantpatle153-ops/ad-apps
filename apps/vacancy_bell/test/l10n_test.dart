import 'package:flutter_test/flutter_test.dart';
import 'package:vacancy_bell/core/json_read.dart';
import 'package:vacancy_bell/core/ymd.dart';
import 'package:vacancy_bell/l10n/s.dart';
import 'package:vacancy_bell/l10n/strings.dart';
import 'package:vacancy_bell/logic/calendar.dart';
import 'package:vacancy_bell/logic/report.dart';
import 'package:vacancy_bell/models/profile.dart';
import 'package:vacancy_bell/models/taxonomy.dart';

final _devanagari = RegExp(r'[ऀ-ॿ]');

/// Hindi strings that are allowed to have no Devanagari (abbreviations).
const _latinOk = {L.pwbd};

void main() {
  test('no extra keys in either table', () {
    expect(stringsEn.keys.toSet(), L.values.toSet());
    expect(stringsHi.keys.toSet(), L.values.toSet());
  });

  group('every key in both languages', () {
    for (final key in L.values) {
      test(key.name, () {
        final en = stringsEn[key];
        final hi = stringsHi[key];
        expect(en, isNotNull, reason: 'English missing');
        expect(hi, isNotNull, reason: 'Hindi missing');
        expect(en!.trim(), isNotEmpty);
        expect(hi!.trim(), isNotEmpty);
        expect(placeholdersOf(hi), placeholdersOf(en), reason: 'placeholders differ');
        expect(en.trim(), en, reason: 'stray spaces');
        expect(hi.trim(), hi, reason: 'stray spaces');
        // Hindi text must really be Hindi (abbreviations like "PwBD" aside).
        if (!_latinOk.contains(key) && en.replaceAll(RegExp(r'\{\w+\}'), '').trim().length > 3) {
          expect(_devanagari.hasMatch(hi) || hi.contains('{'), isTrue, reason: 'not translated: $hi');
        }
      });
    }
  });

  group('no "Official" branding or government claims', () {
    for (final lang in AppLang.values) {
      test(lang.name, () {
        final all = stringsFor(lang);
        expect(all[L.appName]!.toLowerCase(), isNot(contains('official')));
        expect(all[L.appName]!.toLowerCase(), isNot(contains('sarkari')));
        expect(all[L.aboutText]!.toLowerCase(), isNot(contains('official app')));
      });
    }
  });

  group('fillTemplate', () {
    test('fills names', () => expect(fillTemplate('{n} days left', {'n': 3}), '3 days left'));
    test('several', () => expect(fillTemplate('{a}-{b}', {'a': 1, 'b': 2}), '1-2'));
    test('missing args stay visible', () => expect(fillTemplate('{n} left', {}), '{n} left'));
    test('placeholdersOf', () => expect(placeholdersOf('{a} and {b} and {a}'), {'a', 'b'}));
  });

  group('S.t in both languages', () {
    test('English', () => expect(S.en.t(L.daysLeft, {'n': 2}), '2 days left'));
    test('Hindi', () => expect(S.hi.t(L.daysLeft, {'n': 2}), '2 दिन बाकी'));
    test('of(lang)', () => expect(S.of(AppLang.hi).lang, AppLang.hi));
    test('text picks the language', () {
      const t = LocalText('Hello', 'नमस्ते');
      expect(S.en.text(t), 'Hello');
      expect(S.hi.text(t), 'नमस्ते');
      expect(S.hi.text(null), '');
    });
  });

  group('Indian number grouping', () {
    const cases = {
      0: '0',
      7: '7',
      999: '999',
      1000: '1,000',
      14582: '14,582',
      100000: '1,00,000',
      123456: '1,23,456',
      1234567: '12,34,567',
      60244: '60,244',
      12345678: '1,23,45,678',
      -4500: '-4,500',
    };
    cases.forEach((n, want) => test('$n', () => expect(S.number(n), want)));
    test('rupees', () => expect(S.en.rupees(1500), '₹1,500'));
  });

  group('dates', () {
    final d = Ymd(2026, 11, 5);
    test('English', () => expect(S.en.date(d), '05 Nov 2026'));
    test('Hindi', () => expect(S.hi.date(d), '05 नव॰ 2026'));
    for (var m = 1; m <= 12; m++) {
      test('month $m has names in both languages', () {
        expect(S.en.monthYear(2026, m), endsWith('2026'));
        expect(S.hi.monthYear(2026, m), endsWith('2026'));
        expect(_devanagari.hasMatch(S.hi.date(Ymd(2026, m, 1))), isTrue);
      });
    }
    test('weekday', () {
      expect(S.en.weekday(Ymd(2026, 10, 7)), 'Wed');
      expect(S.hi.weekday(Ymd(2026, 10, 7)), 'बुध');
    });
    test('time', () => expect(S.en.time(9, 5), '09:05'));
    test('instant shown in India time', () {
      expect(S.en.instantIst(DateTime.utc(2026, 10, 7, 9, 12)), '07 Oct 2026, 14:42');
      expect(S.en.instantIst(DateTime.utc(2026, 10, 6, 19, 0)), '07 Oct 2026, 00:30');
    });
  });

  group('ago', () {
    final now = DateTime.utc(2026, 10, 7, 12);
    final cases = <(Duration, String, String)>[
      (const Duration(seconds: 20), 'just now', 'अभी'),
      (const Duration(minutes: 5), '5 min ago', '5 मिनट पहले'),
      (const Duration(minutes: 59), '59 min ago', '59 मिनट पहले'),
      (const Duration(hours: 2), '2 h ago', '2 घंटे पहले'),
      (const Duration(hours: 23), '23 h ago', '23 घंटे पहले'),
      (const Duration(days: 3), '3 days ago', '3 दिन पहले'),
    ];
    for (final (d, en, hi) in cases) {
      test('$d', () {
        expect(S.en.ago(now.subtract(d), now), en);
        expect(S.hi.ago(now.subtract(d), now), hi);
      });
    }
  });

  group('enum labels exist and differ between languages where expected', () {
    for (final lang in AppLang.values) {
      final s = S.of(lang);
      test('${lang.name}: post types', () {
        final labels = PostType.values.map(s.postType).toSet();
        expect(labels.length, PostType.values.length);
      });
      test('${lang.name}: categories', () {
        expect(JobCategory.values.map(s.category).toSet().length, JobCategory.values.length);
      });
      test('${lang.name}: qualifications', () {
        expect(Qualification.values.map(s.qualification).toSet().length, Qualification.values.length);
      });
      test('${lang.name}: social categories', () {
        expect(SocialCategory.values.map(s.socialCategory).toSet().length, SocialCategory.values.length);
      });
      test('${lang.name}: genders', () {
        expect(Gender.values.map(s.gender).toSet().length, Gender.values.length);
      });
      test('${lang.name}: report reasons', () {
        expect(ReportReason.values.map(s.reportReason).toSet().length, ReportReason.values.length);
      });
      test('${lang.name}: calendar kinds', () {
        for (final k in CalendarKind.values) {
          expect(s.calendarKind(k), isNotEmpty);
        }
      });
      test('${lang.name}: states', () {
        expect(s.state('UP'), lang == AppLang.hi ? 'उत्तर प्रदेश' : 'Uttar Pradesh');
        expect(s.state(allStates), s.t(L.allStates));
        expect(s.state('ZZ'), 'ZZ');
      });
    }
  });

  group('ageRange', () {
    test('both', () => expect(S.en.ageRange(18, 32), '18 to 32 years'));
    test('Hindi both', () => expect(S.hi.ageRange(18, 32), '18 से 32 वर्ष'));
    test('min only', () => expect(S.en.ageRange(18, null), 'At least 18 years'));
    test('max only', () => expect(S.en.ageRange(null, 30), 'Up to 30 years'));
    test('neither', () => expect(S.en.ageRange(null, null), isNull));
  });

  test('language names', () {
    expect(S.en.languageName(AppLang.hi), 'हिंदी');
    expect(S.hi.languageName(AppLang.en), 'English');
  });
}
