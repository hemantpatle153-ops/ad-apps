import 'dart:async';

import '../core/json_read.dart';
import '../models/feed_index.dart';
import '../models/post.dart';
import 'feed_cache.dart';
import 'feed_fetcher.dart';

enum FeedSource {
  /// Downloaded just now.
  network,

  /// The server said nothing changed (304); the cached copy is current.
  notModified,

  /// The network failed; this is the last good copy.
  cache,

  /// Nothing to show.
  none,
}

enum FeedProblem {
  /// No internet / timeout.
  offline,

  /// The server answered with an error code.
  server,

  /// The file arrived but could not be read.
  badData,

  /// The post no longer exists in the feed.
  notFound,
}

class FeedResult<T> {
  const FeedResult({this.data, required this.source, this.checkedAt, this.problem});

  final T? data;
  final FeedSource source;

  /// When this data was last confirmed current with the server.
  final DateTime? checkedAt;

  /// Why fresh data could not be had (also set when cached data is shown).
  final FeedProblem? problem;

  bool get hasData => data != null;

  /// Showing an older copy because the refresh failed.
  bool get isStale => data != null && problem != null;
}

String postPath(String id) => 'jobs/posts/$id.json';
const indexPath = 'jobs/index.json';

/// Reads the feed with conditional requests, and keeps the last good index
/// and every opened post on disk for offline use.
class JobsRepository {
  JobsRepository({
    required this.fetcher,
    required this.cache,
    DateTime Function()? clock,
    this.maxCachedPosts = 150,
    this.keep,
  }) : _clock = clock ?? DateTime.now;

  /// Ids of posts never evicted from the cache (saved jobs).
  final Set<String> Function()? keep;

  final FeedFetcher fetcher;
  final FeedCache cache;
  final DateTime Function() _clock;
  final int maxCachedPosts;

  FeedIndex? _index;
  final Map<String, PostDetail> _posts = {};
  Future<FeedResult<FeedIndex>>? _indexInFlight;
  final Map<String, Future<FeedResult<PostDetail>>> _postsInFlight = {};

  /// The last index read in this session (network or disk).
  FeedIndex? get lastIndex => _index;

  /// Post details read in this session.
  Map<String, PostDetail> get loadedPosts => Map.unmodifiable(_posts);

  /// The cached index from disk, without any network request.
  Future<FeedResult<FeedIndex>> cachedIndex() async {
    final cached = await cache.read(indexPath);
    if (cached == null) return const FeedResult(source: FeedSource.none);
    try {
      final idx = _index = FeedIndex.parse(cached.body);
      return FeedResult(data: idx, source: FeedSource.cache, checkedAt: cached.savedAt);
    } on FormatException {
      return const FeedResult(source: FeedSource.none, problem: FeedProblem.badData);
    }
  }

  /// Fetches the index, falling back to the cached copy.
  Future<FeedResult<FeedIndex>> index() =>
      _indexInFlight ??= _load<FeedIndex>(indexPath, FeedIndex.parse)
          .then((r) {
        if (r.data != null) _index = r.data;
        return r;
      }).whenComplete(() {
        _indexInFlight = null;
      });

  /// Fetches one post, falling back to the cached copy.
  Future<FeedResult<PostDetail>> post(String id) {
    if (!isValidPostId(id)) {
      return Future.value(
          const FeedResult(source: FeedSource.none, problem: FeedProblem.notFound));
    }
    return _postsInFlight[id] ??=
        _load<PostDetail>(postPath(id), parsePostDetail).then((r) async {
      if (r.data != null) {
        _posts[id] = r.data!;
        if (r.source == FeedSource.network) await _trimPosts();
      }
      return r;
    }).whenComplete(() {
      // Block body: returning the removed future would make it wait on itself.
      _postsInFlight.remove(id);
    });
  }

  /// A post from memory or disk only (for the calendar and offline lists).
  Future<PostDetail?> cachedPost(String id) async {
    final mem = _posts[id];
    if (mem != null) return mem;
    if (!isValidPostId(id)) return null;
    final c = await cache.read(postPath(id));
    if (c == null) return null;
    try {
      return _posts[id] = parsePostDetail(c.body);
    } on FormatException {
      return null;
    }
  }

  /// Loads every cached post into memory (for the calendar).
  Future<Map<String, PostDetail>> allCachedPosts() async {
    for (final key in await cache.keys()) {
      if (!key.startsWith('jobs/posts/') || !key.endsWith('.json')) continue;
      final id = key.substring('jobs/posts/'.length, key.length - '.json'.length);
      await cachedPost(id);
    }
    return loadedPosts;
  }

  Future<void> clearCache() async {
    await cache.clear();
    _posts.clear();
    _index = null;
  }

  Future<FeedResult<T>> _load<T>(String path, T Function(String) parse) async {
    final cached = await cache.read(path);
    FeedResult<T> fallback(FeedProblem problem) {
      if (cached != null) {
        try {
          return FeedResult(
              data: parse(cached.body),
              source: FeedSource.cache,
              checkedAt: cached.savedAt,
              problem: problem);
        } on FormatException {
          // Corrupt cache: treat as missing.
        }
      }
      return FeedResult(source: FeedSource.none, problem: problem);
    }

    FetchResponse res;
    try {
      res = await fetcher.get(path, etag: cached?.etag);
    } on FeedNetworkException {
      return fallback(FeedProblem.offline);
    }
    final now = _clock().toUtc();
    if (res.status == 304 && cached != null) {
      try {
        final data = parse(cached.body);
        await cache.write(path, cached.touched(now));
        return FeedResult(data: data, source: FeedSource.notModified, checkedAt: now);
      } on FormatException {
        // The cached copy is broken; fetch it again without the ETag.
        await cache.delete(path);
        return _load(path, parse);
      }
    }
    if (res.status == 200 && res.body != null) {
      try {
        final data = parse(res.body!);
        await cache.write(path, CachedEntry(body: res.body!, etag: res.etag, savedAt: now));
        return FeedResult(data: data, source: FeedSource.network, checkedAt: now);
      } on FormatException {
        return fallback(FeedProblem.badData);
      }
    }
    if (res.status == 404) return fallback(FeedProblem.notFound);
    return fallback(FeedProblem.server);
  }

  /// Keeps at most [maxCachedPosts] post files, dropping the oldest saved.
  Future<void> _trimPosts() async {
    final pinned = {for (final id in keep?.call() ?? const <String>{}) postPath(id)};
    final keys = [
      for (final k in await cache.keys())
        if (k.startsWith('jobs/posts/') && !pinned.contains(k)) k,
    ];
    if (keys.length <= maxCachedPosts) return;
    final dated = <(String, DateTime)>[];
    for (final k in keys) {
      final e = await cache.read(k);
      dated.add((k, e?.savedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)));
    }
    dated.sort((a, b) => a.$2.compareTo(b.$2));
    for (final (k, _) in dated.take(keys.length - maxCachedPosts)) {
      await cache.delete(k);
    }
  }
}
