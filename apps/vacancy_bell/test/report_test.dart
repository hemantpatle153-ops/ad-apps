import 'package:flutter_test/flutter_test.dart';
import 'package:vacancy_bell/data/kv_store.dart';
import 'package:vacancy_bell/logic/report.dart';

import 'support/fakes.dart';

void main() {
  group('ReportReason wire names (SCHEMA.md)', () {
    const wire = {
      ReportReason.wrongDate: 'wrong_date',
      ReportReason.wrongFee: 'wrong_fee',
      ReportReason.wrongEligibility: 'wrong_eligibility',
      ReportReason.brokenLink: 'broken_link',
      ReportReason.other: 'other',
    };
    wire.forEach((r, w) {
      test(w, () {
        expect(r.wire, w);
        expect(ReportReason.tryParse(w), r);
      });
    });
    test('unknown', () => expect(ReportReason.tryParse('wrong_answer'), isNull));
  });

  group('ReportDraft validation', () {
    final cases = <(String, ReportDraft, ReportProblem?)>[
      ('valid with note', const ReportDraft(item: 'ssc-cgl-2026-notice', reason: ReportReason.wrongDate, note: 'Last date is 6 Nov'), null),
      ('valid without note', const ReportDraft(item: 'ssc-cgl-2026-notice', reason: ReportReason.wrongFee), null),
      ('other needs a note', const ReportDraft(item: 'ssc-cgl-2026-notice', reason: ReportReason.other), ReportProblem.noteNeeded),
      ('other with spaces only', const ReportDraft(item: 'ssc-cgl-2026-notice', reason: ReportReason.other, note: '   '), ReportProblem.noteNeeded),
      ('other with note', const ReportDraft(item: 'ssc-cgl-2026-notice', reason: ReportReason.other, note: 'Wrong org'), null),
      ('300 characters', ReportDraft(item: 'a', reason: ReportReason.brokenLink, note: 'x' * 300), null),
      ('301 characters', ReportDraft(item: 'a', reason: ReportReason.brokenLink, note: 'x' * 301), ReportProblem.noteTooLong),
      ('300 after trimming', ReportDraft(item: 'a', reason: ReportReason.brokenLink, note: '  ${'x' * 300}  '), null),
      ('Hindi note', const ReportDraft(item: 'a', reason: ReportReason.wrongEligibility, note: 'आयु सीमा गलत है'), null),
      ('bad id', const ReportDraft(item: '../x', reason: ReportReason.wrongDate), ReportProblem.badItem),
      ('empty id', const ReportDraft(item: '', reason: ReportReason.wrongDate), ReportProblem.badItem),
    ];
    for (final (name, draft, problem) in cases) {
      test(name, () => expect(draft.problem, problem));
    }
    test('control characters are removed', () {
      const d = ReportDraft(item: 'a', reason: ReportReason.other, note: ' bad\u0000 date\u0007 ');
      expect(d.cleanNote, 'bad date');
    });
  });

  group('toEntry matches the feedReports schema', () {
    const d = ReportDraft(item: 'ssc-cgl-2026-notice', reason: ReportReason.brokenLink, note: ' Apply link 404 ');
    final e = d.toEntry(uid: 'uid-123', at: 'TS');
    test('keys', () => expect(e.keys.toSet(), {'app', 'item', 'reason', 'note', 'by', 'at'}));
    test('app', () => expect(e['app'], 'vacancy_bell'));
    test('item', () => expect(e['item'], 'ssc-cgl-2026-notice'));
    test('reason', () => expect(e['reason'], 'broken_link'));
    test('note trimmed', () => expect(e['note'], 'Apply link 404'));
    test('by', () => expect(e['by'], 'uid-123'));
    test('at is the server placeholder', () => expect(e['at'], 'TS'));
  });

  group('ReportLimiter', () {
    late MemoryStore store;
    late DateTime now;
    late ReportLimiter limiter;
    setUp(() {
      store = MemoryStore();
      now = DateTime.utc(2026, 10, 7, 12);
      limiter = ReportLimiter(store, clock: () => now);
    });
    ReportDraft draft(int i, [ReportReason r = ReportReason.wrongDate]) => ReportDraft(item: 'post-$i', reason: r);

    test('starts empty', () {
      expect(limiter.sentToday, 0);
      expect(limiter.limitReached, isFalse);
    });
    test('counts reports', () async {
      await limiter.record(draft(1));
      await limiter.record(draft(2));
      expect(limiter.sentToday, 2);
    });
    test('limit after 10', () async {
      for (var i = 0; i < maxReportsPerDay; i++) {
        await limiter.record(draft(i));
      }
      expect(limiter.limitReached, isTrue);
    });
    test('9 is still allowed', () async {
      for (var i = 0; i < maxReportsPerDay - 1; i++) {
        await limiter.record(draft(i));
      }
      expect(limiter.limitReached, isFalse);
    });
    test('old reports expire after 24 hours', () async {
      for (var i = 0; i < maxReportsPerDay; i++) {
        await limiter.record(draft(i));
      }
      now = now.add(const Duration(hours: 24, minutes: 1));
      expect(limiter.limitReached, isFalse);
      expect(limiter.sentToday, 0);
    });
    test('23 hours later still limited', () async {
      for (var i = 0; i < maxReportsPerDay; i++) {
        await limiter.record(draft(i));
      }
      now = now.add(const Duration(hours: 23));
      expect(limiter.limitReached, isTrue);
    });
    test('duplicate = same post and reason', () async {
      await limiter.record(draft(1));
      expect(limiter.alreadySent(draft(1)), isTrue);
      expect(limiter.alreadySent(draft(1, ReportReason.wrongFee)), isFalse);
      expect(limiter.alreadySent(draft(2)), isFalse);
    });
    test('corrupt storage is ignored', () {
      store.values['reportLog'] = '{broken';
      expect(limiter.sentToday, 0);
      store.values['reportLog'] = '[{"t": "x"}, 5, {"t": 1, "k": 2}]';
      expect(limiter.sentToday, 0);
    });
    test('storage keeps only the last day', () async {
      await limiter.record(draft(1));
      now = now.add(const Duration(days: 2));
      await limiter.record(draft(2));
      expect(store.values['reportLog'], isNot(contains('post-1')));
    });
  });

  group('ReportService', () {
    late FakeReportBackend backend;
    late ReportService service;
    late DateTime now;
    setUp(() {
      backend = FakeReportBackend();
      now = DateTime.utc(2026, 10, 7, 12);
      service = ReportService(backend, ReportLimiter(MemoryStore(), clock: () => now));
    });

    test('sends a valid report', () async {
      final r = await service.submit(const ReportDraft(item: 'a', reason: ReportReason.wrongDate));
      expect(r, ReportOutcome.sent);
      expect(backend.sent.single.item, 'a');
    });
    test('invalid is not sent', () async {
      final r = await service.submit(const ReportDraft(item: 'a', reason: ReportReason.other));
      expect(r, ReportOutcome.invalid);
      expect(backend.sent, isEmpty);
    });
    test('duplicate is not sent twice', () async {
      const d = ReportDraft(item: 'a', reason: ReportReason.wrongDate);
      await service.submit(d);
      expect(await service.submit(d), ReportOutcome.duplicate);
      expect(backend.sent.length, 1);
    });
    test('11th report of the day is refused', () async {
      for (var i = 0; i < maxReportsPerDay; i++) {
        expect(await service.submit(ReportDraft(item: 'p-$i', reason: ReportReason.wrongFee)), ReportOutcome.sent);
      }
      expect(await service.submit(const ReportDraft(item: 'p-x', reason: ReportReason.wrongFee)),
          ReportOutcome.rateLimited);
      expect(backend.sent.length, maxReportsPerDay);
    });
    test('failure is reported and not counted', () async {
      backend.fail = true;
      const d = ReportDraft(item: 'a', reason: ReportReason.wrongDate);
      expect(await service.submit(d), ReportOutcome.failed);
      backend.fail = false;
      expect(await service.submit(d), ReportOutcome.sent);
    });
  });
}
