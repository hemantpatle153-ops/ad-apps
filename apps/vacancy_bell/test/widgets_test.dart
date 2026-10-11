import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vacancy_bell/app.dart';
import 'package:vacancy_bell/core/json_read.dart';
import 'package:vacancy_bell/core/ymd.dart';
import 'package:vacancy_bell/data/jobs_repository.dart';
import 'package:vacancy_bell/data/settings.dart';
import 'package:vacancy_bell/l10n/s.dart';
import 'package:vacancy_bell/l10n/strings.dart';
import 'package:vacancy_bell/logic/report.dart';
import 'package:vacancy_bell/models/profile.dart';
import 'package:vacancy_bell/models/taxonomy.dart';
import 'package:vacancy_bell/ui/age_calculator_screen.dart';
import 'package:vacancy_bell/ui/detail_screen.dart';
import 'package:vacancy_bell/ui/disclaimer_screen.dart';
import 'package:vacancy_bell/ui/onboarding.dart';
import 'package:vacancy_bell/ui/post_card.dart';
import 'package:vacancy_bell/ui/report_sheet.dart';
import 'package:vacancy_bell/ui/scope.dart';
import 'package:vacancy_bell/ui/theme.dart';
import 'package:vacancy_bell/ui/widgets.dart';

import 'support/fakes.dart';

final en = S.en;
String t(L key, [Map<String, Object?> args = const {}]) => en.t(key, args);

const _cgl = 'SSC CGL 2026 Recruitment';

/// Pumps the whole app around [world] on a phone-sized screen.
Future<TestWorld> pumpApp(
  WidgetTester tester, {
  TestWorld? world,
  bool start = true,
  double textScale = 1.0,
  Size size = const Size(400, 860),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final w = world ?? TestWorld();
  await tester.pumpWidget(VacancyBellApp(controller: w.controller));
  if (start) {
    await w.controller.start();
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return w;
}

/// Pumps a single screen with the app's scope and theme.
Future<TestWorld> pumpScreen(WidgetTester tester, Widget screen,
    {TestWorld? world, bool start = true, double textScale = 1.0}) async {
  tester.view.physicalSize = const Size(400, 860) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final w = world ?? TestWorld();
  if (start) await w.controller.start();
  await tester.pumpWidget(AppScope(
    controller: w.controller,
    child: MaterialApp(theme: vacancyTheme(Brightness.light), home: screen),
  ));
  await tester.pumpAndSettle();
  return w;
}

Future<void> openTab(WidgetTester tester, L label) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(t(label))));
  await tester.pumpAndSettle();
}

Future<void> openCgl(WidgetTester tester) async {
  await tester.tap(find.text(_cgl).first);
  await tester.pumpAndSettle();
}

Finder get _jobList => find
    .descendant(of: find.byKey(const PageStorageKey<String>('list-job')), matching: find.byType(Scrollable))
    .first;

Finder get _detailList =>
    find.descendant(of: find.byType(DetailScreen), matching: find.byType(Scrollable)).first;

Future<void> scrollTo(WidgetTester tester, Finder f, {Finder? scrollable}) =>
    tester.scrollUntilVisible(f, 250, scrollable: scrollable ?? _detailList);

String indexWith(List<Map<String, Object?>> posts, {int schema = 1}) =>
    jsonEncode({'schema': schema, 'generatedAt': '2026-10-07T06:00:00Z', 'posts': posts});

Map<String, Object?> summaryJson(String id) => fixtureSummary(id).toJson();

