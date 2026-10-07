import 'package:flutter_test/flutter_test.dart';
import 'package:roz_quiz/core/report.dart';

import 'support/harness.dart';

final t0 = DateTime.utc(2026, 10, 7, 10);

void main() {
  group('ReportReason wire values (SCHEMA.md reasons)', () {
    test('wrong answer', () => expect(ReportReason.wrongAnswer.wire, 'wrong_answer'));
    test('wrong question', () => expect(ReportReason.wrongQuestion.wire, 'wrong_question'));
    test('translation goes as other', () => expect(ReportReason.translation.wire, 'other'));
    test('other', () => expect(ReportReason.other.wire, 'other'));
    test('only schema reasons are used', () {
      for (final r in ReportReason.values) {
        expect(['wrong_answer', 'wrong_question', 'other'], contains(r.wire));
      }
    });
  });

  group('reportNote', () {
    test('trims', () => expect(reportNote(ReportReason.other, '  hello  '), 'hello'));
    test('keeps inner spaces', () => expect(reportNote(ReportReason.other, 'a  b'), 'a  b'));
    test('translation prefix', () {
      expect(reportNote(ReportReason.translation, 'Hindi option B is wrong'),
          '[translation] Hindi option B is wrong');
    });
    test('translation prefix without note', () {
      expect(reportNote(ReportReason.translation, '  '), '[translation]');
    });
    test('empty note for wrong answer', () => expect(reportNote(ReportReason.wrongAnswer, ''), ''));
    test('cut to 300 characters', () {
      expect(reportNote(ReportReason.other, 'x' * 400).length, kReportNoteMax);
    });
    test('prefix counts towards the limit', () {
      final n = reportNote(ReportReason.translation, 'y' * 300);
      expect(n.runes.length, kReportNoteMax);
      expect(n, startsWith(kTranslationPrefix));
    });
    test('cuts by characters, not UTF-16 units (Hindi is safe)', () {
      final n = reportNote(ReportReason.other, 'क' * 350);
      expect(n.runes.length, kReportNoteMax);
      expect(n, 'क' * kReportNoteMax);
    });
    test('emoji are not split', () {
      final n = reportNote(ReportReason.other, '😀' * 301);
      expect(n.runes.length, kReportNoteMax);
      expect(n.runes.every((r) => r == '😀'.runes.first), isTrue);
    });
  });

  group('validateReport', () {
    test('ok with a reason that needs no note', () {
      expect(validateReport(item: 'q1', reason: ReportReason.wrongAnswer, note: ''), isNull);
      expect(validateReport(item: 'q1', reason: ReportReason.wrongQuestion, note: ''), isNull);
    });
    test('missing item', () {
      expect(validateReport(item: ' ', reason: ReportReason.wrongAnswer, note: ''),
          ReportProblem.missingItem);
    });
    for (final r in [ReportReason.other, ReportReason.translation]) {
      test('${r.name} needs a note of 5+ characters', () {
        expect(validateReport(item: 'q', reason: r, note: ''), ReportProblem.noteRequired);
        expect(validateReport(item: 'q', reason: r, note: '  abcd  '), ReportProblem.noteRequired);
        expect(validateReport(item: 'q', reason: r, note: 'abcde'), isNull);
      });
    }
    test('300 characters is fine, 301 is too long', () {
      expect(validateReport(item: 'q', reason: ReportReason.other, note: 'a' * 300), isNull);
      expect(validateReport(item: 'q', reason: ReportReason.other, note: 'a' * 301),
          ReportProblem.noteTooLong);
    });
    test('Hindi characters count as one each', () {
      expect(validateReport(item: 'q', reason: ReportReason.other, note: 'क' * 300), isNull);
    });
  });

  group('ReportPayload', () {
    test('JSON matches the feedReports schema', () {
      const p = ReportPayload(item: 'q-1', reason: 'other', note: 'n', by: 'uid');
      expect(p.toJson(), {'app': 'roz_quiz', 'item': 'q-1', 'reason': 'other', 'note': 'n', 'by': 'uid'});
    });
  });

  group('ReportRateLimiter', () {
    test('first report is fine', () => expect(ReportRateLimiter().check('a', t0), isNull));
    test('same item again within 30 days', () {
      final l = ReportRateLimiter()..record('a', t0);
      expect(l.check('a', t0.add(const Duration(days: 29))), ReportProblem.alreadyReported);
      expect(l.check('a', t0.add(const Duration(days: 31))), isNull);
    });
    test('20 seconds between reports', () {
      final l = ReportRateLimiter()..record('a', t0);
      expect(l.check('b', t0.add(const Duration(seconds: 19))), ReportProblem.tooSoon);
      expect(l.check('b', t0.add(const Duration(seconds: 20))), isNull);
    });
    test('10 a day', () {
      final l = ReportRateLimiter();
      for (var i = 0; i < 10; i++) {
        final at = t0.add(Duration(minutes: i));
        expect(l.check('q$i', at), isNull, reason: 'report $i');
        l.record('q$i', at);
      }
      expect(l.check('q10', t0.add(const Duration(minutes: 30))), ReportProblem.dailyLimit);
      expect(l.check('q10', t0.add(const Duration(hours: 24, minutes: 10))), isNull);
    });
    test('clock set back does not lock out', () {
      final l = ReportRateLimiter()..record('a', t0);
      expect(l.check('b', t0.subtract(const Duration(hours: 2))), isNull);
    });
    test('custom limits', () {
      final l = ReportRateLimiter(perDay: 1, minGap: Duration.zero)..record('a', t0);
      expect(l.check('b', t0.add(const Duration(minutes: 1))), ReportProblem.dailyLimit);
    });
    test('old history is forgotten', () {
      final l = ReportRateLimiter()..record('a', t0);
      l.record('b', t0.add(const Duration(days: 40)));
      expect(l.history.map((e) => e.$1), ['b']);
    });
    test('history is read-only', () {
      final l = ReportRateLimiter()..record('a', t0);
      expect(() => (l.history as List).clear(), throwsUnsupportedError);
    });
    test('JSON round trip', () {
      final l = ReportRateLimiter()
        ..record('a', t0)
        ..record('b', t0.add(const Duration(minutes: 1)));
      final back = ReportRateLimiter(history: ReportRateLimiter.historyFromJson(l.toJson()));
      expect(back.history, l.history);
      expect(back.check('a', t0.add(const Duration(hours: 1))), ReportProblem.alreadyReported);
    });
    for (final bad in <Object?>[null, 'x', 5, {}]) {
      test('historyFromJson($bad) is empty', () => expect(ReportRateLimiter.historyFromJson(bad), isEmpty));
    }
    test('historyFromJson skips junk rows', () {
      final h = ReportRateLimiter.historyFromJson([
        ['a', 1000],
        ['b'],
        [1, 2],
        ['c', 'x'],
        'row',
      ]);
      expect(h.length, 1);
      expect(h.single.$1, 'a');
      expect(h.single.$2.isUtc, isTrue);
    });
  });

  group('ReportService', () {
    late FakeReportSink sink;
    late DateTime now;
    late ReportService service;
    setUp(() {
      sink = FakeReportSink();
      now = t0;
      service = ReportService(sink, ReportRateLimiter(), clock: () => now);
    });

    test('sends a valid report', () async {
      await service.submit(item: ' q-1 ', reason: ReportReason.wrongAnswer, note: ' B is right ');
      expect(sink.signIns, 1);
      expect(sink.sent.single.toJson(),
          {'app': 'roz_quiz', 'item': 'q-1', 'reason': 'wrong_answer', 'note': 'B is right', 'by': 'uid-test'});
    });
    test('translation report', () async {
      await service.submit(item: 'q', reason: ReportReason.translation, note: 'Hindi typo');
      expect(sink.sent.single.reason, 'other');
      expect(sink.sent.single.note, '[translation] Hindi typo');
    });
    test('invalid report never reaches the sink', () async {
      await expectLater(
          service.submit(item: 'q', reason: ReportReason.other, note: ''),
          throwsA(isA<ReportException>()
              .having((e) => e.problem, 'problem', ReportProblem.noteRequired)
              .having((e) => e.offline, 'offline', isFalse)));
      expect(sink.signIns, 0);
    });
    test('rate limited', () async {
      await service.submit(item: 'q1', reason: ReportReason.wrongAnswer, note: '');
      now = now.add(const Duration(seconds: 5));
      await expectLater(service.submit(item: 'q2', reason: ReportReason.wrongAnswer, note: ''),
          throwsA(isA<ReportException>().having((e) => e.problem, 'problem', ReportProblem.tooSoon)));
      expect(sink.sent.length, 1);
    });
    test('same question twice', () async {
      await service.submit(item: 'q1', reason: ReportReason.wrongAnswer, note: '');
      now = now.add(const Duration(hours: 1));
      expect(service.precheck('q1'), ReportProblem.alreadyReported);
      expect(service.precheck('q2'), isNull);
    });
    test('offline failure is reported and not recorded', () async {
      sink.fail = true;
      await expectLater(service.submit(item: 'q1', reason: ReportReason.wrongAnswer, note: ''),
          throwsA(isA<ReportException>().having((e) => e.offline, 'offline', isTrue)));
      expect(service.limiter.history, isEmpty);
      sink.fail = false;
      await service.submit(item: 'q1', reason: ReportReason.wrongAnswer, note: '');
      expect(sink.sent.length, 1);
    });
    test('ReportException toString', () {
      expect(const ReportException(ReportProblem.tooSoon).toString(), contains('tooSoon'));
    });
  });
}
