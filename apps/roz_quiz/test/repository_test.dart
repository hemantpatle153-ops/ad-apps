import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:roz_quiz/core/day.dart';
import 'package:roz_quiz/data/cache_store.dart';
import 'package:roz_quiz/data/feed_client.dart';
import 'package:roz_quiz/data/repository.dart';

import 'support/harness.dart';

final today = Day(2026, 10, 7);

class Rig {
  Rig({Map<String, String>? feed}) : client = FakeFeedClient(feed ?? fixtureFeed()) {
    repo = QuizRepository(client: client, cache: cache, bundle: FileBundleLoader(), clock: () => now);
  }
  DateTime now = kNow;
  final FakeFeedClient client;
  final cache = MemoryCacheStore();
  late final QuizRepository repo;
}

void main() {
  group('paths', () {
    test('daily and CA paths', () {
      expect(QuizRepository.dailyPath(today), 'quiz/daily/2026-10-07.json');
      expect(QuizRepository.caPath(today), 'quiz/current_affairs/2026-10-07.json');
      expect(QuizRepository.indexPath, 'quiz/index.json');
      expect(QuizRepository.bundledAsset('gk'), 'assets/bank/gk.json');
    });
  });

  group('Loaded', () {
    test('failed', () {
      const l = Loaded<int>.failed(FeedErrorKind.offline);
      expect(l.hasValue, isFalse);
      expect(l.offline, isTrue);
      expect(l.source, isNull);
    });
    test('value', () {
      const l = Loaded<int>(3, DataSource.network);
      expect(l.hasValue, isTrue);
      expect(l.offline, isFalse);
    });
  });

  group('bundled questions', () {
    test('loads all bundled subjects', () async {
      final qs = await Rig().repo.bundledQuestions();
      expect(qs.length, greaterThanOrEqualTo(150));
      expect(qs.map((q) => q.subject).toSet(), QuizRepository.bundledSubjects.toSet());
    });
    test('is memoised', () async {
      final r = Rig().repo;
      expect(identical(await r.bundledQuestions(), await r.bundledQuestions()), isTrue);
    });
    test('a broken asset is skipped, not fatal', () async {
      final repo = QuizRepository(
          client: FakeFeedClient(),
          cache: MemoryCacheStore(),
          bundle: MapBundleLoader({
            'assets/bank/gk.json': fixture('bank_polity.json'),
            'assets/bank/history.json': '{not json',
          }));
      final qs = await repo.bundledQuestions();
      expect(qs.length, 3);
    });
  });

  group('index', () {
    test('from the network, then saved', () async {
      final r = Rig();
      final l = await r.repo.index();
      expect(l.source, DataSource.network);
      expect(l.value!.daily.first, today);
      expect(l.value!.daily.length, 3);
      expect(l.value!.banks.map((b) => b.id), ['polity']);
      expect(r.cache.files.keys, contains('quiz/index.json'));
    });
    test('fresh saved copy is used without the network', () async {
      final r = Rig();
      await r.repo.index();
      r.client.requests.clear();
      r.now = r.now.add(const Duration(minutes: 59));
      final l = await r.repo.index();
      expect(l.source, DataSource.cache);
      expect(r.client.requests, isEmpty);
    });
    test('after an hour it is fetched again', () async {
      final r = Rig();
      await r.repo.index();
      r.client.requests.clear();
      r.now = r.now.add(const Duration(minutes: 61));
      final l = await r.repo.index();
      expect(l.source, DataSource.network);
      expect(r.client.requests, ['quiz/index.json']);
    });
    test('refresh skips the fresh copy', () async {
      final r = Rig();
      await r.repo.index();
      r.client.requests.clear();
      await r.repo.index(refresh: true);
      expect(r.client.requests, ['quiz/index.json']);
    });
    test('offline with a stale copy: copy plus error', () async {
      final r = Rig();
      await r.repo.index();
      r.now = r.now.add(const Duration(days: 3));
      r.client.offline = true;
      final l = await r.repo.index();
      expect(l.source, DataSource.cache);
      expect(l.error, FeedErrorKind.offline);
      expect(l.offline, isTrue);
      expect(l.savedAt, kNow);
    });
    test('offline without a copy', () async {
      final r = Rig()..client.offline = true;
      final l = await r.repo.index();
      expect(l.hasValue, isFalse);
      expect(l.error, FeedErrorKind.offline);
    });
    for (final kind in FeedErrorKind.values) {
      test('${kind.name} error is passed on', () async {
        final r = Rig()..client.errors['quiz/index.json'] = kind;
        expect((await r.repo.index()).error, kind);
      });
    }
    test('broken JSON is bad data and is not saved', () async {
      final r = Rig(feed: {'quiz/index.json': '{"daily": ['});
      final l = await r.repo.index();
      expect(l.error, FeedErrorKind.badData);
      expect(r.cache.files, isEmpty);
    });
    test('a broken new copy keeps the old one', () async {
      final r = Rig();
      await r.repo.index();
      r.client.files['quiz/index.json'] = '[]';
      final l = await r.repo.index(refresh: true);
      expect(l.source, DataSource.cache);
      expect(l.error, FeedErrorKind.badData);
      expect(r.cache.files['quiz/index.json']!.text, fixture('index.json'));
    });
    test('a corrupt saved copy is ignored', () async {
      final r = Rig();
      await r.cache.write('quiz/index.json', 'garbage', kNow);
      final l = await r.repo.index();
      expect(l.source, DataSource.network);
    });
    test('an unexpected exception counts as offline', () async {
      final repo = QuizRepository(
          client: _ThrowingClient(), cache: MemoryCacheStore(), bundle: FileBundleLoader());
      expect((await repo.index()).error, FeedErrorKind.offline);
    });
  });

  group('daily', () {
    test('from the network', () async {
      final r = Rig();
      final l = await r.repo.daily(today);
      expect(l.source, DataSource.network);
      expect(l.value!.questions.length, 10);
      expect(l.value!.date, today);
    });
    test('saved dailies are never re-fetched', () async {
      final r = Rig();
      await r.repo.daily(today);
      r.client.requests.clear();
      r.now = r.now.add(const Duration(days: 30));
      final l = await r.repo.daily(today);
      expect(l.source, DataSource.cache);
      expect(r.client.requests, isEmpty);
    });
    test('offline without a copy: bundled fallback', () async {
      final r = Rig()..client.offline = true;
      final l = await r.repo.daily(today);
      expect(l.source, DataSource.bundled);
      expect(l.value!.questions.length, 10);
      expect(l.error, FeedErrorKind.offline);
      expect(l.value!.questions.every((q) => q.id.startsWith('rq-')), isTrue);
    });
    test('not published yet: bundled fallback with notFound', () async {
      final r = Rig();
      final l = await r.repo.daily(today.addDays(1));
      expect(l.source, DataSource.bundled);
      expect(l.error, FeedErrorKind.notFound);
    });
    test('fallback is the same on every phone', () async {
      final a = await (Rig()..client.offline = true).repo.daily(today);
      final b = await (Rig()..client.offline = true).repo.daily(today);
      expect(a.value!.questions.map((q) => q.id), b.value!.questions.map((q) => q.id));
    });
    test('a file for the wrong date is rejected', () async {
      final r = Rig(feed: {'quiz/daily/2026-10-08.json': fixture('daily_2026-10-07.json')});
      final l = await r.repo.daily(today.addDays(1));
      expect(l.source, DataSource.bundled);
      expect(l.error, FeedErrorKind.badData);
    });
    test('malformed questions are dropped, the rest kept', () async {
      final r = Rig(feed: {'quiz/daily/2026-10-07.json': fixture('daily_malformed.json')});
      final l = await r.repo.daily(today);
      expect(l.source, DataSource.network);
      expect(l.value!.questions.map((q) => q.id), ['q-polity-000101', 'q-english-000110']);
    });
    test('no bank and no network: failed', () async {
      final repo = QuizRepository(
          client: FakeFeedClient()..offline = true,
          cache: MemoryCacheStore(),
          bundle: MapBundleLoader({}));
      final l = await repo.daily(today);
      expect(l.hasValue, isFalse);
      expect(l.error, FeedErrorKind.offline);
    });
  });

  group('current affairs', () {
    test('from the network', () async {
      final l = await Rig().repo.currentAffairs(today);
      expect(l.value!.notes.length, 3);
      expect(l.value!.questions.length, 2);
    });
    test("today's file is re-fetched after an hour", () async {
      final r = Rig();
      await r.repo.currentAffairs(today);
      r.client.requests.clear();
      r.now = r.now.add(const Duration(minutes: 30));
      await r.repo.currentAffairs(today);
      expect(r.client.requests, isEmpty);
      r.now = r.now.add(const Duration(minutes: 31));
      await r.repo.currentAffairs(today);
      expect(r.client.requests, [QuizRepository.caPath(today)]);
    });
    test("a past day's file is kept forever", () async {
      final r = Rig();
      await r.repo.currentAffairs(today);
      r.client.requests.clear();
      r.now = r.now.add(const Duration(days: 2));
      final l = await r.repo.currentAffairs(today);
      expect(l.source, DataSource.cache);
      expect(r.client.requests, isEmpty);
    });
    test('missing day', () async {
      final l = await Rig().repo.currentAffairs(today.addDays(-5));
      expect(l.hasValue, isFalse);
      expect(l.error, FeedErrorKind.notFound);
    });
  });

  group('downloadBanks', () {
    test('fetches banks listed in the index (and ignores unsafe paths)', () async {
      final r = Rig();
      expect(await r.repo.downloadBanks(), 1);
      expect(r.cache.files.keys, contains('quiz/banks/polity.json'));
      expect(r.client.requests.where((p) => p.contains('etc')), isEmpty);
    });
    test('up-to-date banks are skipped', () async {
      final r = Rig();
      await r.repo.downloadBanks();
      r.client.requests.clear();
      r.now = r.now.add(const Duration(hours: 2));
      expect(await r.repo.downloadBanks(), 0);
      expect(r.client.requests, ['quiz/index.json']);
    });
    test('a bank saved before its update is fetched again', () async {
      final r = Rig();
      await r.cache.write('quiz/banks/polity.json', fixture('bank_polity.json'), DateTime.utc(2026, 10, 1));
      expect(await r.repo.downloadBanks(), 1);
    });
    test('offline throws', () async {
      final r = Rig()..client.offline = true;
      await expectLater(r.repo.downloadBanks(),
          throwsA(isA<FeedException>().having((e) => e.kind, 'kind', FeedErrorKind.offline)));
    });
    test('offline with a saved index still throws', () async {
      final r = Rig();
      await r.repo.index();
      r.client.offline = true;
      await expectLater(r.repo.downloadBanks(), throwsA(isA<FeedException>()));
    });
    test('a missing bank file is not counted', () async {
      final r = Rig()..client.files.remove('quiz/banks/polity.json');
      expect(await r.repo.downloadBanks(), 0);
    });
  });

  group('pool', () {
    test('bundled only at first', () async {
      final r = Rig();
      final pool = await r.repo.pool();
      expect(pool.length, (await r.repo.bundledQuestions()).length);
    });
    test('adds downloaded banks, dailies and CA quizzes', () async {
      final r = Rig();
      final before = (await r.repo.pool()).length;
      await r.repo.daily(today);
      await r.repo.currentAffairs(today);
      await r.repo.downloadBanks();
      final pool = await r.repo.pool();
      expect(pool.length, before + 10 + 2 + 3);
      final ids = pool.map((q) => q.id).toSet();
      expect(ids, containsAll(['q-polity-000101', 'q-current_affairs-000201', 'q-polity-000303']));
    });
    test('is memoised until something new is saved', () async {
      final r = Rig();
      final a = await r.repo.pool();
      expect(identical(a, await r.repo.pool()), isTrue);
      await r.repo.daily(today);
      expect(identical(a, await r.repo.pool()), isFalse);
    });
    test('ids are unique', () async {
      final r = Rig();
      await r.repo.daily(today);
      await r.repo.downloadBanks();
      final pool = await r.repo.pool();
      expect(pool.map((q) => q.id).toSet().length, pool.length);
    });
    test('a downloaded copy replaces a bundled one with the same id', () async {
      final r = Rig();
      final bundled = (await r.repo.bundledQuestions()).first;
      final bank = {
        'schema': 1,
        'subject': bundled.subject,
        'questions': [
          {...questionJson(id: bundled.id), 'subject': bundled.subject, 'q': {'en': 'NEW', 'hi': 'नया'}}
        ],
      };
      await r.cache.write('quiz/banks/x.json', jsonEncode(bank), kNow);
      final pool = await r.repo.pool();
      expect(pool.firstWhere((q) => q.id == bundled.id).q.en, 'NEW');
    });
    test('unknown and corrupt saved files are ignored', () async {
      final r = Rig();
      await r.cache.write('quiz/banks/bad.json', 'nope', kNow);
      await r.cache.write('other/thing.json', '{}', kNow);
      expect((await r.repo.pool()).length, (await r.repo.bundledQuestions()).length);
    });
  });

  group('lastUpdated and clearCache', () {
    test('null when nothing was downloaded', () async {
      expect(await Rig().repo.lastUpdated(), isNull);
    });
    test('newest save time', () async {
      final r = Rig();
      await r.repo.index();
      r.now = r.now.add(const Duration(hours: 3));
      await r.repo.daily(today);
      expect(await r.repo.lastUpdated(), kNow.add(const Duration(hours: 3)));
    });
    test('clearCache forgets everything', () async {
      final r = Rig();
      await r.repo.daily(today);
      await r.repo.clearCache();
      expect(r.cache.files, isEmpty);
      expect(await r.repo.lastUpdated(), isNull);
      expect((await r.repo.pool()).length, (await r.repo.bundledQuestions()).length);
    });
  });

  group('FileCacheStore', () {
    late Directory tmp;
    late FileCacheStore store;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('roz_cache');
      store = FileCacheStore(Directory('${tmp.path}/feed'));
    });
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('missing file reads as null', () async {
      expect(await store.read('quiz/index.json'), isNull);
      expect(await store.paths(), isEmpty);
    });
    test('write then read', () async {
      final at = DateTime.utc(2026, 10, 7, 1, 2, 3);
      await store.write('quiz/daily/2026-10-07.json', '{"a":"हिंदी\nline"}', at);
      final f = await store.read('quiz/daily/2026-10-07.json');
      expect(f!.text, '{"a":"हिंदी\nline"}');
      expect(f.savedAt, at);
      expect(f.savedAt.isUtc, isTrue);
    });
    test('local times are stored as UTC', () async {
      final at = DateTime.utc(2026, 10, 7, 1);
      await store.write('a.json', 'x', at.toLocal());
      expect((await store.read('a.json'))!.savedAt, at);
    });
    test('overwrite', () async {
      await store.write('a.json', 'one', kNow);
      await store.write('a.json', 'two', kNow);
      expect((await store.read('a.json'))!.text, 'two');
    });
    test('paths lists what was written', () async {
      await store.write('quiz/index.json', '{}', kNow);
      await store.write('quiz/banks/gk.json', '{}', kNow);
      expect((await store.paths()).toSet(), {'quiz/index.json', 'quiz/banks/gk.json'});
    });
    test('no temp files are left behind', () async {
      await store.write('a.json', 'x', kNow);
      final names = store.dir.listSync().map((e) => e.uri.pathSegments.last);
      expect(names.where((n) => n.endsWith('.tmp')), isEmpty);
    });
    test('foreign and corrupt files are ignored', () async {
      await store.write('a.json', 'x', kNow);
      File('${store.dir.path}/readme.txt').writeAsStringSync('hi');
      File('${store.dir.path}/!!!.cache').writeAsStringSync('1\nx');
      expect(await store.paths(), ['a.json']);
    });
    test('a file without a header reads as null', () async {
      await store.write('a.json', 'x', kNow);
      final f = store.dir.listSync().whereType<File>().single;
      f.writeAsStringSync('no header');
      expect(await store.read('a.json'), isNull);
      f.writeAsStringSync('abc\nbody');
      expect(await store.read('a.json'), isNull);
    });
    test('clear removes everything', () async {
      await store.write('a.json', 'x', kNow);
      await store.clear();
      expect(await store.paths(), isEmpty);
      await store.clear();
    });
    test('works with the repository', () async {
      final repo = QuizRepository(client: FakeFeedClient(fixtureFeed()), cache: store, bundle: FileBundleLoader(), clock: () => kNow);
      await repo.daily(today);
      final again = QuizRepository(
          client: FakeFeedClient()..offline = true, cache: FileCacheStore(store.dir), bundle: FileBundleLoader(), clock: () => kNow);
      final l = await again.daily(today);
      expect(l.source, DataSource.cache);
      expect(l.value!.questions.length, 10);
    });
  });

  group('HttpFeedClient', () {
    HttpFeedClient client(MockClientHandler h, {String base = 'https://feed.example/data/'}) =>
        HttpFeedClient(base, client: MockClient(h), timeout: const Duration(milliseconds: 200));

    test('builds the URL from the base', () async {
      Uri? asked;
      final c = client((req) async {
        asked = req.url;
        return http.Response('{}', 200);
      });
      await c.get('quiz/index.json');
      expect(asked.toString(), 'https://feed.example/data/quiz/index.json');
    });
    test('base without a trailing slash', () {
      final c = client((_) async => http.Response('', 200), base: 'https://feed.example/data');
      expect(c.uriFor('quiz/index.json').toString(), 'https://feed.example/data/quiz/index.json');
    });
    for (final bad in ['../secret.json', 'quiz/../../x.json', '/etc/passwd', 'quiz/index.txt', 'Quiz/A.json', 'https://evil/x.json', 'a b.json', '']) {
      test('refuses unsafe path "$bad"', () {
        final c = client((_) async => http.Response('', 200));
        expect(() => c.uriFor(bad), throwsA(isA<FeedException>()));
      });
    }
    test('decodes UTF-8', () async {
      final c = client((_) async => http.Response.bytes(utf8.encode('{"hi":"हिंदी"}'), 200));
      expect(await c.get('a.json'), '{"hi":"हिंदी"}');
    });
    final codes = {404: FeedErrorKind.notFound, 500: FeedErrorKind.server, 403: FeedErrorKind.server, 301: FeedErrorKind.server};
    codes.forEach((code, kind) {
      test('HTTP $code is ${kind.name}', () async {
        final c = client((_) async => http.Response('x', code));
        await expectLater(c.get('a.json'), throwsA(isA<FeedException>().having((e) => e.kind, 'kind', kind)));
      });
    });
    test('socket error is offline', () async {
      final c = client((_) async => throw const SocketException('no route'));
      await expectLater(c.get('a.json'),
          throwsA(isA<FeedException>().having((e) => e.kind, 'kind', FeedErrorKind.offline)));
    });
    test('client exception is offline', () async {
      final c = client((_) async => throw http.ClientException('reset'));
      await expectLater(c.get('a.json'),
          throwsA(isA<FeedException>().having((e) => e.kind, 'kind', FeedErrorKind.offline)));
    });
    test('timeout is offline', () async {
      final c = client((_) => Completer<http.Response>().future);
      await expectLater(c.get('a.json'),
          throwsA(isA<FeedException>().having((e) => e.detail, 'detail', 'timeout')));
    });
    test('invalid UTF-8 is bad data', () async {
      final c = client((_) async => http.Response.bytes([0xff, 0xfe, 0xfd], 200));
      await expectLater(c.get('a.json'),
          throwsA(isA<FeedException>().having((e) => e.kind, 'kind', FeedErrorKind.badData)));
    });
    test('too large is bad data', () async {
      final c = client((_) async => http.Response.bytes(List.filled(HttpFeedClient.maxBytes + 1, 32), 200));
      await expectLater(c.get('a.json'),
          throwsA(isA<FeedException>().having((e) => e.kind, 'kind', FeedErrorKind.badData)));
    });
    test('FeedException toString', () {
      expect(const FeedException(FeedErrorKind.server, 'HTTP 500').toString(), contains('HTTP 500'));
      expect(const FeedException(FeedErrorKind.offline).toString(), 'FeedException(FeedErrorKind.offline)');
    });
  });
}

class _ThrowingClient implements FeedClient {
  @override
  Future<String> get(String path) async => throw StateError('boom');
}
