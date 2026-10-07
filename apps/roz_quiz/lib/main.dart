import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/controller.dart';
import 'config.dart';
import 'data/cache_store.dart';
import 'data/feed_client.dart';
import 'data/repository.dart';
import 'data/user_store.dart';
import 'services/firebase_reports.dart';
import 'services/reminders.dart';

class AssetBundleLoader implements BundleLoader {
  @override
  Future<String> load(String assetPath) => rootBundle.loadString(assetPath);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final kv = await PrefsKeyValueStore.open();
  final support = await getApplicationSupportDirectory();
  final controller = AppController(
    store: UserStore(kv),
    repo: QuizRepository(
      client: HttpFeedClient(AppConfig.feedBaseUrl),
      cache: FileCacheStore(Directory('${support.path}/feed')),
      bundle: AssetBundleLoader(),
    ),
    reminders: LocalReminderScheduler(),
    reportSink: FirebaseReportSink(),
  );
  runApp(RozQuizApp(controller: controller));
  // Data loads after the first frame so the app opens instantly.
  controller.start();
  if (AppConfig.adsEnabled) AdService.instance.init(AdConfig.fromEnvironment());
}
