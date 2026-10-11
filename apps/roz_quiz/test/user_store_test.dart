import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:roz_quiz/core/bi.dart';
import 'package:roz_quiz/core/day.dart';
import 'package:roz_quiz/core/report.dart';
import 'package:roz_quiz/core/session.dart';
import 'package:roz_quiz/core/stats.dart';
import 'package:roz_quiz/data/user_store.dart';

import 'support/harness.dart';

void main() {
  group('Settings', () {
    test('defaults: English, 8 AM reminder, streak nudge on, 1/4 negative', () {
      final s = Settings();
      expect(s.lang, Lang.en);
      expect(s.theme, AppTheme.system);
      expect(s.timerSeconds, 0);
      expect(s.dailyReminder, isTrue);
      expect(s.reminderMinutes, 480);
      expect(s.streakReminder, isTrue);
      expect(s.onboarded, isFalse);
      expect(s.targetExams, isEmpty);
      expect(s.mockNegative, NegativeMarking.quarter);
      expect(s.sound, isTrue);
      expect(s.haptics, isTrue);
    });
    test('round trip', () {
      final s = Settings()
        ..lang = Lang.hi
        ..theme = AppTheme.dark
        ..timerSeconds = 45
        ..sound = false
        ..haptics = false
        ..dailyReminder = false
        ..reminderMinutes = 1290
        ..streakReminder = false
        ..onboarded = true
        ..targetExams = ['upsc', 'ssc']
        ..mockNegative = NegativeMarking.third;
      final b = Settings.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(jsonEncode(b.toJson()), jsonEncode(Settings.fromJson(s.toJson()).toJson()));
      expect(b.lang, Lang.hi);
      expect(b.theme, AppTheme.dark);
      expect(b.timerSeconds, 45);
      expect(b.sound, isFalse);
      expect(b.haptics, isFalse);
      expect(b.dailyReminder, isFalse);
      expect(b.reminderMinutes, 1290);
      expect(b.streakReminder, isFalse);
      expect(b.onboarded, isTrue);
      expect(b.targetExams, ['ssc', 'upsc'], reason: 'kept in kExams order');
      expect(b.mockNegative, NegativeMarking.third);
    });
    for (final bad in <Object?>[null, 'x', 1, []]) {
      test('fromJson($bad) gives defaults', () {
        expect(jsonEncode(Settings.fromJson(bad).toJson()), jsonEncode(Settings().toJson()));
      });
    }
    for (final t in [-1, 5, 31, 120, '30']) {
      test('unknown timer $t becomes off', () => expect(Settings.fromJson({'timer': t}).timerSeconds, 0));
    }
    for (final t in kTimerChoices) {
      test('timer $t kept', () => expect(Settings.fromJson({'timer': t}).timerSeconds, t));
    }
    for (final m in [-1, 1440, 99999, 'x', 8.5]) {
      test('bad reminder minutes $m fall back to 8 AM', () {
        expect(Settings.fromJson({'reminderMinutes': m}).reminderMinutes, 480);
      });
    }
    test('unknown exams are dropped', () {
      expect(Settings.fromJson({'exams': ['ssc', 'nasa', 3]}).targetExams, ['ssc']);
    });
    test('unknown theme and language', () {
      final s = Settings.fromJson({'theme': 'neon', 'lang': 'fr'});
      expect(s.theme, AppTheme.system);
      expect(s.lang, Lang.en);
    });
    test('non-bool flags fall back to defaults', () {
      final s = Settings.fromJson({'sound': 'no', 'dailyReminder': 0, 'onboarded': 'true'});
      expect(s.sound, isTrue);
      expect(s.dailyReminder, isTrue);
      expect(s.onboarded, isFalse);
    });
  });

  group('DailyRecord', () {
    test('round trip', () {
      const r = DailyRecord(7, 10, 65000, [0, 1, null, 3, 2, 1, 0, 0, null, 1]);
      final b = DailyRecord.fromJson(jsonDecode(jsonEncode(r.toJson())))!;
      expect(b.correct, 7);
      expect(b.total, 10);
      expect(b.timeMs, 65000);
      expect(b.choices, r.choices);
      expect(b.fraction, 0.7);
    });
    final bad = <Object?>[
      null,
      'x',
      [1, 2],
      [11, 10, 0],
      [-1, 10, 0],
      [1, 0, 0],
      ['1', 10, 0],
      [1, 10, 'x'],
    ];
    for (final b in bad) {
      test('rejects $b', () => expect(DailyRecord.fromJson(b), isNull));
    }
    test('old records without choices', () {
      expect(DailyRecord.fromJson([3, 10, 100])!.choices, isEmpty);
    });
    test('bad choices become null, negative time becomes 0', () {
      final r = DailyRecord.fromJson([3, 10, -5, [0, 7, 'x', -1, 3]])!;
      expect(r.choices, [0, null, null, null, 3]);
      expect(r.timeMs, 0);
    });
  });

  group('SavedQuestion', () {
    test('round trip', () {
      final q = makeQ(id: 'saved-1', answer: 2);
      final s = SavedQuestion(q, kNow, count: 3);
      final b = SavedQuestion.fromJson(jsonDecode(jsonEncode(s.toJson())))!;
      expect(b.question.id, 'saved-1');
      expect(b.question.answer, 2);
      expect(b.savedAt, kNow);
      expect(b.count, 3);
    });
    test('bad count becomes 1', () {
      final j = SavedQuestion(makeQ(), kNow).toJson()..['n'] = -4;
      expect(SavedQuestion.fromJson(j)!.count, 1);
    });
    test('broken question or time is dropped', () {
      expect(SavedQuestion.fromJson({'q': {}, 'at': 1}), isNull);
      expect(SavedQuestion.fromJson({'q': questionJson(), 'at': 'x'}), isNull);
      expect(SavedQuestion.fromJson('x'), isNull);
    });
  });

  group('UserStore', () {
    test('empty store has defaults', () {
      final s = UserStore(MemoryKeyValueStore());
      expect(s.days, isEmpty);
      expect(s.xp, 0);
      expect(s.badges, isEmpty);
      expect(s.bookmarks, isEmpty);
      expect(s.seen, isEmpty);
      expect(s.reportHistory, isEmpty);
      expect(s.stats.quizzes, 0);
    });
    test('everything survives a restart', () async {
      final kv = MemoryKeyValueStore();
      final s = UserStore(kv);
      s.settings.lang = Lang.hi;
      await s.saveSettings();
      s.days['2026-10-07'] = const DailyRecord(8, 10, 1000, [0]);
      await s.saveDays();
      s.stats.quizzes = 4;
      await s.saveStats();
      s.xp = 321;
      await s.saveXp();
      s.badges.addAll({Achievement.firstQuiz, Achievement.streak3});
      await s.saveBadges();
      s.bookmarks['b1'] = SavedQuestion(makeQ(id: 'b1'), kNow);
      await s.saveBookmarks();
      s.mistakes['m1'] = SavedQuestion(makeQ(id: 'm1'), kNow, count: 2);
      await s.saveMistakes();
      s.seen.addAll(['a', 'b']);
      await s.saveSeen();
      await s.saveReports(ReportRateLimiter()..record('q', kNow));

      final b = UserStore(kv);
      expect(b.settings.lang, Lang.hi);
      expect(b.days['2026-10-07']!.correct, 8);
      expect(b.stats.quizzes, 4);
      expect(b.xp, 321);
      expect(b.badges, {Achievement.firstQuiz, Achievement.streak3});
      expect(b.bookmarks.keys, ['b1']);
      expect(b.mistakes['m1']!.count, 2);
      expect(b.seen, {'a', 'b'});
      expect(b.reportHistory.single.$1, 'q');
      expect(b.playedDays, {Day(2026, 10, 7)});
    });
    test('damaged values fall back without failing', () {
      final kv = MemoryKeyValueStore({
        'settings.v1': '{oops',
        'days.v1': '{"2026-10-07":[1,10,0],"bad":[1,10,0],"2026-10-08":"x"}',
        'stats.v1': '[]',
        'xp.v1': '-5',
        'badges.v1': '["firstQuiz","unknown",3]',
        'bookmarks.v1': '[{"q":{},"at":1}, "x"]',
        'mistakes.v1': 'null',
        'seen.v1': '["a",1,null]',
        'reports.v1': '"x"',
      });
      final s = UserStore(kv);
      expect(s.settings.lang, Lang.en);
      expect(s.days.keys, ['2026-10-07']);
      expect(s.xp, 0);
      expect(s.badges, {Achievement.firstQuiz});
      expect(s.bookmarks, isEmpty);
      expect(s.mistakes, isEmpty);
      expect(s.seen, {'a'});
      expect(s.reportHistory, isEmpty);
    });
    test('bookmark and mistake lists are newest first', () {
      final s = UserStore(MemoryKeyValueStore());
      s.bookmarks['old'] = SavedQuestion(makeQ(id: 'old'), kNow);
      s.bookmarks['new'] = SavedQuestion(makeQ(id: 'new'), kNow.add(const Duration(hours: 1)));
      expect(s.bookmarkList.map((e) => e.question.id), ['new', 'old']);
      s.mistakes['x'] = SavedQuestion(makeQ(id: 'x'), kNow);
      expect(s.mistakeList.single.question.id, 'x');
    });
    test('saved lists are capped, oldest dropped', () async {
      final s = UserStore(MemoryKeyValueStore());
      for (var i = 0; i < UserStore.maxSaved + 5; i++) {
        s.bookmarks['b$i'] = SavedQuestion(makeQ(id: 'b$i'), kNow.add(Duration(minutes: i)));
      }
      await s.saveBookmarks();
      expect(s.bookmarks.length, UserStore.maxSaved);
      expect(s.bookmarks.containsKey('b0'), isFalse);
      expect(s.bookmarks.containsKey('b${UserStore.maxSaved + 4}'), isTrue);
    });
    test('seen is capped, keeping the newest', () async {
      final s = UserStore(MemoryKeyValueStore());
      for (var i = 0; i < UserStore.maxSeen + 10; i++) {
        s.seen.add('s$i');
      }
      await s.saveSeen();
      expect(s.seen.length, UserStore.maxSeen);
      expect(s.seen.contains('s0'), isFalse);
      expect(s.seen.contains('s${UserStore.maxSeen + 9}'), isTrue);
    });
    test('MemoryKeyValueStore remove', () async {
      final kv = MemoryKeyValueStore({'a': '1'});
      await kv.remove('a');
      expect(kv.getString('a'), isNull);
    });
  });
}
