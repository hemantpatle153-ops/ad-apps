import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vacancy_bell/data/feed_cache.dart';
import 'package:vacancy_bell/data/feed_fetcher.dart';
import 'package:vacancy_bell/data/jobs_repository.dart';

import 'support/fakes.dart';

void main() {
  late FakeFetcher fetcher;
  late MemoryFeedCache cache;
  late DateTime now;
  late JobsRepository repo;

  setUp(() {
    fetcher = fixtureFetcher();
    cache = MemoryFeedCache();
    now = fixtureNow;
    repo = JobsRepository(fetcher: fetcher, cache: cache, clock: () => now);
  });

  group('index', () {
    test('fresh download', () async {
      final r = await repo.index();
      expect(r.source, FeedSource.network);
      expect(r.data!.posts.length, 20);
      expect(r.problem, isNull);
      expect(r.checkedAt, now);
      expect(repo.lastIndex, same(r.data));
    });
    test('is cached on disk', () async {
      await repo.index();
      expect((await cache.read(indexPath))!.body, indexJson);
    });
    test('sends the ETag and accepts 304', () async {
      fetcher.etags[indexPath] = '"v1"';
      await repo.index();
      now = now.add(const Duration(hours: 1));
      final r = await repo.index();
      expect(fetcher.requests.last, (indexPath, '"v1"'));
      expect(r.source, FeedSource.notModified);
      expect(r.data!.posts.length, 20);
      expect(r.checkedAt, now);
    });
    test('304 refreshes the saved time', () async {
      fetcher.etags[indexPath] = '"v1"';
      await repo.index();
      now = now.add(const Duration(hours: 2));
      await repo.index();
      expect((await cache.read(indexPath))!.savedAt, now);
    });
    test('changed ETag downloads again', () async {
      fetcher.etags[indexPath] = '"v1"';
      await repo.index();
      fetcher.etags[indexPath] = '"v2"';
      final r = await repo.index();
      expect(r.source, FeedSource.network);
      expect((await cache.read(indexPath))!.etag, '"v2"');
    });
    test('offline with a cache shows the cache', () async {
      await repo.index();
      fetcher.offline = true;
      now = now.add(const Duration(hours: 5));
      final r = await repo.index();
      expect(r.source, FeedSource.cache);
      expect(r.problem, FeedProblem.offline);
      expect(r.isStale, isTrue);
      expect(r.data!.posts.length, 20);
      expect(r.checkedAt, fixtureNow);
    });
    test('offline without a cache is an error', () async {
      fetcher.offline = true;
      final r = await repo.index();
      expect(r.source, FeedSource.none);
      expect(r.problem, FeedProblem.offline);
      expect(r.hasData, isFalse);
    });
    test('server error falls back to the cache', () async {
      await repo.index();
      fetcher.forceStatus = 503;
      final r = await repo.index();
      expect(r.problem, FeedProblem.server);
      expect(r.data, isNotNull);
    });
    test('server error without cache', () async {
      fetcher.forceStatus = 500;
      final r = await repo.index();
      expect((r.problem, r.hasData), (FeedProblem.server, false));
    });
    test('feed not published yet (404)', () async {
      fetcher.files.remove(indexPath);
      final r = await repo.index();
      expect((r.problem, r.hasData), (FeedProblem.notFound, false));
    });
    test('broken download keeps the last good copy', () async {
      await repo.index();
      fetcher.files[indexPath] = '{"posts": ';
      final r = await repo.index();
      expect(r.problem, FeedProblem.badData);
      expect(r.data!.posts.length, 20);
      expect((await cache.read(indexPath))!.body, indexJson);
    });
    test('broken download without cache', () async {
      fetcher.files[indexPath] = 'garbage';
      final r = await repo.index();
      expect((r.problem, r.hasData), (FeedProblem.badData, false));
    });
    test('corrupt cache with 304 refetches without ETag', () async {
      fetcher.etags[indexPath] = '"v1"';
      await cache.write(indexPath, CachedEntry(body: 'corrupt', etag: '"v1"', savedAt: now));
      final r = await repo.index();
      expect(r.source, FeedSource.network);
      expect(fetcher.requests.map((e) => e.$2), ['"v1"', null]);
    });
    test('corrupt cache while offline is no data', () async {
      await cache.write(indexPath, CachedEntry(body: 'corrupt', savedAt: now));
      fetcher.offline = true;
      final r = await repo.index();
      expect(r.hasData, isFalse);
    });
    test('parallel calls share one request', () async {
      fetcher.delay = const Duration(milliseconds: 10);
      final results = await Future.wait([repo.index(), repo.index(), repo.index()]);
      expect(fetcher.requests.length, 1);
      expect(results.every((r) => r.hasData), isTrue);
    });
    test('cachedIndex reads disk only', () async {
      await repo.index();
      final fresh = JobsRepository(fetcher: fetcher, cache: cache, clock: () => now);
      fetcher.requests.clear();
      final r = await fresh.cachedIndex();
      expect(r.source, FeedSource.cache);
      expect(r.data!.posts.length, 20);
      expect(fetcher.requests, isEmpty);
    });
    test('cachedIndex with nothing saved', () async {
      expect((await repo.cachedIndex()).source, FeedSource.none);
    });
  });

  group('posts', () {
    test('downloads and remembers a post', () async {
      final r = await repo.post('ssc-cgl-2026-notice');
      expect(r.source, FeedSource.network);
      expect(r.data!.importantDates, isNotEmpty);
      expect(repo.loadedPosts.containsKey('ssc-cgl-2026-notice'), isTrue);
    });
    test('opened posts work offline', () async {
      await repo.post('ssc-cgl-2026-notice');
      fetcher.offline = true;
      final r = await repo.post('ssc-cgl-2026-notice');
      expect(r.source, FeedSource.cache);
      expect(r.problem, FeedProblem.offline);
      expect(r.data!.fees.length, 3);
    });
    test('unopened post offline has no data', () async {
      fetcher.offline = true;
      final r = await repo.post('up-police-constable-2026');
      expect((r.hasData, r.problem), (false, FeedProblem.offline));
    });
    test('missing post is notFound', () async {
      final r = await repo.post('withdrawn-post');
      expect(r.problem, FeedProblem.notFound);
    });
    test('invalid ids never reach the network', () async {
      for (final id in ['../index', 'A B', '', 'x/y']) {
        final r = await repo.post(id);
        expect(r.problem, FeedProblem.notFound);
      }
      expect(fetcher.requests, isEmpty);
    });
    test('cachedPost reads memory or disk', () async {
      await repo.post('ssc-cgl-2026-notice');
      final fresh = JobsRepository(fetcher: fetcher, cache: cache, clock: () => now);
      expect((await fresh.cachedPost('ssc-cgl-2026-notice'))!.id, 'ssc-cgl-2026-notice');
      expect(await fresh.cachedPost('up-police-constable-2026'), isNull);
      expect(await fresh.cachedPost('../bad'), isNull);
    });
    test('allCachedPosts loads every saved post', () async {
      await repo.post('ssc-cgl-2026-notice');
      await repo.post('up-police-constable-2026');
      await repo.index();
      final fresh = JobsRepository(fetcher: fetcher, cache: cache, clock: () => now);
      final all = await fresh.allCachedPosts();
      expect(all.keys.toSet(), {'ssc-cgl-2026-notice', 'up-police-constable-2026'});
    });
    test('keeps at most maxCachedPosts post files, oldest out first', () async {
      final small = JobsRepository(fetcher: fetcher, cache: cache, clock: () => now, maxCachedPosts: 2);
      for (var i = 0; i < 4; i++) {
        fetcher.files[postPath('p-$i')] = '{"id": "p-$i", "title": "P $i"}';
        now = now.add(const Duration(minutes: 1));
        await small.post('p-$i');
      }
      final keys = (await cache.keys()).where((k) => k.startsWith('jobs/posts/')).toSet();
      expect(keys, {postPath('p-2'), postPath('p-3')});
    });
    test('saved posts are never evicted', () async {
      final small = JobsRepository(
          fetcher: fetcher, cache: cache, clock: () => now, maxCachedPosts: 1, keep: () => {'p-0'});
      for (var i = 0; i < 3; i++) {
        fetcher.files[postPath('p-$i')] = '{"id": "p-$i", "title": "P $i"}';
        now = now.add(const Duration(minutes: 1));
        await small.post('p-$i');
      }
      final keys = (await cache.keys()).where((k) => k.startsWith('jobs/posts/')).toSet();
      expect(keys, {postPath('p-0'), postPath('p-2')});
    });
    test('clearCache empties disk and memory', () async {
      await repo.index();
      await repo.post('ssc-cgl-2026-notice');
      await repo.clearCache();
      expect(await cache.keys(), isEmpty);
      expect(repo.loadedPosts, isEmpty);
      expect(repo.lastIndex, isNull);
    });
  });

  group('CachedEntry encoding', () {
    test('round trip', () {
      final e = CachedEntry(body: '{"a":1}', etag: 'W/"x"', savedAt: DateTime.utc(2026, 10, 7, 1, 2, 3));
      final back = CachedEntry.decode(e.encode())!;
      expect((back.body, back.etag, back.savedAt), (e.body, e.etag, e.savedAt));
    });
    test('without etag', () {
      final e = CachedEntry(body: 'x', savedAt: DateTime.utc(2026));
      expect(CachedEntry.decode(e.encode())!.etag, isNull);
    });
    for (final bad in ['', '{', '[]', '{"body": 1}', '{"body": "x"}', '{"body": "x", "savedAt": "never"}']) {
      test('rejects $bad', () => expect(CachedEntry.decode(bad), isNull));
    }
  });

  group('FileFeedCache', () {
    late Directory dir;
    late FileFeedCache files;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('vb_cache_');
      files = FileFeedCache(Directory('${dir.path}/feed'));
    });
    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('file names are flat and safe', () {
      expect(FileFeedCache.fileNameFor('jobs/posts/ssc-cgl.json'), 'jobs__posts__ssc-cgl.json');
      expect(FileFeedCache.fileNameFor('a b?c'), 'a_b_c');
      expect(FileFeedCache.keyForFileName('jobs__index.json'), 'jobs/index.json');
    });
    test('write then read', () async {
      final e = CachedEntry(body: 'hello', etag: '"e"', savedAt: DateTime.utc(2026, 10, 7));
      await files.write(indexPath, e);
      final back = (await files.read(indexPath))!;
      expect((back.body, back.etag), ('hello', '"e"'));
    });
    test('missing key is null', () async => expect(await files.read('nope.json'), isNull));
    test('keys lists feed paths', () async {
      await files.write(indexPath, CachedEntry(body: '1', savedAt: DateTime.utc(2026)));
      await files.write(postPath('a-1'), CachedEntry(body: '2', savedAt: DateTime.utc(2026)));
      expect((await files.keys()).toSet(), {indexPath, postPath('a-1')});
    });
    test('no temp files left behind', () async {
      await files.write(indexPath, CachedEntry(body: '1', savedAt: DateTime.utc(2026)));
      final names = Directory('${dir.path}/feed').listSync().map((e) => e.path);
      expect(names.any((n) => n.endsWith('.tmp')), isFalse);
    });
    test('delete and clear', () async {
      await files.write(indexPath, CachedEntry(body: '1', savedAt: DateTime.utc(2026)));
      await files.write(postPath('a-1'), CachedEntry(body: '2', savedAt: DateTime.utc(2026)));
      await files.delete(indexPath);
      expect(await files.read(indexPath), isNull);
      await files.clear();
      expect(await files.keys(), isEmpty);
    });
    test('corrupt file reads as null', () async {
      await Directory('${dir.path}/feed').create(recursive: true);
      File('${dir.path}/feed/${FileFeedCache.fileNameFor(indexPath)}').writeAsStringSync('{{{');
      expect(await files.read(indexPath), isNull);
    });
    test('works as the repository cache', () async {
      final r = JobsRepository(fetcher: fetcher, cache: files, clock: () => now);
      await r.index();
      fetcher.offline = true;
      final again = JobsRepository(fetcher: fetcher, cache: files, clock: () => now);
      final res = await again.index();
      expect(res.source, FeedSource.cache);
      expect(res.data!.posts.length, 20);
    });
  });

  group('HttpFeedFetcher', () {
    test('builds URLs under the base', () {
      final f = HttpFeedFetcher('https://raw.example.com/feed-data');
      expect(f.uriFor('jobs/index.json').toString(), 'https://raw.example.com/feed-data/jobs/index.json');
      final g = HttpFeedFetcher('https://raw.example.com/feed-data/');
      expect(g.uriFor('jobs/posts/a.json').toString(), 'https://raw.example.com/feed-data/jobs/posts/a.json');
    });
    test('200 with body and etag', () async {
      final client = MockClient((req) async {
        expect(req.headers['If-None-Match'], isNull);
        return http.Response('{"posts":[]}', 200, headers: {'etag': '"abc"'});
      });
      final r = await HttpFeedFetcher('https://x.example', client: client).get('jobs/index.json');
      expect((r.status, r.body, r.etag), (200, '{"posts":[]}', '"abc"'));
    });
    test('sends If-None-Match and passes 304 through', () async {
      final client = MockClient((req) async {
        expect(req.headers['If-None-Match'], '"abc"');
        return http.Response('', 304, headers: {'etag': '"abc"'});
      });
      final r = await HttpFeedFetcher('https://x.example', client: client).get('a', etag: '"abc"');
      expect((r.status, r.body), (304, null));
    });
    test('decodes UTF-8 Hindi', () async {
      final client = MockClient((_) async => http.Response.bytes(utf8.encode('{"t":"नमस्ते"}'), 200));
      final r = await HttpFeedFetcher('https://x.example', client: client).get('a');
      expect(r.body, '{"t":"नमस्ते"}');
    });
    test('network errors become FeedNetworkException', () async {
      final client = MockClient((_) async => throw http.ClientException('no route'));
      expect(() => HttpFeedFetcher('https://x.example', client: client).get('a'),
          throwsA(isA<FeedNetworkException>()));
    });
    test('socket errors too', () async {
      final client = MockClient((_) async => throw const SocketException('down'));
      expect(() => HttpFeedFetcher('https://x.example', client: client).get('a'),
          throwsA(isA<FeedNetworkException>()));
    });
    test('timeouts too', () async {
      final client = MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return http.Response('{}', 200);
      });
      final f = HttpFeedFetcher('https://x.example', client: client, timeout: const Duration(milliseconds: 20));
      expect(() => f.get('a'), throwsA(isA<FeedNetworkException>()));
    });
  });
}
