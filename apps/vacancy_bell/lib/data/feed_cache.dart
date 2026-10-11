import 'dart:convert';
import 'dart:io';

/// One cached feed file with its ETag and when it was last confirmed fresh.
class CachedEntry {
  const CachedEntry({required this.body, required this.savedAt, this.etag});
  final String body;
  final String? etag;
  final DateTime savedAt;

  CachedEntry touched(DateTime at) =>
      CachedEntry(body: body, etag: etag, savedAt: at);

  String encode() => jsonEncode({
        'v': 1,
        'etag': etag,
        'savedAt': savedAt.toUtc().toIso8601String(),
        'body': body,
      });

  static CachedEntry? decode(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      final body = m['body'];
      final saved = m['savedAt'] is String ? DateTime.tryParse(m['savedAt'] as String) : null;
      if (body is! String || saved == null) return null;
      return CachedEntry(
        body: body,
        etag: m['etag'] is String ? m['etag'] as String : null,
        savedAt: saved.toUtc(),
      );
    } on FormatException {
      return null;
    }
  }
}

/// Last good copies of feed files, keyed by feed path.
abstract class FeedCache {
  Future<CachedEntry?> read(String key);
  Future<void> write(String key, CachedEntry entry);
  Future<void> delete(String key);

  /// Keys (feed paths) currently cached.
  Future<List<String>> keys();
  Future<void> clear();
}

class MemoryFeedCache implements FeedCache {
  final Map<String, CachedEntry> entries = {};

  @override
  Future<CachedEntry?> read(String key) async => entries[key];

  @override
  Future<void> write(String key, CachedEntry entry) async => entries[key] = entry;

  @override
  Future<void> delete(String key) async => entries.remove(key);

  @override
  Future<List<String>> keys() async => entries.keys.toList();

  @override
  Future<void> clear() async => entries.clear();
}

/// Files in the app's private storage, one per feed path. Writes go to a
/// temporary file first so a crash never leaves half a file behind.
class FileFeedCache implements FeedCache {
  FileFeedCache(this.dir);
  final Directory dir;

  /// "jobs/posts/ssc-cgl.json" -> "jobs__posts__ssc-cgl.json". Feed paths
  /// only contain [a-z0-9-_./]; anything else is replaced.
  static String fileNameFor(String key) =>
      key.replaceAll('/', '__').replaceAll(RegExp(r'[^A-Za-z0-9_.\-]'), '_');

  static String keyForFileName(String name) => name.replaceAll('__', '/');

  File _file(String key) => File('${dir.path}/${fileNameFor(key)}');

  @override
  Future<CachedEntry?> read(String key) async {
    final f = _file(key);
    try {
      if (!await f.exists()) return null;
      return CachedEntry.decode(await f.readAsString());
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> write(String key, CachedEntry entry) async {
    try {
      await dir.create(recursive: true);
      final f = _file(key);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(entry.encode(), flush: true);
      await tmp.rename(f.path);
    } on FileSystemException {
      // A full disk only costs offline reading; never crash for it.
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      final f = _file(key);
      if (await f.exists()) await f.delete();
    } on FileSystemException {
      // Ignore.
    }
  }

  @override
  Future<List<String>> keys() async {
    try {
      if (!await dir.exists()) return [];
      return [
        await for (final e in dir.list())
          if (e is File && e.path.endsWith('.json'))
            keyForFileName(e.uri.pathSegments.last),
      ];
    } on FileSystemException {
      return [];
    }
  }

  @override
  Future<void> clear() async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException {
      // Ignore.
    }
  }
}
