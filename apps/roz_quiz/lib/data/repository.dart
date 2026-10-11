import 'dart:convert';

import '../core/day.dart';
import '../core/models.dart';
import '../core/selection.dart';
import 'cache_store.dart';
import 'feed_client.dart';

enum DataSource { network, cache, bundled }

/// A value plus where it came from. [error] is set when the network was
/// tried and failed, even if a saved or bundled value is shown instead.
class Loaded<T> {
  const Loaded(this.value, this.source, {this.savedAt, this.error});
  const Loaded.failed(FeedErrorKind this.error)
      : value = null,
        source = null,
        savedAt = null;

  final T? value;
  final DataSource? source;
  final DateTime? savedAt;
  final FeedErrorKind? error;

  bool get hasValue => value != null;
  bool get offline => error == FeedErrorKind.offline;
}

/// Reads the bundled starter bank (rootBundle in the app, files in tests).
abstract class BundleLoader {
  Future<String> load(String assetPath);
}

/// Questions and notes from the feed, the on-disk cache and the bundled
/// starter bank, in that order of preference.
class QuizRepository {
  QuizRepository({
    required this.client,
    required this.cache,
    required this.bundle,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final FeedClient client;
  final CacheStore cache;
  final BundleLoader bundle;
  final DateTime Function() _clock;

  /// Subjects with a bundled `assets/bank/<subject>.json`.
  static const bundledSubjects = [
    'gk',
    'history',
    'polity',
    'geography',
    'economy',
    'science',
    'maths',
    'reasoning',
    'english',
    'computer',
  ];

  static const indexPath = 'quiz/index.json';
  static String dailyPath(Day d) => 'quiz/daily/${d.key}.json';
  static String caPath(Day d) => 'quiz/current_affairs/${d.key}.json';
  static String bundledAsset(String subject) => 'assets/bank/$subject.json';

  /// How long a saved index or today's current affairs count as fresh.
  static const freshFor = Duration(hours: 1);

  List<Question>? _bundled;

  Future<List<Question>> bundledQuestions() async {
    final cached = _bundled;
    if (cached != null) return cached;
    final out = <Question>[];
    final ids = <String>{};
    for (final s in bundledSubjects) {
      try {
        final bank = QuestionBank.tryParse(jsonDecode(await bundle.load(bundledAsset(s))));
        for (final q in bank?.questions ?? const <Question>[]) {
          if (ids.add(q.id)) out.add(q);
        }
      } catch (_) {
        // A broken asset must not stop the app; the test suite guards it.
      }
    }
    return _bundled = List.unmodifiable(out);
  }

  Object? _decode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  /// Network first unless a fresh-enough copy is saved; on failure the
  /// saved copy (any age).
  Future<Loaded<T>> _load<T>(
    String path,
    T? Function(Object? json) parse, {
    required bool Function(CachedFile saved) fresh,
    bool refresh = false,
  }) async {
    final saved = await cache.read(path);
    final savedValue = saved == null ? null : parse(_decode(saved.text));
    if (!refresh && saved != null && savedValue != null && fresh(saved)) {
      return Loaded(savedValue, DataSource.cache, savedAt: saved.savedAt);
    }
    FeedErrorKind error;
    try {
      final text = await client.get(path);
      final value = parse(_decode(text));
      if (value != null) {
        final now = _clock().toUtc();
        await cache.write(path, text, now);
        _pool = null;
        return Loaded(value, DataSource.network, savedAt: now);
      }
      error = FeedErrorKind.badData;
    } on FeedException catch (e) {
      error = e.kind;
    } catch (_) {
      error = FeedErrorKind.offline;
    }
    if (savedValue != null) {
      return Loaded(savedValue, DataSource.cache,
          savedAt: saved!.savedAt, error: error);
    }
    return Loaded.failed(error);
  }

  Future<Loaded<FeedIndex>> index({bool refresh = false}) => _load(
        indexPath,
        FeedIndex.tryParse,
        refresh: refresh,
        fresh: (s) => _clock().toUtc().difference(s.savedAt) < freshFor,
      );

  /// The Daily Quiz for [day]. Published dailies never change, so a saved
  /// one is used as is. Without network and without a saved copy the
  /// questions come from the bundled bank ([DataSource.bundled]), the same
  /// on every phone.
  Future<Loaded<DailyQuiz>> daily(Day day, {bool refresh = false}) async {
    final r = await _load(dailyPath(day),
        (j) => DailyQuiz.tryParse(j, expected: day),
        refresh: refresh, fresh: (_) => true);
    if (r.hasValue) return r;
    final picked = dailyFallback(day, await bundledQuestions());
    if (picked.isEmpty) return r;
    return Loaded(DailyQuiz(date: day, questions: picked), DataSource.bundled,
        error: r.error);
  }

  /// Current affairs for [day]; today's file may still grow, so it is
  /// re-fetched after [freshFor].
  Future<Loaded<CaDay>> currentAffairs(Day day, {bool refresh = false}) {
    final today = Day.ist(_clock());
    return _load(caPath(day), (j) => CaDay.tryParse(j, expected: day),
        refresh: refresh,
        fresh: (s) =>
            day.isBefore(today) ||
            _clock().toUtc().difference(s.savedAt) < freshFor);
  }

  /// Downloads every bank in the index that changed since it was saved.
  /// Returns how many banks were fetched; throws [FeedException] when the
  /// index itself can't be read.
  Future<int> downloadBanks() async {
    final idx = await index(refresh: true);
    final value = idx.value;
    if (value == null) throw FeedException(idx.error ?? FeedErrorKind.offline);
    if (idx.error != null) throw FeedException(idx.error!);
    var fetched = 0;
    for (final b in value.banks) {
      final saved = await cache.read(b.file);
      final upToDate = saved != null &&
          b.updatedAt != null &&
          !saved.savedAt.isBefore(b.updatedAt!);
      if (upToDate) continue;
      final r = await _load(b.file, QuestionBank.tryParse,
          refresh: true, fresh: (_) => false);
      if (r.source == DataSource.network) fetched++;
    }
    return fetched;
  }

  /// Every question the phone has: bundled bank, downloaded banks, saved
  /// dailies and current affairs quizzes. Downloaded copies win over
  /// bundled ones with the same id.
  Future<List<Question>> pool() async => _pool ??= await _buildPool();

  List<Question>? _pool;

  Future<List<Question>> _buildPool() async {
    final byId = <String, Question>{
      for (final q in await bundledQuestions()) q.id: q,
    };
    for (final path in await cache.paths()) {
      final saved = await cache.read(path);
      if (saved == null) continue;
      final json = _decode(saved.text);
      final List<Question> qs;
      if (path.startsWith('quiz/banks/')) {
        qs = QuestionBank.tryParse(json)?.questions ?? const [];
      } else if (path.startsWith('quiz/daily/')) {
        qs = DailyQuiz.tryParse(json)?.questions ?? const [];
      } else if (path.startsWith('quiz/current_affairs/')) {
        qs = CaDay.tryParse(json)?.questions ?? const [];
      } else {
        continue;
      }
      for (final q in qs) {
        byId[q.id] = q;
      }
    }
    return List.unmodifiable(byId.values);
  }

  /// Newest save time of any downloaded file, or null when nothing was
  /// ever downloaded.
  Future<DateTime?> lastUpdated() async {
    DateTime? newest;
    for (final p in await cache.paths()) {
      final s = await cache.read(p);
      if (s != null && (newest == null || s.savedAt.isAfter(newest))) {
        newest = s.savedAt;
      }
    }
    return newest;
  }

  Future<void> clearCache() async {
    _pool = null;
    await cache.clear();
  }
}
