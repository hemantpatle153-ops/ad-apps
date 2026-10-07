import 'package:flutter_test/flutter_test.dart';
import 'package:vacancy_bell/config.dart';
import 'package:vacancy_bell/data/jobs_repository.dart';
import 'package:vacancy_bell/l10n/s.dart';
import 'package:vacancy_bell/logic/alerts.dart';
import 'package:vacancy_bell/logic/share_text.dart';
import 'package:vacancy_bell/models/post.dart';
import 'package:vacancy_bell/models/taxonomy.dart';
import 'package:vacancy_bell/services/sync.dart';

import 'support/fakes.dart';

void main() {
  group('syncReminders', () {
    test('schedules 3-day and 1-day reminders for reminded saved posts', () async {
      final w = TestWorld();
      final p = fixtureSummary('ssc-cgl-2026-notice');
      await w.settings.setSaved(p, true);
      await w.settings.setReminder(p.id, true);
      final plan = await syncReminders(w.settings, w.notifications, now: w.now);
      expect(plan.length, 2);
      expect(w.notifications.scheduled.length, 2);
      final titles = w.notifications.scheduled.values.map((e) => e.$2).toSet();
      expect(titles, {'3 days left: SSC CGL 2026 Recruitment', 'Last date tomorrow: SSC CGL 2026 Recruitment'});
      expect(w.notifications.scheduled.values.first.$3, 'Last date 05 Nov 2026. Apply before it closes.');
    });
    test('saved without reminder is not scheduled', () async {
      final w = TestWorld();
      await w.settings.setSaved(fixtureSummary('ssc-cgl-2026-notice'), true);
      await syncReminders(w.settings, w.notifications, now: w.now);
      expect(w.notifications.scheduled, isEmpty);
    });
    test('turning a reminder off cancels it', () async {
      final w = TestWorld();
      final p = fixtureSummary('ssc-cgl-2026-notice');
      await w.settings.setSaved(p, true);
      await w.settings.setReminder(p.id, true);
      await syncReminders(w.settings, w.notifications, now: w.now);
      await w.settings.setReminder(p.id, false);
      await syncReminders(w.settings, w.notifications, now: w.now);
      expect(w.notifications.scheduled, isEmpty);
    });
    test('Hindi wording', () async {
      final w = TestWorld(prefs: {'lang': 'hi'});
      final p = fixtureSummary('ssc-cgl-2026-notice');
      await w.settings.setSaved(p, true);
      await w.settings.setReminder(p.id, true);
      await syncReminders(w.settings, w.notifications, now: w.now);
      expect(w.notifications.scheduled.values.map((e) => e.$2), contains('कल अंतिम तिथि: एसएससी सीजीएल 2026 भर्ती'));
    });
    test('custom reminder time is used', () async {
      final w = TestWorld();
      final p = fixtureSummary('ssc-cgl-2026-notice');
      await w.settings.setSaved(p, true);
      await w.settings.setReminder(p.id, true);
      await w.settings.setReminderTime(20, 0);
      final plan = await syncReminders(w.settings, w.notifications, now: w.now);
      expect(plan.first.when, DateTime.utc(2026, 11, 2, 14, 30));
    });
  });

  group('runAlertCheck', () {
    test('first run seeds and shows nothing', () async {
      final w = TestWorld();
      final shown = await runAlertCheck(repo: w.repo, settings: w.settings, notifications: w.notifications, now: w.now);
      expect(shown, 0);
      expect(w.settings.seenIds!.length, 20);
      expect(w.settings.lastAlertCheck, w.now);
    });
    test('announces a new matching post', () async {
      final w = TestWorld();
      final seen = [for (final p in fixtureIndex.posts) if (p.id != 'ssc-cgl-2026-notice') p.id];
      await w.settings.setSeenIds(seen);
      final shown = await runAlertCheck(repo: w.repo, settings: w.settings, notifications: w.notifications, now: w.now);
      expect(shown, 1);
      final m = w.notifications.shown.single;
      expect(m.title, 'New: SSC CGL 2026 Recruitment');
      expect(m.body, 'Staff Selection Commission · Last date 05 Nov 2026');
      expect(m.postId, 'ssc-cgl-2026-notice');
      expect(w.settings.seenIds, contains('ssc-cgl-2026-notice'));
    });
    test('three new posts each get their own notification', () async {
      final w = TestWorld();
      await w.settings.setSeenIds(['something-old']);
      final shown = await runAlertCheck(repo: w.repo, settings: w.settings, notifications: w.notifications, now: w.now);
      expect(shown, 3);
      expect(w.notifications.shown.map((m) => m.postId).toSet(),
          {'ssc-cgl-2026-notice', 'rrb-ntpc-graduate-2026', 'up-police-constable-2026'});
    });
    test('many new posts become one summary', () async {
      final w = TestWorld();
      await w.settings.setSeenIds(['something-old']);
      await w.settings.setAlertPrefs(const AlertPrefs(types: {PostType.job, PostType.admitCard, PostType.syllabus}));
      final shown = await runAlertCheck(repo: w.repo, settings: w.settings, notifications: w.notifications, now: w.now);
      expect(shown, 1);
      expect(w.notifications.shown.single.id, alertSummaryId);
      expect(w.notifications.shown.single.title, endsWith('new posts for you'));
    });
    test('second run right after shows nothing', () async {
      final w = TestWorld();
      await w.settings.setSeenIds(['something-old']);
      await runAlertCheck(repo: w.repo, settings: w.settings, notifications: w.notifications, now: w.now);
      w.notifications.shown.clear();
      final shown = await runAlertCheck(repo: w.repo, settings: w.settings, notifications: w.notifications, now: w.now);
      expect(shown, 0);
    });
    test('alerts off: nothing shown, seen still updated', () async {
      final w = TestWorld();
      await w.settings.setSeenIds(['x']);
      await w.settings.setAlertPrefs(const AlertPrefs(enabled: false));
      expect(await runAlertCheck(repo: w.repo, settings: w.settings, notifications: w.notifications, now: w.now), 0);
      expect(w.settings.seenIds!.length, 21);
    });
    test('no permission: nothing shown', () async {
      final w = TestWorld();
      w.notifications.granted = false;
      await w.settings.setSeenIds(['x']);
      expect(await runAlertCheck(repo: w.repo, settings: w.settings, notifications: w.notifications, now: w.now), 0);
      expect(w.notifications.shown, isEmpty);
    });
    test('offline: nothing happens', () async {
      final w = TestWorld();
      w.fetcher.offline = true;
      await w.settings.setSeenIds(['x']);
      expect(await runAlertCheck(repo: w.repo, settings: w.settings, notifications: w.notifications, now: w.now), 0);
      expect(w.settings.seenIds, ['x']);
    });
    test('category choice filters alerts', () async {
      final w = TestWorld();
      await w.settings.setSeenIds(['x']);
      await w.settings.setAlertPrefs(const AlertPrefs(categories: {JobCategory.police}));
      await runAlertCheck(repo: w.repo, settings: w.settings, notifications: w.notifications, now: w.now);
      expect(w.notifications.shown.single.postId, 'up-police-constable-2026');
    });
    test('refreshes saved posts from the feed', () async {
      final w = TestWorld();
      final old = PostSummary.tryParse({...fixtureSummary('rpsc-ras-2026').toJson(), 'lastDate': '2026-10-20'})!;
      await w.settings.setSaved(old, true);
      await runAlertCheck(repo: w.repo, settings: w.settings, notifications: w.notifications, now: w.now);
      expect(w.settings.saved.single.lastDate.toString(), '2026-10-30');
    });
  });

  group('markIndexSeen', () {
    test('merges ids without duplicates', () async {
      final w = TestWorld();
      await w.settings.setSeenIds(['old', 'ssc-cgl-2026-notice']);
      await markIndexSeen(w.settings, fixtureIndex.posts);
      final seen = w.settings.seenIds!;
      expect(seen.toSet().length, seen.length);
      expect(seen, contains('old'));
      expect(seen.length, 21);
    });
  });

  group('share text', () {
    final p = fixtureSummary('ssc-cgl-2026-notice');
    final d = fixturePost('ssc-cgl-2026-notice');
    test('English with key facts', () {
      final t = buildShareText(S.en, p, detail: d);
      expect(t, startsWith('SSC CGL 2026 Recruitment\nStaff Selection Commission\n'));
      expect(t, contains('Posts: 14,582'));
      expect(t, contains('Last date: 05 Nov 2026'));
      expect(t, contains('Qualification: Graduate'));
      expect(t, contains('Age limit: 18 to 32 years'));
      expect(t, contains(d.officialNoticeUrl!));
      expect(t, contains('Verify on the official website'));
      expect(t, endsWith(AppConfig.playLink));
    });
    test('Hindi', () {
      final t = buildShareText(S.hi, p, detail: d);
      expect(t, startsWith('एसएससी सीजीएल 2026 भर्ती'));
      expect(t, contains('अंतिम तिथि: 05 नव॰ 2026'));
      expect(t, contains('पद: 14,582'));
    });
    test('without details uses the summary', () {
      final t = buildShareText(S.en, p);
      expect(t, contains('Last date: 05 Nov 2026'));
      expect(t, isNot(contains('https://ssc.gov.in')));
    });
    test('unknown facts are left out, no blank runs', () {
      final bare = PostSummary.tryParse({'id': 'bare', 'title': 'Bare post'})!;
      final t = buildShareText(S.en, bare);
      expect(t, isNot(contains('Last date')));
      expect(t, isNot(contains('Posts:')));
      expect(t, isNot(contains('\n\n\n')));
      expect(t.split('\n').first, 'Bare post');
    });
    test('"any" qualification is not listed', () {
      final t = buildShareText(S.en, fixtureSummary('nvs-class-6-admission-2027'));
      expect(t, isNot(contains('Qualification')));
    });
  });

  test('feed paths', () {
    expect(indexPath, 'jobs/index.json');
    expect(postPath('ssc-cgl-2026-notice'), 'jobs/posts/ssc-cgl-2026-notice.json');
  });

  test('feed base URL points at the feed-data branch', () {
    expect(AppConfig.feedBaseUrl,
        'https://raw.githubusercontent.com/hemantpatle153-ops/ad-apps-builds/feed-data/');
    expect(AppConfig.adsEnabled, isFalse);
  });
}
