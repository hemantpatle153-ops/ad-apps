import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roz_quiz/app/app.dart';
import 'package:roz_quiz/app/controller.dart';
import 'package:roz_quiz/core/bi.dart';
import 'package:roz_quiz/core/models.dart';
import 'package:roz_quiz/core/report.dart';
import 'package:roz_quiz/core/selection.dart';
import 'package:roz_quiz/data/cache_store.dart';
import 'package:roz_quiz/data/feed_client.dart';
import 'package:roz_quiz/data/repository.dart';
import 'package:roz_quiz/data/user_store.dart';
import 'package:roz_quiz/services/reminders.dart';
import 'package:roz_quiz/ui/scope.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();
Object? fixtureJson(String name) => jsonDecode(fixture(name));

/// Feed files served from a map; anything else is 404, or offline when
/// [offline] is set.
class FakeFeedClient implements FeedClient {
  FakeFeedClient([Map<String, String>? files]) : files = {...?files};
  final Map<String, String> files;
  final List<String> requests = [];
  bool offline = false;
  final Map<String, FeedErrorKind> errors = {};

  @override
  Future<String> get(String path) async {
    requests.add(path);
    if (offline) throw const FeedException(FeedErrorKind.offline);
    final e = errors[path];
    if (e != null) throw FeedException(e);
    final f = files[path];
    if (f == null) throw const FeedException(FeedErrorKind.notFound);
    return f;
  }
}

/// The real bundled bank, read from the assets folder.
class FileBundleLoader implements BundleLoader {
  @override
  Future<String> load(String assetPath) => File(assetPath).readAsString();
}

class MapBundleLoader implements BundleLoader {
  MapBundleLoader(this.files);
  final Map<String, String> files;

  @override
  Future<String> load(String assetPath) async {
    final f = files[assetPath];
    if (f == null) throw StateError('no asset $assetPath');
    return f;
  }
}

class FakeReportSink implements ReportSink {
  final List<ReportPayload> sent = [];
  bool fail = false;
  int signIns = 0;

  @override
  Future<String> signIn() async {
    signIns++;
    if (fail) throw const SocketException('offline');
    return 'uid-test';
  }

  @override
  Future<void> send(ReportPayload payload) async {
    if (fail) throw const SocketException('offline');
    sent.add(payload);
  }
}

/// A full feed for 2026-10-07 built from the fixtures.
Map<String, String> fixtureFeed() => {
      'quiz/index.json': fixture('index.json'),
      'quiz/daily/2026-10-07.json': fixture('daily_2026-10-07.json'),
      'quiz/current_affairs/2026-10-07.json': fixture('current_affairs_2026-10-07.json'),
      'quiz/banks/polity.json': fixture('bank_polity.json'),
    };

/// 2026-10-07 10:00 IST.
final kNow = DateTime.utc(2026, 10, 7, 4, 30);

class Harness {
  Harness({
    DateTime? now,
    Map<String, String>? feed,
    bool offline = false,
    bool onboarded = true,
    Lang lang = Lang.en,
    KeyValueStore? kv,
    int timer = 0,
    bool permission = true,
  })  : now = now ?? kNow,
        client = FakeFeedClient(feed ?? fixtureFeed())..offline = offline,
        kv = kv ?? MemoryKeyValueStore() {
    final store = UserStore(this.kv);
    store.settings
      ..onboarded = onboarded
      ..lang = lang
      ..timerSeconds = timer
      ..sound = false
      ..haptics = false;
    reminders = FakeReminderScheduler(granted: permission);
    controller = AppController(
      store: store,
      repo: QuizRepository(client: client, cache: cache, bundle: FileBundleLoader()),
      reminders: reminders,
      reportSink: reports,
      clock: () => this.now,
      random: () => SeededRandom(42),
    );
  }

  DateTime now;
  final FakeFeedClient client;
  final KeyValueStore kv;
  final cache = MemoryCacheStore();
  final reports = FakeReportSink();
  late final FakeReminderScheduler reminders;
  late final AppController controller;
}

/// Pumps the whole app (after start()) on a phone-sized screen.
Future<void> pumpApp(WidgetTester tester, Harness h,
    {double textScale = 1.0, Size size = const Size(400, 860)}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  Hooks.share = (text) async => sharedTexts.add(text);
  await tester.runAsync(() => h.controller.start());
  await tester.pumpWidget(RozQuizApp(controller: h.controller));
  await tester.pumpAndSettle();
}

/// Pumps one screen inside the app's scope and theme.
Future<void> pumpScreen(WidgetTester tester, Harness h, Widget screen,
    {double textScale = 1.0, Size size = const Size(400, 860)}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  Hooks.share = (text) async => sharedTexts.add(text);
  await tester.pumpWidget(AppScope(
    controller: h.controller,
    child: MaterialApp(
      theme: ThemeData(useMaterial3: true),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
            data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: kMaxTextScale)),
            child: child!);
      },
      home: screen,
    ),
  ));
  await tester.pump();
}

final List<String> sharedTexts = [];

int _seq = 0;

/// A valid question for tests.
Question makeQ({
  String? id,
  String subject = 'gk',
  int answer = 0,
  List<String> exams = const ['ssc'],
  Difficulty difficulty = Difficulty.medium,
  String? asked,
  String? text,
}) {
  final n = _seq++;
  final qid = id ?? 'q-test-$n';
  return Question(
    id: qid,
    q: Bi(text ?? 'Question $qid?', 'प्रश्न $qid?'),
    options: [for (var i = 0; i < 4; i++) Bi('Option $i of $qid', 'विकल्प $i $qid')],
    answer: answer,
    explanation: Bi('Because $qid.', 'क्योंकि $qid।'),
    subject: subject,
    exams: exams,
    difficulty: difficulty,
    asked: asked,
  );
}

/// JSON of a valid question, to break in parsing tests.
Map<String, Object?> questionJson({String id = 'q-gk-1', int answer = 1}) => {
      'id': id,
      'q': {'en': 'What?', 'hi': 'क्या?'},
      'options': <Object?>[
        {'en': 'A', 'hi': 'क'},
        {'en': 'B', 'hi': 'ख'},
        {'en': 'C', 'hi': 'ग'},
        {'en': 'D', 'hi': 'घ'},
      ],
      'answer': answer,
      'explanation': {'en': 'Because.', 'hi': 'क्योंकि।'},
      'subject': 'gk',
      'exams': ['ssc'],
      'difficulty': 'easy',
      'source': {'name': 'PIB', 'url': 'https://pib.gov.in/x'},
      'asked': null,
      'verified': true,
    };
