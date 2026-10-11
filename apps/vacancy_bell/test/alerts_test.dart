import 'package:flutter_test/flutter_test.dart';
import 'package:vacancy_bell/core/json_read.dart';
import 'package:vacancy_bell/core/ymd.dart';
import 'package:vacancy_bell/logic/alerts.dart';
import 'package:vacancy_bell/models/feed_index.dart';
import 'package:vacancy_bell/models/post.dart';
import 'package:vacancy_bell/models/profile.dart';
import 'package:vacancy_bell/models/taxonomy.dart';

import 'support/fakes.dart';

PostSummary post(String id,
        {String type = 'job',
        String category = 'ssc',
        String postedAt = '2026-10-07T05:00:00Z',
        String? lastDate = '2026-11-05',
        List<String> quals = const ['graduate'],
        List<String> states = const ['all'],
        int? ageMin = 18,
        int? ageMax = 32}) =>
    PostSummary.tryParse({
      'id': id,
      'type': type,
      'title': {'en': 'Post $id', 'hi': 'पोस्ट $id'},
      'org': {'en': 'Org', 'hi': 'संस्था'},
      'category': category,
      'postedAt': postedAt,
      'lastDate': lastDate,
      'qualifications': quals,
      'states': states,
      'ageMin': ageMin,
      'ageMax': ageMax,
    })!;

FeedIndex indexOf(List<PostSummary> posts) =>
    FeedIndex(schema: 1, generatedAt: fixtureNow, posts: posts);