void main() {
  group('home: list', () {
    testWidgets('shows the jobs tab with posts and a count', (tester) async {
      final w = await pumpApp(tester);
      expect(find.text(_cgl), findsOneWidget);
      final n = w.controller.postsOf(PostType.job).length;
      expect(n, 12);
      expect(find.text(t(L.resultsCount, {'n': n})), findsOneWidget);
      expect(find.byType(PostCard), findsWidgets);
    });

    testWidgets('app name in the bar, no "Official"', (tester) async {
      await pumpApp(tester);
      expect(find.text('Vacancy Bell'), findsOneWidget);
      expect(find.textContaining('Official'), findsNothing);
    });

    testWidgets('all post-type tabs are present', (tester) async {
      await pumpApp(tester);
      expect(find.byType(Tab), findsNWidgets(7));
      expect(find.text(en.postType(PostType.job)), findsWidgets);
      expect(find.text(en.postType(PostType.admitCard)), findsOneWidget);
    });

    testWidgets('admit card tab lists admit cards only', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text(en.postType(PostType.admitCard)));
      await tester.pumpAndSettle();
      expect(find.text('SSC CHSL 2026 Tier 1 Admit Card'), findsOneWidget);
      expect(find.text(_cgl), findsNothing);
      expect(find.text(t(L.resultsCount, {'n': 2})), findsOneWidget);
    });

    testWidgets('newest post comes first and shows the New badge', (tester) async {
      await pumpApp(tester);
      final first = tester.widget<PostCard>(find.byType(PostCard).first);
      expect(first.post.id, 'ssc-cgl-2026-notice');
      expect(find.descendant(of: find.byType(PostCard).first, matching: find.text(t(L.badgeNew))),
          findsOneWidget);
    });

    testWidgets('urgent card shows days left', (tester) async {
      await pumpApp(tester);
      // RRB NTPC closes on 9 Oct: two days after "today".
      expect(find.text(t(L.daysLeft, {'n': 2})), findsWidgets);
    });

    testWidgets('closing today shows "Last day today"', (tester) async {
      await pumpApp(tester);
      await tester.scrollUntilVisible(find.text('IBPS PO/MT XV 2026'), 300, scrollable: _jobList);
      expect(find.text(t(L.lastDayToday)), findsWidgets);
    });

    testWidgets('closed post shows Closed', (tester) async {
      await pumpApp(tester);
      await tester.scrollUntilVisible(find.text('Bihar STET 2026'), 300, scrollable: _jobList);
      expect(find.text(t(L.closed)), findsWidgets);
    });

    testWidgets('eligibility badge appears once details are set', (tester) async {
      final w = TestWorld();
      await w.settings.setProfile(const UserProfile(qualification: Qualification.class10));
      await pumpApp(tester, world: w);
      // SSC CGL needs a degree.
      expect(find.descendant(of: find.byType(PostCard).first, matching: find.text(t(L.eligibleNoQual))),
          findsOneWidget);
    });

    testWidgets('no eligibility badge without details', (tester) async {
      await pumpApp(tester);
      expect(find.text(t(L.eligibleYes)), findsNothing);
      expect(find.text(t(L.eligibleCheck)), findsNothing);
    });

    testWidgets('pull to refresh fetches again', (tester) async {
      final w = await pumpApp(tester);
      final before = w.fetcher.requests.length;
      await tester.fling(_jobList, const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(w.fetcher.requests.length, greaterThan(before));
    });
  });

  group('home: search', () {
    testWidgets('typing filters the list', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.byTooltip(t(L.search)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'police');
      await tester.pumpAndSettle();
      expect(find.text('UP Police Constable 2026'), findsOneWidget);
      expect(find.text(_cgl), findsNothing);
    });

    testWidgets('Hindi search text works', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.byTooltip(t(L.search)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'पुलिस');
      await tester.pumpAndSettle();
      expect(find.text('UP Police Constable 2026'), findsOneWidget);
    });

    testWidgets('no match shows the empty-search state and can clear', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.byTooltip(t(L.search)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'zzzz nothing');
      await tester.pumpAndSettle();
      expect(find.text(t(L.emptySearch)), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, t(L.clearAll)));
      await tester.pumpAndSettle();
      expect(find.text(_cgl), findsOneWidget);
    });

    testWidgets('closing search restores everything', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.byTooltip(t(L.search)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'police');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(t(L.clearSearch)));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text(_cgl), findsOneWidget);
    });
  });

  group('home: filters', () {
    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.byTooltip(t(L.filters)));
      await tester.pumpAndSettle();
    }

    testWidgets('sheet opens with all sections', (tester) async {
      await pumpApp(tester);
      await openSheet(tester);
      expect(find.text(t(L.sortBy)), findsOneWidget);
      expect(find.text(t(L.onlyEligible)), findsOneWidget);
      expect(find.text(t(L.filterCategory)), findsOneWidget);
    });

    testWidgets('category filter narrows the list and shows a badge', (tester) async {
      final w = await pumpApp(tester);
      await openSheet(tester);
      await tester.tap(find.widgetWithText(FilterChip, en.category(JobCategory.police)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t(L.showResults)));
      await tester.pumpAndSettle();
      expect(w.controller.query.categories, {JobCategory.police});
      expect(find.text('UP Police Constable 2026'), findsOneWidget);
      expect(find.text(_cgl), findsNothing);
      // Badge count and an active filter chip.
      expect(find.descendant(of: find.byType(Badge), matching: find.text('1')), findsOneWidget);
      expect(find.widgetWithText(InputChip, en.category(JobCategory.police)), findsOneWidget);
    });

    testWidgets('removing the chip clears that filter', (tester) async {
      final w = await pumpApp(tester);
      await openSheet(tester);
      await tester.tap(find.widgetWithText(FilterChip, en.category(JobCategory.police)));
      await tester.tap(find.text(t(L.showResults)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(t(L.remove)));
      await tester.pumpAndSettle();
      expect(w.controller.query.isDefault, isTrue);
      expect(find.text(_cgl), findsOneWidget);
    });

    testWidgets('closing-soon sort puts the earliest open deadline first', (tester) async {
      await pumpApp(tester);
      await openSheet(tester);
      await tester.tap(find.text(t(L.sortClosing)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t(L.showResults)));
      await tester.pumpAndSettle();
      final first = tester.widget<PostCard>(find.byType(PostCard).first);
      expect(first.post.id, 'ibps-po-xv-2026');
    });

    testWidgets('only-eligible needs details first', (tester) async {
      await pumpApp(tester);
      await openSheet(tester);
      expect(find.text(t(L.onlyEligibleNeedsProfile)), findsOneWidget);
      final sw = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, t(L.onlyEligible)));
      expect(sw.onChanged, isNull);
    });

    testWidgets('only-eligible hides posts the user cannot apply for', (tester) async {
      final w = TestWorld();
      await w.settings.setProfile(const UserProfile(qualification: Qualification.class10));
      await pumpApp(tester, world: w);
      await openSheet(tester);
      await tester.tap(find.widgetWithText(SwitchListTile, t(L.onlyEligible)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t(L.showResults)));
      await tester.pumpAndSettle();
      expect(w.controller.query.onlyEligible, isTrue);
      expect(find.text(_cgl), findsNothing);
    });

    testWidgets('clear all in the sheet resets choices', (tester) async {
      final w = await pumpApp(tester);
      await openSheet(tester);
      await tester.tap(find.widgetWithText(FilterChip, en.category(JobCategory.police)));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, t(L.clearAll)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t(L.showResults)));
      await tester.pumpAndSettle();
      expect(w.controller.query.isDefault, isTrue);
    });

    testWidgets('filtered to nothing shows the empty-search state', (tester) async {
      final w = await pumpApp(tester);
      w.controller.setQuery(w.controller.query.copyWith(categories: {JobCategory.medical}, hideClosed: true, state: () => 'KL'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.postType(PostType.admitCard)));
      await tester.pumpAndSettle();
      expect(find.text(t(L.emptySearch)), findsOneWidget);
    });
  });

  group('home: states', () {
    testWidgets('loading shows the skeleton', (tester) async {
      final f = fixtureFetcher()..delay = const Duration(seconds: 2);
      final w = await pumpApp(tester, world: TestWorld(fetcher: f), start: false);
      final started = w.controller.start();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(SkeletonList), findsWidgets);
      expect(find.bySemanticsLabel(t(L.loading)), findsWidgets);
      await tester.pump(const Duration(seconds: 3));
      await started;
      await tester.pumpAndSettle();
      expect(find.byType(SkeletonList), findsNothing);
      expect(find.text(_cgl), findsOneWidget);
    });

    testWidgets('offline with nothing cached shows the error with retry', (tester) async {
      final w = TestWorld()..fetcher.offline = true;
      await pumpApp(tester, world: w);
      expect(find.text(t(L.loadErrorTitle)), findsOneWidget);
      expect(find.text(t(L.errorOffline)), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
      w.fetcher.offline = false;
      await tester.tap(find.text(t(L.retry)));
      await tester.pumpAndSettle();
      expect(find.text(_cgl), findsOneWidget);
    });

    testWidgets('server error shows the server message', (tester) async {
      final w = TestWorld()..fetcher.forceStatus = 500;
      await pumpApp(tester, world: w);
      expect(find.text(t(L.loadErrorTitle)), findsOneWidget);
      expect(find.text(t(L.errorServer)), findsOneWidget);
    });

    testWidgets('broken feed shows the bad-data message', (tester) async {
      final w = TestWorld(fetcher: FakeFetcher({indexPath: '<html>not json</html>'}));
      await pumpApp(tester, world: w);
      expect(find.text(t(L.errorBadData)), findsOneWidget);
    });

    testWidgets('offline with a cached copy shows posts and a banner', (tester) async {
      final w = await pumpApp(tester);
      w.fetcher.offline = true;
      await w.controller.refresh();
      await tester.pumpAndSettle();
      expect(find.text(_cgl), findsOneWidget);
      expect(find.byType(InfoBanner), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
      expect(find.textContaining('just now'), findsOneWidget);
    });

    testWidgets('the banner retry fetches again and clears it', (tester) async {
      final w = await pumpApp(tester);
      w.fetcher.offline = true;
      await w.controller.refresh();
      await tester.pumpAndSettle();
      w.fetcher.offline = false;
      await tester.tap(find.descendant(of: find.byType(InfoBanner), matching: find.text(t(L.retry))));
      await tester.pumpAndSettle();
      expect(find.byType(InfoBanner), findsNothing);
    });

    testWidgets('a cached list is shown at once when starting offline', (tester) async {
      final w = TestWorld();
      await w.repo.index(); // fills the cache
      w.fetcher.offline = true;
      await pumpApp(tester, world: w);
      expect(find.text(_cgl), findsOneWidget);
      expect(find.byType(InfoBanner), findsOneWidget);
    });

    testWidgets('an empty tab says so', (tester) async {
      final w = TestWorld(fetcher: FakeFetcher({indexPath: indexWith([summaryJson('ssc-cgl-2026-notice')])}));
      await pumpApp(tester, world: w);
      await tester.tap(find.text(en.postType(PostType.admitCard)));
      await tester.pumpAndSettle();
      expect(find.text(t(L.emptyTab)), findsOneWidget);
      expect(find.text(t(L.emptyTabHint)), findsOneWidget);
    });

    testWidgets('an empty feed shows empty tabs, not an error', (tester) async {
      final w = TestWorld(fetcher: FakeFetcher({indexPath: indexWith([])}));
      await pumpApp(tester, world: w);
      expect(find.text(t(L.emptyTab)), findsOneWidget);
      expect(find.text(t(L.loadErrorTitle)), findsNothing);
    });

    testWidgets('a newer feed format asks to update the app', (tester) async {
      final w = TestWorld(
          fetcher: FakeFetcher({indexPath: indexWith([summaryJson('ssc-cgl-2026-notice')], schema: 2)}));
      await pumpApp(tester, world: w);
      expect(find.text(t(L.feedNewer)), findsOneWidget);
      expect(find.text(_cgl), findsOneWidget);
    });
  });

  group('navigation', () {
    testWidgets('bottom bar has four destinations', (tester) async {
      await pumpApp(tester);
      expect(find.byType(NavigationDestination), findsNWidgets(4));
    });

    testWidgets('Saved starts empty', (tester) async {
      await pumpApp(tester);
      await openTab(tester, L.navSaved);
      expect(find.text(t(L.savedEmpty)), findsOneWidget);
    });

    testWidgets('More lists tools and about', (tester) async {
      await pumpApp(tester);
      await openTab(tester, L.navMore);
      expect(find.text(t(L.myDetails)), findsOneWidget);
      expect(find.text(t(L.ageCalculator)), findsOneWidget);
      expect(find.text(t(L.disclaimer)), findsOneWidget);
      expect(find.text(t(L.privacyPolicy)), findsOneWidget);
    });

    testWidgets('More > privacy policy opens the link', (tester) async {
      final w = await pumpApp(tester);
      await openTab(tester, L.navMore);
      await tester.tap(find.text(t(L.privacyPolicy)));
      await tester.pumpAndSettle();
      expect(w.actions.opened.single, contains('privacy/vacancy_bell'));
    });

    testWidgets('More > disclaimer opens the screen', (tester) async {
      await pumpApp(tester);
      await openTab(tester, L.navMore);
      await tester.tap(find.text(t(L.disclaimer)));
      await tester.pumpAndSettle();
      expect(find.byType(DisclaimerScreen), findsOneWidget);
    });

    testWidgets('More > age calculator opens the screen', (tester) async {
      await pumpApp(tester);
      await openTab(tester, L.navMore);
      await tester.tap(find.text(t(L.ageCalculator)));
      await tester.pumpAndSettle();
      expect(find.byType(AgeCalculatorScreen), findsOneWidget);
    });

    testWidgets('notification tap opens the post', (tester) async {
      final key = GlobalKey<NavigatorState>();
      final w = TestWorld();
      await w.controller.start();
      tester.view.physicalSize = const Size(1200, 2580);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(VacancyBellApp(controller: w.controller, navigatorKey: key));
      await tester.pumpAndSettle();
      openPostFromNotification(key, 'up-police-constable-2026');
      await tester.pumpAndSettle();
      expect(find.byType(DetailScreen), findsOneWidget);
      expect(find.text('UP Police Constable 2026'), findsWidgets);
    });

    testWidgets('empty notification payload does nothing', (tester) async {
      final key = GlobalKey<NavigatorState>();
      final w = TestWorld();
      await tester.pumpWidget(VacancyBellApp(controller: w.controller, navigatorKey: key));
      await tester.pump();
      openPostFromNotification(key, '');
      openPostFromNotification(key, null);
      await tester.pump();
      expect(find.byType(DetailScreen), findsNothing);
    });
  });

  group('detail', () {
    testWidgets('shows the header and the main sections', (tester) async {
      await pumpApp(tester);
      await openCgl(tester);
      expect(find.byType(DetailScreen), findsOneWidget);
      expect(find.text('Staff Selection Commission'), findsWidgets);
      expect(find.text(t(L.postsCount, {'n': '14,582'})), findsOneWidget);
      for (final key in [L.importantDates, L.applicationFee, L.ageLimit, L.vacancyDetails]) {
        await scrollTo(tester, find.text(t(key)));
        expect(find.text(t(key)), findsOneWidget);
      }
    });

    testWidgets('verify note and report button are at the end', (tester) async {
      await pumpApp(tester);
      await openCgl(tester);
      await scrollTo(tester, find.text(t(L.verifyNote)));
      expect(find.text(t(L.verifyNote)), findsOneWidget);
      await scrollTo(tester, find.widgetWithText(TextButton, t(L.reportMistake)));
      expect(find.widgetWithText(TextButton, t(L.reportMistake)), findsOneWidget);
    });

    testWidgets('bookmark saves and unsaves', (tester) async {
      final w = await pumpApp(tester);
      await openCgl(tester);
      await tester.tap(find.byTooltip(t(L.save)));
      await tester.pumpAndSettle();
      expect(w.settings.isSaved('ssc-cgl-2026-notice'), isTrue);
      expect(find.byTooltip(t(L.unsave)), findsOneWidget);
      await tester.tap(find.byTooltip(t(L.unsave)));
      await tester.pumpAndSettle();
      expect(w.settings.isSaved('ssc-cgl-2026-notice'), isFalse);
    });

    testWidgets('share sends a text with the key facts', (tester) async {
      final w = await pumpApp(tester);
      await openCgl(tester);
      await tester.tap(find.byTooltip(t(L.share)));
      await tester.pumpAndSettle();
      expect(w.actions.shared.single, startsWith(_cgl));
      expect(w.actions.shared.single, contains('Last date: 05 Nov 2026'));
    });

    testWidgets('remind me schedules two reminders and saves the post', (tester) async {
      final w = await pumpApp(tester);
      await openCgl(tester);
      await tester.tap(find.text(t(L.remindMe)));
      await tester.pumpAndSettle();
      expect(w.notifications.scheduled.length, 2);
      expect(w.settings.isSaved('ssc-cgl-2026-notice'), isTrue);
      expect(find.text(t(L.reminderOn)), findsOneWidget);
      expect(find.text(t(L.reminderOnDetail, {'time': '09:00'})), findsOneWidget);
    });

    testWidgets('turning the reminder off cancels it', (tester) async {
      final w = await pumpApp(tester);
      await openCgl(tester);
      await tester.tap(find.text(t(L.remindMe)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t(L.reminderOn)));
      await tester.pumpAndSettle();
      expect(w.notifications.scheduled, isEmpty);
      expect(find.text(t(L.reminderOff)), findsOneWidget);
    });

    testWidgets('without permission the rationale is shown first', (tester) async {
      final w = TestWorld();
      w.notifications.granted = false;
      await pumpApp(tester, world: w);
      await openCgl(tester);
      await tester.tap(find.text(t(L.remindMe)));
      await tester.pumpAndSettle();
      expect(find.text(t(L.notifRationaleTitle)), findsOneWidget);
      await tester.tap(find.text(t(L.allow)));
      await tester.pumpAndSettle();
      expect(w.notifications.permissionRequests, 1);
      expect(w.settings.notificationPermissionAsked, isTrue);
      expect(w.notifications.scheduled.length, 2);
    });

    testWidgets('"Not now" does not ask Android', (tester) async {
      final w = TestWorld();
      w.notifications.granted = false;
      await pumpApp(tester, world: w);
      await openCgl(tester);
      await tester.tap(find.text(t(L.remindMe)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t(L.notNow)));
      await tester.pumpAndSettle();
      expect(w.notifications.permissionRequests, 0);
    });

    testWidgets('a closed post cannot get a reminder', (tester) async {
      final w = await pumpApp(tester);
      await tester.scrollUntilVisible(find.text('Bihar STET 2026'), 300, scrollable: _jobList);
      await tester.tap(find.text('Bihar STET 2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t(L.remindMe)));
      await tester.pumpAndSettle();
      expect(find.text(t(L.reminderUnavailable)), findsOneWidget);
      expect(w.notifications.scheduled, isEmpty);
    });

    testWidgets('official notice button opens the link', (tester) async {
      final w = await pumpApp(tester);
      await openCgl(tester);
      await tester.tap(find.text(t(L.seeNotice)).last);
      await tester.pumpAndSettle();
      expect(w.actions.opened.single, startsWith('https://'));
    });

    testWidgets('a link that cannot open shows a message', (tester) async {
      final w = await pumpApp(tester);
      w.actions.openResult = false;
      await openCgl(tester);
      await tester.tap(find.text(t(L.seeNotice)).last);
      await tester.pumpAndSettle();
      expect(find.text(t(L.openLinkFailed)), findsOneWidget);
    });

    testWidgets('no details yet: eligibility card points to My details', (tester) async {
      await pumpApp(tester);
      await openCgl(tester);
      expect(find.text(t(L.eligNoProfile)), findsWidgets);
    });

    testWidgets('with details the eligibility verdict is explained', (tester) async {
      final w = TestWorld();
      await w.settings.setProfile(UserProfile(
          dob: Ymd(2001, 3, 10), qualification: Qualification.graduate, category: SocialCategory.general));
      await pumpApp(tester, world: w);
      await openCgl(tester);
      expect(find.text(t(L.yourEligibility)), findsOneWidget);
      expect(find.text(t(L.eligQualYes)), findsOneWidget);
      expect(find.text(t(L.eligDisclaimer)), findsOneWidget);
    });

    testWidgets('class 10 profile is told the qualification is short', (tester) async {
      final w = TestWorld();
      await w.settings.setProfile(const UserProfile(qualification: Qualification.class10));
      await pumpApp(tester, world: w);
      await openCgl(tester);
      expect(find.text(t(L.eligQualNo)), findsOneWidget);
      expect(find.text(t(L.eligibleNoQual)), findsWidgets);
    });

    testWidgets('details offline: summary still shown with a retry card', (tester) async {
      final w = TestWorld(fetcher: fixtureFetcher(withPosts: false));
      await pumpApp(tester, world: w);
      w.fetcher.offline = true;
      await openCgl(tester);
      expect(find.text(_cgl), findsOneWidget);
      expect(find.text(t(L.detailsOffline)), findsOneWidget);
      expect(find.text(t(L.retry)), findsOneWidget);
    });

    testWidgets('details missing on the server says the post is gone', (tester) async {
      final w = TestWorld(fetcher: fixtureFetcher(withPosts: false));
      await pumpApp(tester, world: w);
      await openCgl(tester);
      expect(find.text(t(L.postGone)), findsOneWidget);
    });

    testWidgets('retry loads the details once back online', (tester) async {
      final w = await pumpApp(tester);
      w.fetcher.offline = true;
      await openCgl(tester);
      expect(find.text(t(L.detailsOffline)), findsOneWidget);
      w.fetcher.offline = false;
      await tester.tap(find.text(t(L.retry)));
      await tester.pumpAndSettle();
      expect(find.text(t(L.detailsOffline)), findsNothing);
      await scrollTo(tester, find.text(t(L.importantDates)));
      expect(find.text(t(L.importantDates)), findsOneWidget);
    });

    testWidgets('unknown post from a notification, offline', (tester) async {
      final w = TestWorld()..fetcher.offline = true;
      await pumpScreen(tester, const DetailScreen(postId: 'no-such-post'), world: w);
      expect(find.text(t(L.detailsFailed)), findsOneWidget);
    });

    testWidgets('broken sections in a post do not break the screen', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('RRB NTPC Graduate Level 2026'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(DetailScreen), findsOneWidget);
    });
  });

  group('report a mistake', () {
    Future<void> openReport(WidgetTester tester) async {
      await openCgl(tester);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(PopupMenuItem<String>), matching: find.text(t(L.reportMistake))));
      await tester.pumpAndSettle();
    }

    testWidgets('sheet lists every reason; send is disabled until one is picked', (tester) async {
      await pumpApp(tester);
      await openReport(tester);
      for (final r in ReportReason.values) {
        expect(find.widgetWithText(ChoiceChip, en.reportReason(r)), findsOneWidget);
      }
      final send = tester.widget<FilledButton>(
          find.ancestor(of: find.text(t(L.reportSend)), matching: find.byWidgetPredicate((w) => w is FilledButton)));
      expect(send.onPressed, isNull);
    });

    testWidgets('sends a report and thanks the user', (tester) async {
      final w = await pumpApp(tester);
      await openReport(tester);
      await tester.tap(find.text(en.reportReason(ReportReason.wrongDate)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Last date is 6 Nov');
      await tester.tap(find.text(t(L.reportSend)));
      await tester.pumpAndSettle();
      expect(w.reportBackend.sent.single.item, 'ssc-cgl-2026-notice');
      expect(w.reportBackend.sent.single.reason, ReportReason.wrongDate);
      expect(w.reportBackend.sent.single.cleanNote, 'Last date is 6 Nov');
      expect(find.text(t(L.reportSent)), findsOneWidget);
      expect(find.byType(ReportSheet), findsNothing);
    });

    testWidgets('"Other" needs a note', (tester) async {
      final w = await pumpApp(tester);
      await openReport(tester);
      await tester.tap(find.text(en.reportReason(ReportReason.other)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t(L.reportSend)));
      await tester.pumpAndSettle();
      expect(find.text(t(L.reportNoteRequired)), findsOneWidget);
      expect(w.reportBackend.sent, isEmpty);
    });

    testWidgets('a failed send says so and keeps the sheet', (tester) async {
      final w = await pumpApp(tester);
      w.reportBackend.fail = true;
      await openReport(tester);
      await tester.tap(find.text(en.reportReason(ReportReason.brokenLink)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t(L.reportSend)));
      await tester.pumpAndSettle();
      expect(find.text(t(L.reportFailed)), findsOneWidget);
      expect(find.text(t(L.reportPickReason)), findsOneWidget);
    });

    testWidgets('the same report twice is caught', (tester) async {
      final w = await pumpApp(tester);
      await w.reports.submit(const ReportDraft(item: 'ssc-cgl-2026-notice', reason: ReportReason.wrongFee));
      await openReport(tester);
      await tester.tap(find.text(en.reportReason(ReportReason.wrongFee)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t(L.reportSend)));
      await tester.pumpAndSettle();
      expect(find.text(t(L.reportDuplicate)), findsOneWidget);
      expect(w.reportBackend.sent.length, 1);
    });

    testWidgets('the daily limit is shown', (tester) async {
      final w = await pumpApp(tester);
      for (var i = 0; i < maxReportsPerDay; i++) {
        await w.reports.submit(ReportDraft(item: 'p-$i', reason: ReportReason.wrongFee));
      }
      await openReport(tester);
      await tester.tap(find.text(en.reportReason(ReportReason.wrongDate)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t(L.reportSend)));
      await tester.pumpAndSettle();
      expect(find.text(t(L.reportLimit)), findsOneWidget);
    });
  });

  group('saved', () {
    testWidgets('saved posts are listed with their type', (tester) async {
      final w = TestWorld();
      await w.settings.setSaved(fixtureSummary('ssc-chsl-2026-admit-card'), true);
      await w.settings.setSaved(fixtureSummary('ssc-cgl-2026-notice'), true);
      await pumpApp(tester, world: w);
      await openTab(tester, L.navSaved);
      expect(find.text(_cgl), findsOneWidget);
      expect(find.text('SSC CHSL 2026 Tier 1 Admit Card'), findsOneWidget);
      expect(find.text(t(L.savedEmpty)), findsNothing);
    });

    testWidgets('swipe removes, undo brings it back with its reminder', (tester) async {
      final w = TestWorld();
      final p = fixtureSummary('ssc-cgl-2026-notice');
      await pumpApp(tester, world: w);
      await w.controller.setReminder(p, true);
      await openTab(tester, L.navSaved);
      await tester.drag(find.byType(Dismissible), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(w.settings.saved, isEmpty);
      expect(w.notifications.scheduled, isEmpty);
      expect(find.text(t(L.removed)), findsOneWidget);
      await tester.tap(find.text(t(L.undo)));
      await tester.pumpAndSettle();
      expect(w.settings.isSaved(p.id), isTrue);
      expect(w.settings.hasReminder(p.id), isTrue);
      expect(w.notifications.scheduled.length, 2);
    });

    testWidgets('tapping a saved post opens it', (tester) async {
      final w = TestWorld();
      await w.settings.setSaved(fixtureSummary('up-police-constable-2026'), true);
      await pumpApp(tester, world: w);
      await openTab(tester, L.navSaved);
      await tester.tap(find.text('UP Police Constable 2026'));
      await tester.pumpAndSettle();
      expect(find.byType(DetailScreen), findsOneWidget);
    });

    testWidgets('saved posts show even when offline with no cache', (tester) async {
      final w = TestWorld()..fetcher.offline = true;
      await w.settings.setSaved(fixtureSummary('ssc-cgl-2026-notice'), true);
      await pumpApp(tester, world: w);
      await openTab(tester, L.navSaved);
      expect(find.text(_cgl), findsOneWidget);
    });
  });

  group('calendar', () {
    testWidgets('lists upcoming dates by month', (tester) async {
      await pumpApp(tester);
      await openTab(tester, L.navCalendar);
      expect(find.text(t(L.calendarTitle)), findsOneWidget);
      expect(find.text(en.monthYear(2026, 10)), findsOneWidget);
      expect(find.text(t(L.calendarEmpty)), findsNothing);
    });

    testWidgets('empty when there is nothing to show', (tester) async {
      final w = TestWorld()..fetcher.offline = true;
      await pumpApp(tester, world: w);
      await openTab(tester, L.navCalendar);
      expect(find.text(t(L.calendarEmpty)), findsOneWidget);
    });

    testWidgets('saved-only shows just saved posts', (tester) async {
      final w = TestWorld();
      await w.settings.setSaved(fixtureSummary('up-police-constable-2026'), true);
      await pumpApp(tester, world: w);
      await openTab(tester, L.navCalendar);
      await tester.tap(find.widgetWithText(ChoiceChip, t(L.navSaved)));
      await tester.pumpAndSettle();
      expect(find.text('UP Police Constable 2026'), findsWidgets);
      expect(find.text('RRB NTPC Graduate Level 2026'), findsNothing);
    });

    testWidgets('saved-only with nothing saved is empty', (tester) async {
      await pumpApp(tester);
      await openTab(tester, L.navCalendar);
      await tester.tap(find.widgetWithText(ChoiceChip, t(L.navSaved)));
      await tester.pumpAndSettle();
      expect(find.text(t(L.calendarEmpty)), findsOneWidget);
    });

    testWidgets('tapping an event opens the post', (tester) async {
      await pumpApp(tester);
      await openTab(tester, L.navCalendar);
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      expect(find.byType(DetailScreen), findsOneWidget);
    });
  });

  group('settings', () {
    Future<void> openSettings(WidgetTester tester) async {
      await openTab(tester, L.navMore);
      await tester.tap(find.widgetWithText(ListTile, t(L.settings)));
      await tester.pumpAndSettle();
    }

    testWidgets('switching to Hindi changes the whole app', (tester) async {
      final w = await pumpApp(tester);
      await openSettings(tester);
      await tester.tap(find.text('हिंदी'));
      await tester.pumpAndSettle();
      expect(w.settings.lang, AppLang.hi);
      expect(find.text(S.hi.t(L.settings)), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text(S.hi.t(L.navJobs)), findsOneWidget);
    });

    testWidgets('dark theme is applied', (tester) async {
      final w = await pumpApp(tester);
      await openSettings(tester);
      await tester.tap(find.text(t(L.themeDark)));
      await tester.pumpAndSettle();
      expect(w.settings.theme, ThemeChoice.dark);
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.dark);
      expect(Theme.of(tester.element(find.byType(ListView).first)).brightness, Brightness.dark);
    });

    testWidgets('turning alerts off stops background checks', (tester) async {
      final w = await pumpApp(tester);
      await openSettings(tester);
      await tester.tap(find.widgetWithText(SwitchListTile, t(L.alertsOn)));
      await tester.pumpAndSettle();
      expect(w.settings.alertPrefs.enabled, isFalse);
      expect(w.background.enabled, isFalse);
      expect(find.text(t(L.alertTypes)), findsNothing);
    });

    testWidgets('alert types can be picked', (tester) async {
      final w = await pumpApp(tester);
      await openSettings(tester);
      await tester.tap(find.widgetWithText(FilterChip, en.postType(PostType.result)));
      await tester.pumpAndSettle();
      expect(w.settings.alertPrefs.types, {PostType.job, PostType.result});
    });

    testWidgets('alert categories can be picked', (tester) async {
      final w = await pumpApp(tester);
      await openSettings(tester);
      await tester.scrollUntilVisible(find.widgetWithText(FilterChip, en.category(JobCategory.banking)), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.widgetWithText(FilterChip, en.category(JobCategory.banking)));
      await tester.pumpAndSettle();
      expect(w.settings.alertPrefs.categories, {JobCategory.banking});
    });

    testWidgets('blocked notifications are pointed out', (tester) async {
      final w = TestWorld();
      w.notifications.granted = false;
      await pumpApp(tester, world: w);
      await openSettings(tester);
      expect(find.text(t(L.notificationsBlocked)), findsOneWidget);
    });

    testWidgets('clear cache confirms', (tester) async {
      await pumpApp(tester);
      await openSettings(tester);
      await tester.scrollUntilVisible(find.text(t(L.clearCache)), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text(t(L.clearCache)));
      await tester.pumpAndSettle();
      expect(find.text(t(L.cacheCleared)), findsOneWidget);
    });

    testWidgets('shows the version and reminder time', (tester) async {
      await pumpApp(tester);
      await openSettings(tester);
      await tester.scrollUntilVisible(find.text(t(L.version, {'v': '1.0.0'})), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text(t(L.version, {'v': '1.0.0'})), findsOneWidget);
      expect(find.textContaining('09:00'), findsOneWidget);
    });
  });

  group('onboarding', () {
    testWidgets('first run shows the language picker in both languages', (tester) async {
      await pumpApp(tester, world: TestWorld(onboarded: false), start: false);
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingFlow), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('हिंदी'), findsOneWidget);
      expect(find.textContaining(S.hi.t(L.chooseLanguage)), findsOneWidget);
    });

    testWidgets('Skip goes straight to the app', (tester) async {
      final w = TestWorld(onboarded: false);
      await pumpApp(tester, world: w);
      await tester.tap(find.text(t(L.skip)));
      await tester.pumpAndSettle();
      expect(w.settings.onboarded, isTrue);
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('picking Hindi switches the flow', (tester) async {
      final w = TestWorld(onboarded: false);
      await pumpApp(tester, world: w);
      await tester.tap(find.text('हिंदी'));
      await tester.pumpAndSettle();
      expect(w.settings.lang, AppLang.hi);
      expect(find.text(S.hi.t(L.skip)), findsOneWidget);
    });

    testWidgets('three steps, then the permission rationale', (tester) async {
      final w = TestWorld(onboarded: false);
      w.notifications.granted = false;
      await pumpApp(tester, world: w);
      await tester.tap(find.text(t(L.continueLabel)));
      await tester.pumpAndSettle();
      expect(find.text(t(L.onbInterestsTitle)), findsOneWidget);
      await tester.tap(find.widgetWithText(FilterChip, en.category(JobCategory.railway)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t(L.continueLabel)));
      await tester.pumpAndSettle();
      expect(find.text(t(L.onbDetailsTitle)), findsOneWidget);
      await tester.tap(find.text(t(L.done)));
      await tester.pumpAndSettle();
      expect(find.text(t(L.notifRationaleTitle)), findsOneWidget);
      await tester.tap(find.text(t(L.allow)));
      await tester.pumpAndSettle();
      expect(w.settings.onboarded, isTrue);
      expect(w.settings.alertPrefs.enabled, isTrue);
      expect(w.settings.alertPrefs.categories, {JobCategory.railway});
      expect(w.background.enabled, isTrue);
    });

    testWidgets('declining notifications turns alerts off', (tester) async {
      final w = TestWorld(onboarded: false);
      w.notifications.granted = false;
      await pumpApp(tester, world: w);
      await tester.tap(find.text(t(L.continueLabel)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t(L.continueLabel)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t(L.done)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t(L.notNow)));
      await tester.pumpAndSettle();
      expect(w.settings.onboarded, isTrue);
      expect(w.settings.alertPrefs.enabled, isFalse);
      expect(w.background.enabled, isFalse);
    });

    testWidgets('back button returns to the previous step', (tester) async {
      await pumpApp(tester, world: TestWorld(onboarded: false), start: false);
      await tester.tap(find.text(t(L.continueLabel)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(t(L.back)));
      await tester.pumpAndSettle();
      expect(find.text('हिंदी'), findsOneWidget);
    });
  });

  group('my details', () {
    Future<void> openProfile(WidgetTester tester) async {
      await openTab(tester, L.navMore);
      await tester.tap(find.text(t(L.myDetails)));
      await tester.pumpAndSettle();
    }

    testWidgets('category chip is saved at once', (tester) async {
      final w = await pumpApp(tester);
      await openProfile(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, en.socialCategory(SocialCategory.obc)));
      await tester.pumpAndSettle();
      expect(w.settings.profile.category, SocialCategory.obc);
    });

    testWidgets('PwBD switch is saved', (tester) async {
      final w = await pumpApp(tester);
      await openProfile(tester);
      await tester.tap(find.widgetWithText(SwitchListTile, t(L.pwbd)));
      await tester.pumpAndSettle();
      expect(w.settings.profile.pwbd, isTrue);
    });

    testWidgets('ex-serviceman shows the note', (tester) async {
      final w = await pumpApp(tester);
      await openProfile(tester);
      await tester.tap(find.widgetWithText(SwitchListTile, t(L.exServiceman)));
      await tester.pumpAndSettle();
      expect(w.settings.profile.exServiceman, isTrue);
      expect(find.text(t(L.exServicemanNote)), findsOneWidget);
    });

    testWidgets('date of birth from the picker', (tester) async {
      final w = await pumpApp(tester);
      await openProfile(tester);
      await tester.tap(find.text(t(L.dateOfBirth)));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(w.settings.profile.dob, isNotNull);
    });

    testWidgets('clear details empties the profile', (tester) async {
      final w = TestWorld();
      await w.settings.setProfile(UserProfile(dob: Ymd(2000, 1, 1), state: 'UP'));
      await pumpApp(tester, world: w);
      await openProfile(tester);
      expect(find.text('01 Jan 2000'), findsOneWidget);
      await tester.scrollUntilVisible(find.text(t(L.clearDetails)), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text(t(L.clearDetails)));
      await tester.pumpAndSettle();
      expect(w.settings.profile.isEmpty, isTrue);
    });

    testWidgets('More shows the saved qualification', (tester) async {
      final w = TestWorld();
      await w.settings.setProfile(const UserProfile(qualification: Qualification.class12));
      await pumpApp(tester, world: w);
      await openTab(tester, L.navMore);
      expect(find.text(en.qualification(Qualification.class12)), findsOneWidget);
    });
  });

  group('age calculator', () {
    testWidgets('uses the saved date of birth', (tester) async {
      final w = TestWorld();
      await w.settings.setProfile(UserProfile(dob: Ymd(2000, 5, 17)));
      await pumpScreen(tester, const AgeCalculatorScreen(), world: w);
      expect(find.byType(AgeResultCard), findsOneWidget);
      expect(find.text('26'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
      expect(find.bySemanticsLabel(t(L.ageResult, {'y': 26, 'm': 4, 'd': 20})), findsOneWidget);
    });

    testWidgets('a custom "age on" date', (tester) async {
      final w = TestWorld();
      await w.settings.setProfile(UserProfile(dob: Ymd(2000, 5, 17)));
      await pumpScreen(tester, AgeCalculatorScreen(initialOn: Ymd(2027, 1, 1)), world: w);
      expect(find.text(t(L.totalMonths, {'n': 319})), findsOneWidget);
    });

    testWidgets('without a date of birth nothing is calculated', (tester) async {
      await pumpScreen(tester, const AgeCalculatorScreen());
      expect(find.byType(AgeResultCard), findsNothing);
      expect(find.text(t(L.ageCalcIntro)), findsOneWidget);
    });

    testWidgets('birth after the "age on" date is flagged', (tester) async {
      final w = TestWorld();
      await w.settings.setProfile(UserProfile(dob: Ymd(2000, 5, 17)));
      await pumpScreen(tester, AgeCalculatorScreen(initialOn: Ymd(1999, 1, 1)), world: w);
      expect(find.text(t(L.ageInvalid)), findsOneWidget);
    });
  });

  group('disclaimer', () {
    testWidgets('says it is not affiliated and lists sources', (tester) async {
      await pumpScreen(tester, const DisclaimerScreen());
      expect(find.text(t(L.disclaimerNotAffiliated)), findsOneWidget);
      await tester.scrollUntilVisible(find.text(t(L.sourcesTitle)), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text(t(L.sourcesTitle)), findsOneWidget);
    });

    testWidgets('every source is a government or exam-body https site', (tester) async {
      for (final (name, url) in officialSources) {
        expect(name, isNotEmpty);
        expect(url, startsWith('https://'));
      }
    });

    testWidgets('tapping a source opens it', (tester) async {
      final w = await pumpScreen(tester, const DisclaimerScreen());
      await tester.scrollUntilVisible(find.text(officialSources.first.$1), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text(officialSources.first.$1));
      await tester.pumpAndSettle();
      expect(w.actions.opened.single, officialSources.first.$2);
    });
  });

  group('accessibility and themes', () {
    for (final lang in AppLang.values) {
      testWidgets('home at 1.3x text, ${lang.name}', (tester) async {
        await pumpApp(tester, world: TestWorld(prefs: {'lang': lang.name}), textScale: 1.3, size: const Size(360, 740));
        expect(tester.takeException(), isNull);
        expect(find.byType(PostCard), findsWidgets);
      });

      testWidgets('detail at 1.3x text, ${lang.name}', (tester) async {
        final w = TestWorld(prefs: {'lang': lang.name});
        await w.settings.setProfile(UserProfile(dob: Ymd(2001, 3, 10), qualification: Qualification.graduate));
        await pumpApp(tester, world: w, textScale: 1.3, size: const Size(360, 740));
        await tester.tap(find.byType(PostCard).first);
        await tester.pumpAndSettle();
        await tester.fling(_detailList, const Offset(0, -3000), 3000);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('more, saved and calendar at 1.3x, ${lang.name}', (tester) async {
        final w = TestWorld(prefs: {'lang': lang.name});
        await w.settings.setSaved(fixtureSummary('ssc-cgl-2026-notice'), true);
        await pumpApp(tester, world: w, textScale: 1.3, size: const Size(360, 740));
        final s = S.of(lang);
        for (final key in [L.navCalendar, L.navSaved, L.navMore]) {
          await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(s.t(key))));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });

      testWidgets('settings at 1.3x, ${lang.name}', (tester) async {
        await pumpApp(tester, world: TestWorld(prefs: {'lang': lang.name}), textScale: 1.3, size: const Size(360, 740));
        final s = S.of(lang);
        await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(s.t(L.navMore))));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ListTile, s.t(L.settings)));
        await tester.pumpAndSettle();
        await tester.fling(find.byType(Scrollable).first, const Offset(0, -3000), 3000);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('onboarding at 1.3x, ${lang.name}', (tester) async {
        final w = TestWorld(onboarded: false, prefs: {'lang': lang.name});
        await pumpApp(tester, world: w, start: false, textScale: 1.3, size: const Size(360, 740));
        final s = S.of(lang);
        for (var i = 0; i < 2; i++) {
          await tester.tap(find.text(s.t(L.continueLabel)));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });

      testWidgets('error state at 1.3x, ${lang.name}', (tester) async {
        final w = TestWorld(prefs: {'lang': lang.name})..fetcher.offline = true;
        await pumpApp(tester, world: w, textScale: 1.3, size: const Size(360, 740));
        expect(tester.takeException(), isNull);
        expect(find.text(S.of(lang).t(L.loadErrorTitle)), findsOneWidget);
      });
    }

    testWidgets('dark theme renders home and detail', (tester) async {
      final w = TestWorld(prefs: {'theme': 'dark'});
      await pumpApp(tester, world: w);
      expect(Theme.of(tester.element(find.byType(PostCard).first)).brightness, Brightness.dark);
      await openCgl(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('status colours exist in both themes', (tester) async {
      for (final b in Brightness.values) {
        final theme = vacancyTheme(b);
        expect(theme.extension<StatusColors>(), isNotNull);
        expect(theme.useMaterial3, isTrue);
      }
    });

    testWidgets('tap targets are big enough on home', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('tap targets are labelled on home', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('tap targets are labelled on detail', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      await openCgl(tester);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  });

  group('hindi', () {
    testWidgets('home in Hindi', (tester) async {
      await pumpApp(tester, world: TestWorld(prefs: {'lang': 'hi'}));
      expect(find.text('एसएससी सीजीएल 2026 भर्ती'), findsOneWidget);
      expect(find.text(S.hi.postType(PostType.admitCard)), findsOneWidget);
    });

    testWidgets('detail in Hindi', (tester) async {
      await pumpApp(tester, world: TestWorld(prefs: {'lang': 'hi'}));
      await tester.tap(find.text('एसएससी सीजीएल 2026 भर्ती'));
      await tester.pumpAndSettle();
      expect(find.text(S.hi.t(L.remindMe)), findsOneWidget);
      await scrollTo(tester, find.text(S.hi.t(L.importantDates)));
      expect(find.text(S.hi.t(L.importantDates)), findsOneWidget);
    });

    testWidgets('error state in Hindi', (tester) async {
      final w = TestWorld(prefs: {'lang': 'hi'})..fetcher.offline = true;
      await pumpApp(tester, world: w);
      expect(find.text(S.hi.t(L.errorOffline)), findsOneWidget);
      expect(find.text(S.hi.t(L.retry)), findsOneWidget);
    });
  });
}
