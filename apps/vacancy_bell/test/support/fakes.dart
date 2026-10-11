import 'dart:io';

import 'package:vacancy_bell/core/json_read.dart';
import 'package:vacancy_bell/data/feed_cache.dart';
import 'package:vacancy_bell/data/feed_fetcher.dart';
import 'package:vacancy_bell/data/jobs_repository.dart';
import 'package:vacancy_bell/data/kv_store.dart';
import 'package:vacancy_bell/data/settings.dart';
import 'package:vacancy_bell/logic/alerts.dart';
import 'package:vacancy_bell/logic/reminder_plan.dart';
import 'package:vacancy_bell/logic/report.dart';
import 'package:vacancy_bell/models/feed_index.dart';
import 'package:vacancy_bell/models/post.dart';
import 'package:vacancy_bell/services/background.dart';
import 'package:vacancy_bell/services/notifications.dart';
import 'package:vacancy_bell/services/platform_actions.dart';
import 'package:vacancy_bell/state/app_controller.dart';

/// 2026-10-07 17:30 IST, the "now" every fixture is written against.
final fixtureNow = DateTime.utc(2026, 10, 7, 12, 0);

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

String get indexJson => fixture('jobs_index.json');

FeedIndex get fixtureIndex => FeedIndex.parse(indexJson);

PostDetail fixturePost(String id) => parsePostDetail(fixture('posts/$id.json'));

PostSummary fixtureSummary(String id) => fixtureIndex.byId(id)!;

/// Answers feed paths from a map; tracks the requests it saw.
class FakeFetcher implements FeedFetcher {
  FakeFetcher([Map<String, String>? files]) : files = {...?files};

  final Map<String, String> files;

  /// path -> ETag returned with the file.
  final Map<String, String> etags = {};

  /// Answer every request with this status (e.g. 500), when set.
  int? forceStatus;
  bool offline = false;
  final List<(String, String?)> requests = [];

  /// Delay before answering (to test loading states).
  Duration delay = Duration.zero;

  @override
  Future<FetchResponse> get(String path, {String? etag}) async {
    requests.add((path, etag));
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (offline) throw const FeedNetworkException('offline');
    if (forceStatus != null) return FetchResponse(forceStatus!);
    final body = files[path];
    if (body == null) return const FetchResponse(404);
    final tag = etags[path];
    if (tag != null && etag == tag) return FetchResponse(304, etag: tag);
    return FetchResponse(200, body: body, etag: tag);
  }
}

FakeFetcher fixtureFetcher({bool withPosts = true}) {
  final f = FakeFetcher({indexPath: indexJson});
  if (withPosts) {
    for (final id in ['ssc-cgl-2026-notice', 'up-police-constable-2026', 'rrb-ntpc-graduate-2026']) {
      f.files[postPath(id)] = fixture('posts/$id.json');
    }
  }
  return f;
}

class FakeNotifications implements NotificationGateway {
  bool granted = true;
  bool grantOnRequest = true;
  int permissionRequests = 0;
  final Map<int, (PlannedReminder, String, String)> scheduled = {};
  final List<AlertMessage> shown = [];
  String? launch;

  @override
  Future<void> init({void Function(String? payload)? onTap, AppLang lang = AppLang.en}) async {}

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    granted = grantOnRequest;
    return granted;
  }

  @override
  Future<bool> permissionGranted() async => granted;

  @override
  Future<void> schedule(PlannedReminder r, {required String title, required String body}) async {
    scheduled[r.id] = (r, title, body);
  }

  @override
  Future<void> show(AlertMessage m) async => shown.add(m);

  @override
  Future<List<int>> pendingIds() async => scheduled.keys.toList();

  @override
  Future<void> cancel(int id) async => scheduled.remove(id);

  @override
  Future<String?> launchPayload() async => launch;
}

class FakeBackground implements BackgroundScheduler {
  bool? enabled;
  @override
  Future<void> init() async {}
  @override
  Future<void> enable() async => enabled = true;
  @override
  Future<void> disable() async => enabled = false;
}

class FakeActions implements PlatformActions {
  final List<String> opened = [];
  final List<String> shared = [];
  bool openResult = true;

  @override
  Future<bool> openUrl(String url) async {
    opened.add(url);
    return openResult;
  }

  @override
  Future<void> shareText(String text, {String? subject}) async => shared.add(text);
}

class FakeReportBackend implements ReportBackend {
  final List<ReportDraft> sent = [];
  bool fail = false;

  @override
  Future<void> send(ReportDraft draft) async {
    if (fail) throw const SocketException('offline');
    sent.add(draft);
  }
}

/// A full set of fakes around the fixtures.
class TestWorld {
  TestWorld({
    FakeFetcher? fetcher,
    Map<String, String>? prefs,
    DateTime? now,
    bool onboarded = true,
  })  : fetcher = fetcher ?? fixtureFetcher(),
        store = MemoryStore({
          if (onboarded) 'onboarded': 'true',
          if (onboarded) 'lang': 'en',
          ...?prefs,
        }),
        now = now ?? fixtureNow {
    settings = AppSettings(store);
    repo = JobsRepository(fetcher: this.fetcher, cache: cache, clock: () => this.now, keep: () => settings.savedIds);
    reports = ReportService(reportBackend, ReportLimiter(store, clock: () => this.now));
    controller = AppController(AppServices(
      repo: repo,
      settings: settings,
      notifications: notifications,
      background: background,
      reports: reports,
      actions: actions,
      clock: () => this.now,
    ));
  }

  final FakeFetcher fetcher;
  final MemoryStore store;
  final cache = MemoryFeedCache();
  final notifications = FakeNotifications();
  final background = FakeBackground();
  final actions = FakeActions();
  final reportBackend = FakeReportBackend();
  DateTime now;
  late final AppSettings settings;
  late final JobsRepository repo;
  late final ReportService reports;
  late final AppController controller;
}
