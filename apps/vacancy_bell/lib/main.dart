import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'config.dart';
import 'data/feed_fetcher.dart';
import 'data/jobs_repository.dart';
import 'data/kv_store.dart';
import 'data/report_backend.dart';
import 'data/settings.dart';
import 'logic/report.dart';
import 'services/background.dart';
import 'services/notifications.dart';
import 'services/platform_actions.dart';
import 'state/app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await PrefsStore.open();
  final settings = AppSettings(store);
  final repo = JobsRepository(
    fetcher: HttpFeedFetcher(AppConfig.feedBaseUrl),
    cache: await openFeedCache(),
    keep: () => settings.savedIds,
  );
  final notifications = LocalNotificationGateway();
  final controller = AppController(AppServices(
    repo: repo,
    settings: settings,
    notifications: notifications,
    background: WorkmanagerScheduler(),
    reports: ReportService(FirebaseReportBackend(), ReportLimiter(store)),
    actions: const RealPlatformActions(),
  ));
  final navigatorKey = GlobalKey<NavigatorState>();

  runApp(VacancyBellApp(controller: controller, navigatorKey: navigatorKey));

  // Everything below runs after the first frame so the app opens instantly.
  await notifications.init(
    lang: settings.lang,
    onTap: (id) => openPostFromNotification(navigatorKey, id),
  );
  final launchedFor = await notifications.launchPayload();
  if (launchedFor != null) {
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => openPostFromNotification(navigatorKey, launchedFor));
  }
  controller.start();
  controller.syncBackground();
  // The first release has no ads (see AppConfig.adsEnabled).
  if (AppConfig.adsEnabled) {
    AdService.instance.init(AdConfig.fromEnvironment());
  }
}
