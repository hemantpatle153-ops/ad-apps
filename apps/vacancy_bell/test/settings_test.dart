import 'package:flutter_test/flutter_test.dart';
import 'package:vacancy_bell/core/json_read.dart';
import 'package:vacancy_bell/core/ymd.dart';
import 'package:vacancy_bell/data/kv_store.dart';
import 'package:vacancy_bell/data/settings.dart';
import 'package:vacancy_bell/logic/alerts.dart';
import 'package:vacancy_bell/models/post.dart';
import 'package:vacancy_bell/models/profile.dart';
import 'package:vacancy_bell/models/taxonomy.dart';

import 'support/fakes.dart';

void main() {
  late MemoryStore store;
  late AppSettings s;
  setUp(() {
    store = MemoryStore();
    s = AppSettings(store);
  });

  group('language and theme', () {
    test('no language before first run', () {
      expect(s.langOrNull, isNull);
      expect(s.lang, AppLang.en);
    });
    test('set Hindi', () async {
      await s.setLang(AppLang.hi);
      expect(s.lang, AppLang.hi);
      expect(AppSettings(store).lang, AppLang.hi);
    });
    test('theme default and change', () async {
      expect(s.theme, ThemeChoice.system);
      await s.setTheme(ThemeChoice.dark);
      expect(s.theme, ThemeChoice.dark);
    });
    test('unknown stored theme falls back', () {
      store.values['theme'] = 'neon';
      expect(s.theme, ThemeChoice.system);
    });
    test('onboarded flag', () async {
      expect(s.onboarded, isFalse);
      await s.setOnboarded();
      expect(s.onboarded, isTrue);
    });
    test('writes notify listeners', () async {
      var n = 0;
      s.addListener(() => n++);
      await s.setLang(AppLang.hi);
      await s.setTheme(ThemeChoice.light);
      await s.setProfile(const UserProfile(state: 'UP'));
      expect(n, 3);
    });
  });

  group('profile', () {
    test('empty by default', () => expect(s.profile.isEmpty, isTrue));
    test('round trip', () async {
      final p = UserProfile(
        dob: Ymd(2000, 5, 17),
        qualification: Qualification.engineering,
        category: SocialCategory.obc,
        pwbd: true,
        exServiceman: true,
        state: 'MH',
        gender: Gender.female,
      );
      await s.setProfile(p);
      expect(AppSettings(store).profile, p);
    });
    test('corrupt profile reads as empty', () {
      store.values['profile'] = '{oops';
      expect(s.profile, UserProfile.empty);
    });
    test('bad fields are dropped one by one', () {
      store.values['profile'] =
          '{"dob":"17-05-2000","qualification":"any","category":"vip","state":"all","gender":"m","pwbd":"yes"}';
      final p = s.profile;
      expect(p.dob, isNull);
      expect(p.qualification, isNull);
      expect(p.category, isNull);
      expect(p.state, isNull);
      expect(p.gender, isNull);
      expect(p.pwbd, isFalse);
    });
    test('copyWith can clear a field', () {
      final p = UserProfile(dob: Ymd(2000, 1, 1), state: 'UP');
      expect(p.copyWith(dob: () => null).dob, isNull);
      expect(p.copyWith(dob: () => null).state, 'UP');
    });
    test('canCheckEligibility needs dob or qualification', () {
      expect(const UserProfile(state: 'UP').canCheckEligibility, isFalse);
      expect(UserProfile(dob: Ymd(2000, 1, 1)).canCheckEligibility, isTrue);
      expect(const UserProfile(qualification: Qualification.class10).canCheckEligibility, isTrue);
    });
  });

  group('saved posts', () {
    final a = fixtureSummary('ssc-cgl-2026-notice');
    final b = fixtureSummary('up-police-constable-2026');

    test('save, newest first', () async {
      await s.setSaved(a, true);
      await s.setSaved(b, true);
      expect(s.saved.map((p) => p.id), [b.id, a.id]);
      expect(s.isSaved(a.id), isTrue);
    });
    test('saving twice keeps one copy and moves it up', () async {
      await s.setSaved(a, true);
      await s.setSaved(b, true);
      await s.setSaved(a, true);
      expect(s.saved.map((p) => p.id), [a.id, b.id]);
    });
    test('unsave', () async {
      await s.setSaved(a, true);
      await s.setSaved(a, false);
      expect(s.saved, isEmpty);
      expect(s.isSaved(a.id), isFalse);
    });
    test('survives restart with all fields', () async {
      await s.setSaved(a, true);
      final back = AppSettings(store).saved.single;
      expect(back.lastDate, a.lastDate);
      expect(back.title, a.title);
      expect(back.totalPosts, a.totalPosts);
    });
    test('refreshSaved updates changed posts', () async {
      await s.setSaved(a, true);
      final changed = PostSummary.tryParse({...a.toJson(), 'lastDate': '2026-11-20'})!;
      expect(await s.refreshSaved([changed]), isTrue);
      expect(s.saved.single.lastDate, Ymd(2026, 11, 20));
    });
    test('refreshSaved with no change', () async {
      await s.setSaved(a, true);
      expect(await s.refreshSaved([a, b]), isFalse);
    });
    test('refreshSaved keeps posts that left the feed', () async {
      await s.setSaved(a, true);
      expect(await s.refreshSaved([b]), isFalse);
      expect(s.saved.single.id, a.id);
    });
    test('corrupt entries are skipped', () {
      store.values['saved'] = '[{"id":"ok-1","title":"OK"}, {"id":"Bad Id"}, 5]';
      expect(s.saved.map((p) => p.id), ['ok-1']);
    });
  });

  group('reminders', () {
    test('toggle', () async {
      await s.setReminder('a-1', true);
      expect(s.hasReminder('a-1'), isTrue);
      await s.setReminder('a-1', false);
      expect(s.hasReminder('a-1'), isFalse);
    });
    test('invalid ids in storage are ignored', () {
      store.values['reminders'] = '["ok", "Bad Id", 3]';
      expect(s.reminders, {'ok'});
    });
    test('the returned set is a copy', () {
      s.reminders.add('x');
      expect(s.reminders, isEmpty);
    });
    test('time default 09:00', () => expect(s.reminderTime, (9, 0)));
    test('time change', () async {
      await s.setReminderTime(18, 30);
      expect(s.reminderTime, (18, 30));
    });
    test('bad stored time falls back', () {
      store.values['reminderTime'] = '{"h": 30, "m": 0}';
      expect(s.reminderTime, (9, 0));
    });
  });

  group('alerts state', () {
    test('default prefs', () {
      expect(s.alertPrefs.enabled, isTrue);
      expect(s.alertPrefs.types, {PostType.job});
    });
    test('prefs round trip', () async {
      await s.setAlertPrefs(const AlertPrefs(enabled: false, categories: {JobCategory.banking}));
      expect(s.alertPrefs.enabled, isFalse);
      expect(s.alertPrefs.categories, {JobCategory.banking});
    });
    test('seen ids are null until the first check', () => expect(s.seenIds, isNull));
    test('seen ids keep order', () async {
      await s.setSeenIds(['c', 'b', 'a']);
      expect(s.seenIds, ['c', 'b', 'a']);
    });
    test('last check time', () async {
      await s.setLastAlertCheck(fixtureNow);
      expect(s.lastAlertCheck, fixtureNow);
    });
    test('permission asked flag', () async {
      expect(s.notificationPermissionAsked, isFalse);
      await s.setNotificationPermissionAsked();
      expect(s.notificationPermissionAsked, isTrue);
    });
  });

  group('memo is cleared by writes and reload', () {
    test('profile read after write is fresh', () async {
      expect(s.profile.state, isNull);
      await s.setProfile(const UserProfile(state: 'UP'));
      expect(s.profile.state, 'UP');
    });
    test('reload picks up another isolate\'s write', () async {
      expect(s.saved, isEmpty);
      store.values['saved'] = '[{"id":"bg-1","title":"From background"}]';
      expect(s.saved, isEmpty); // memoised
      await s.reload();
      expect(s.saved.single.id, 'bg-1');
    });
  });
}
