import 'package:flutter_test/flutter_test.dart';
import 'package:vacancy_bell/core/json_read.dart';
import 'package:vacancy_bell/core/ymd.dart';
import 'package:vacancy_bell/logic/calendar.dart';

import 'support/fakes.dart';

void main() {
  final today = Ymd(2026, 10, 7);
  final posts = fixtureIndex.posts;

  group('buildCalendar from summaries', () {
    final events = buildCalendar(posts, const {}, today: today);
    test('only last dates from today on', () {
      expect(events.every((e) => !e.date.isBefore(today)), isTrue);
      expect(events.every((e) => e.kind == CalendarKind.lastDate), isTrue);
    });
    test('closed post left out', () => expect(events.any((e) => e.post.id == 'bihar-stet-2026'), isFalse));
    test('last day today included', () => expect(events.first.post.id, 'ibps-po-xv-2026'));
    test('sorted by date', () {
      for (var i = 1; i < events.length; i++) {
        expect(events[i - 1].date.compareTo(events[i].date) <= 0, isTrue);
      }
    });
    test('one event per post with a future last date', () {
      final expected = posts.where((p) => p.lastDate != null && !p.lastDate!.isBefore(today)).length;
      expect(events.length, expected);
    });
  });

  group('with details', () {
    final details = {
      'ssc-cgl-2026-notice': fixturePost('ssc-cgl-2026-notice'),
      'up-police-constable-2026': fixturePost('up-police-constable-2026'),
    };
    final events = buildCalendar(posts, details, today: today);
    test('adds exam dates', () {
      final cgl = events.where((e) => e.post.id == 'ssc-cgl-2026-notice').toList();
      expect(cgl.any((e) => e.kind == CalendarKind.exam && e.date == Ymd(2027, 1, 12)), isTrue);
    });
    test('skips application start dates', () {
      expect(events.any((e) => e.label?.en == 'Application start'), isFalse);
    });
    test('does not repeat the last date', () {
      final cgl = events.where((e) => e.post.id == 'ssc-cgl-2026-notice' && e.date == Ymd(2026, 11, 5));
      expect(cgl.length, 1);
    });
    test('keeps other important dates', () {
      expect(events.any((e) => e.post.id == 'ssc-cgl-2026-notice' && e.date == Ymd(2026, 11, 6)), isTrue);
    });
    test('UP police written exam', () {
      expect(events.any((e) => e.post.id == 'up-police-constable-2026' && e.kind == CalendarKind.exam), isTrue);
    });
    test('respects maxEvents', () {
      expect(buildCalendar(posts, details, today: today, maxEvents: 3).length, 3);
    });
  });

  group('groupByMonth', () {
    final months = groupByMonth(buildCalendar(posts, const {}, today: today));
    test('months in order', () {
      expect(months.map((m) => '${m.year}-${m.month}'), ['2026-10', '2026-11']);
    });
    test('events stay in their month', () {
      for (final m in months) {
        expect(m.events.every((e) => e.date.year == m.year && e.date.month == m.month), isTrue);
      }
    });
    test('empty', () => expect(groupByMonth(const []), isEmpty));
  });

  group('kindOfLabel', () {
    final cases = {
      'Last date to apply': CalendarKind.lastDate,
      'Closing date': CalendarKind.lastDate,
      'Admit card': CalendarKind.admitCard,
      'Result date': CalendarKind.result,
      'Tier 1 exam': CalendarKind.exam,
      'CBT date': CalendarKind.exam,
      'Skill test': CalendarKind.exam,
      'Fee payment': CalendarKind.other,
    };
    cases.forEach((label, kind) {
      test(label, () => expect(kindOfLabel(LocalText.same(label)), kind));
    });
  });
}
