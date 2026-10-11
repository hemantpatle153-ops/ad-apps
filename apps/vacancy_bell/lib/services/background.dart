import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import '../config.dart';
import '../data/feed_cache.dart';
import '../data/feed_fetcher.dart';
import '../data/jobs_repository.dart';
import '../data/kv_store.dart';
import '../data/settings.dart';
import 'notifications.dart';
import 'sync.dart';

const alertTaskName = 'newPosts';
const alertTaskUniqueName = 'vacancy-bell-new-posts';
const alertCheckEvery = Duration(hours: 3);

/// Turns the periodic new-post check on and off. Behind an interface so
/// tests don't need the platform plugin.
abstract class BackgroundScheduler {
  Future<void> init();
  Future<void> enable();
  Future<void> disable();
}

class WorkmanagerScheduler implements BackgroundScheduler {
  bool _ready = false;

  @override
  Future<void> init() async {
    if (_ready) return;
    await Workmanager().initialize(backgroundDispatcher);
    _ready = true;
  }

  @override
  Future<void> enable() async {
    await init();
    await Workmanager().registerPeriodicTask(
      alertTaskUniqueName,
      alertTaskName,
      frequency: alertCheckEvery,
      flexInterval: const Duration(minutes: 45),
      initialDelay: const Duration(minutes: 20),
      constraints: Constraints(networkType: NetworkType.connected, requiresBatteryNotLow: true),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }

  @override
  Future<void> disable() async {
    await init();
    await Workmanager().cancelByUniqueName(alertTaskUniqueName);
  }
}

/// Where the offline copies live (shared with the background check).
Future<FileFeedCache> openFeedCache() async {
  final dir = await getApplicationSupportDirectory();
  return FileFeedCache(Directory('${dir.path}/feed'));
}

/// Entry point of the background isolate.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      final settings = AppSettings(await PrefsStore.open());
      final notifications = LocalNotificationGateway();
      await notifications.init(lang: settings.lang);
      final repo = JobsRepository(
        fetcher: HttpFeedFetcher(AppConfig.feedBaseUrl),
        cache: await openFeedCache(),
        keep: () => settings.savedIds,
      );
      await runAlertCheck(
        repo: repo,
        settings: settings,
        notifications: notifications,
        now: DateTime.now().toUtc(),
      );
      return true;
    } catch (e) {
      debugPrint('Alert check failed: $e');
      // Let WorkManager retry later.
      return false;
    }
  });
}