void main() {
  final now = fixtureNow;
  const anyone = UserProfile.empty;

  group('alertMatches', () {
    final cases = <(String, PostSummary, AlertPrefs, UserProfile, bool)>[
      ('new job, default prefs', post('a'), AlertPrefs.defaults, anyone, true),
      ('admit card not in default types', post('a', type: 'admit_card'), AlertPrefs.defaults, anyone, false),
      ('admit card when asked', post('a', type: 'admit_card'),
          const AlertPrefs(types: {PostType.admitCard}), anyone, true),
      ('result when asked', post('a', type: 'result'),
          const AlertPrefs(types: {PostType.job, PostType.result}), anyone, true),
      ('category chosen', post('a', category: 'railway'),
          const AlertPrefs(categories: {JobCategory.railway}), anyone, true),
      ('category not chosen', post('a', category: 'banking'),
          const AlertPrefs(categories: {JobCategory.railway}), anyone, false),
      ('empty categories = all', post('a', category: 'banking'), const AlertPrefs(), anyone, true),
      ('older than 3 days', post('a', postedAt: '2026-10-03T05:00:00Z'), AlertPrefs.defaults, anyone, false),
      ('exactly 3 days', post('a', postedAt: '2026-10-04T12:00:00Z'), AlertPrefs.defaults, anyone, true),
      ('no posting time', PostSummary.tryParse({'id': 'x', 'title': 'X', 'type': 'job'})!,
          AlertPrefs.defaults, anyone, false),
      ('already closed', post('a', lastDate: '2026-10-06'), AlertPrefs.defaults, anyone, false),
      ('no last date is fine', post('a', lastDate: null), AlertPrefs.defaults, anyone, true),
      ('other state skipped', post('a', states: ['BR']), AlertPrefs.defaults, const UserProfile(state: 'UP'), false),
      ('own state kept', post('a', states: ['UP']), AlertPrefs.defaults, const UserProfile(state: 'UP'), true),
      ('other state kept when not matching profile', post('a', states: ['BR']),
          const AlertPrefs(matchProfile: false), const UserProfile(state: 'UP'), true),
      ('qualification mismatch skipped', post('a', quals: ['graduate']), AlertPrefs.defaults,
          const UserProfile(qualification: Qualification.class10), false),
      ('qualification mismatch kept when not matching profile', post('a', quals: ['graduate']),
          const AlertPrefs(matchProfile: false), const UserProfile(qualification: Qualification.class10), true),
      ('clearly too old skipped', post('a', ageMax: 25), AlertPrefs.defaults,
          UserProfile(dob: Ymd(1980, 1, 1), qualification: Qualification.graduate, category: SocialCategory.general),
          false),
      ('possibly eligible kept', post('a'), AlertPrefs.defaults,
          UserProfile(dob: Ymd(2000, 1, 1), qualification: Qualification.graduate), true),
      ('result is not checked against age', post('a', type: 'result', ageMax: 25),
          const AlertPrefs(types: {PostType.result}),
          UserProfile(dob: Ymd(1980, 1, 1), qualification: Qualification.class10, category: SocialCategory.general),
          true),
    ];
    for (final (name, p, prefs, profile, want) in cases) {
      test(name, () => expect(alertMatches(p, prefs, profile, now: now), want));
    }
  });

  group('findNewAlerts', () {
    final idx = indexOf([post('c'), post('b'), post('a')]);

    test('first check seeds silently', () {
      final r = findNewAlerts(idx, null, AlertPrefs.defaults, anyone, now: now);
      expect(r.seeded, isTrue);
      expect(r.matches, isEmpty);
      expect(r.seen, ['c', 'b', 'a']);
    });
    test('announces only unseen posts', () {
      final r = findNewAlerts(idx, ['b', 'a'], AlertPrefs.defaults, anyone, now: now);
      expect(r.seeded, isFalse);
      expect(r.matches.map((p) => p.id), ['c']);
    });
    test('nothing new', () {
      final r = findNewAlerts(idx, ['c', 'b', 'a'], AlertPrefs.defaults, anyone, now: now);
      expect(r.matches, isEmpty);
    });
    test('disabled alerts still update seen ids', () {
      final r = findNewAlerts(idx, ['a'], const AlertPrefs(enabled: false), anyone, now: now);
      expect(r.matches, isEmpty);
      expect(r.seen.toSet(), {'a', 'b', 'c'});
    });
    test('non-matching new posts are marked seen too', () {
      final r = findNewAlerts(indexOf([post('x', category: 'banking')]), [],
          const AlertPrefs(categories: {JobCategory.ssc}), anyone, now: now);
      expect(r.matches, isEmpty);
      expect(r.seen, ['x']);
    });
    test('posts that left the feed are remembered', () {
      final r = findNewAlerts(indexOf([post('new')]), ['gone-1', 'gone-2'], AlertPrefs.defaults, anyone, now: now);
      expect(r.seen, ['new', 'gone-1', 'gone-2']);
    });
    test('a post that comes back is not announced again', () {
      final r = findNewAlerts(indexOf([post('back')]), ['back'], AlertPrefs.defaults, anyone, now: now);
      expect(r.matches, isEmpty);
    });
    test('seen list is capped', () {
      final old = [for (var i = 0; i < maxSeenIds + 50; i++) 'old-$i'];
      final r = findNewAlerts(indexOf([post('n')]), old, AlertPrefs.defaults, anyone, now: now);
      expect(r.seen.length, maxSeenIds);
      expect(r.seen.first, 'n');
    });
    test('keeps feed order (newest first)', () {
      final r = findNewAlerts(idx, [], AlertPrefs.defaults, anyone, now: now);
      expect(r.matches.map((p) => p.id), ['c', 'b', 'a']);
    });
    test('fixture: SSC student sees the new SSC CGL post only', () {
      final seen = [for (final p in fixtureIndex.posts) if (p.id != 'ssc-cgl-2026-notice' && p.id != 'rpsc-ras-2026') p.id];
      final r = findNewAlerts(fixtureIndex, seen, const AlertPrefs(categories: {JobCategory.ssc}),
          UserProfile(dob: Ymd(2000, 1, 1), qualification: Qualification.graduate), now: now);
      expect(r.matches.map((p) => p.id), ['ssc-cgl-2026-notice']);
    });
  });

  group('AlertPrefs storage', () {
    test('round trip', () {
      const p = AlertPrefs(
          enabled: false, categories: {JobCategory.ssc, JobCategory.police}, types: {PostType.result}, matchProfile: false);
      final again = AlertPrefs.fromJson(p.toJson());
      expect(again.enabled, isFalse);
      expect(again.categories, p.categories);
      expect(again.types, p.types);
      expect(again.matchProfile, isFalse);
    });
    test('garbage gives defaults', () {
      final p = AlertPrefs.fromJson('nope');
      expect(p.enabled, isTrue);
      expect(p.types, {PostType.job});
      expect(p.categories, isEmpty);
    });
    test('unknown values are dropped', () {
      final p = AlertPrefs.fromJson({'categories': ['ssc', 'astronaut'], 'types': ['job', 'webinar']});
      expect(p.categories, {JobCategory.ssc});
      expect(p.types, {PostType.job});
    });
    test('an empty type list stays empty', () {
      expect(AlertPrefs.fromJson({'types': []}).types, isEmpty);
    });
  });

  group('stableHash and notification ids', () {
    test('FNV-1a known values', () {
      expect(stableHash(''), 0x811c9dc5);
      expect(stableHash('a'), 0xe40c292c);
    });
    test('same id, same hash', () => expect(stableHash('ssc-cgl-2026-notice'), stableHash('ssc-cgl-2026-notice')));
    test('different ids, different hashes', () => expect(stableHash('a'), isNot(stableHash('b'))));
    for (final p in fixtureIndex.posts) {
      test('ids for ${p.id} fit in 32 bits and their ranges', () {
        final a = alertNotificationId(p.id);
        expect(a, inInclusiveRange(alertIdBase, alertIdBase + 10000000));
        for (final days in [1, 3]) {
          final r = reminderNotificationId(p.id, days);
          expect(isReminderNotificationId(r), isTrue);
          expect(r, lessThan(0x7fffffff));
          expect(isReminderNotificationId(a), isFalse);
        }
        expect(reminderNotificationId(p.id, 1), isNot(reminderNotificationId(p.id, 3)));
      });
    }
    test('fixture ids do not collide', () {
      final all = <int>{};
      for (final p in fixtureIndex.posts) {
        all
          ..add(alertNotificationId(p.id))
          ..add(reminderNotificationId(p.id, 1))
          ..add(reminderNotificationId(p.id, 3));
      }
      expect(all.length, fixtureIndex.posts.length * 3);
    });
    test('summary id is outside both ranges', () {
      expect(isReminderNotificationId(alertSummaryId), isFalse);
      expect(alertSummaryId, lessThan(alertIdBase));
    });
  });

  group('buildAlertMessages', () {
    List<AlertMessage> build(List<PostSummary> m) => buildAlertMessages(
          m,
          AppLang.en,
          singleTitle: (p) => 'New: ${p.title.en}',
          singleBody: (p) => p.org.en,
          summaryTitle: (n) => '$n new posts',
          summaryBody: (top) => top.map((p) => p.id).join(', '),
        );
    test('none', () => expect(build([]), isEmpty));
    for (var n = 1; n <= maxSingleAlerts; n++) {
      test('$n match(es) give $n notifications', () {
        final msgs = build([for (var i = 0; i < n; i++) post('p$i')]);
        expect(msgs.length, n);
        expect(msgs.every((m) => m.postId != null), isTrue);
        expect(msgs.first.title, 'New: Post p0');
        expect(msgs.first.id, alertNotificationId('p0'));
      });
    }
    for (final n in [4, 7, 30]) {
      test('$n matches give one summary', () {
        final msgs = build([for (var i = 0; i < n; i++) post('p$i')]);
        expect(msgs.length, 1);
        expect(msgs.single.id, alertSummaryId);
        expect(msgs.single.title, '$n new posts');
        expect(msgs.single.body, 'p0, p1, p2');
        expect(msgs.single.postId, isNull);
      });
    }
  });
}
