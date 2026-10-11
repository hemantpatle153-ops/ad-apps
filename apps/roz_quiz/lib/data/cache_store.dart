import 'dart:convert';
import 'dart:io';

/// A saved copy of one feed file.
class CachedFile {
  const CachedFile(this.text, this.savedAt);
  final String text;
  final DateTime savedAt;
}

/// Keeps downloaded feed files so the app works offline.
abstract class CacheStore {
  Future<CachedFile?> read(String path);
  Future<void> write(String path, String text, DateTime savedAt);
  Future<List<String>> paths();
  Future<void> clear();
}

class MemoryCacheStore implements CacheStore {
  final Map<String, CachedFile> files = {};

  @override
  Future<CachedFile?> read(String path) async => files[path];

  @override
  Future<void> write(String path, String text, DateTime savedAt) async =>
      files[path] = CachedFile(text, savedAt);

  @override
  Future<List<String>> paths() async => files.keys.toList();

  @override
  Future<void> clear() async => files.clear();
}

/// Files under the app's support folder. Each feed path becomes one file
/// whose first line is the save time; writes go through a temp file and a
/// rename so a crash never leaves half a file.
class FileCacheStore implements CacheStore {
  FileCacheStore(this.dir);
  final Directory dir;

  File _file(String path) =>
      File('${dir.path}/${base64Url.encode(utf8.encode(path))}.cache');

  @override
  Future<CachedFile?> read(String path) async {
    final f = _file(path);
    try {
      if (!await f.exists()) return null;
      final raw = await f.readAsString();
      final nl = raw.indexOf('\n');
      if (nl < 0) return null;
      final ms = int.tryParse(raw.substring(0, nl));
      if (ms == null) return null;
      return CachedFile(raw.substring(nl + 1),
          DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true));
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(String path, String text, DateTime savedAt) async {
    await dir.create(recursive: true);
    final f = _file(path);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString('${savedAt.toUtc().millisecondsSinceEpoch}\n$text',
        flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<List<String>> paths() async {
    if (!await dir.exists()) return const [];
    final out = <String>[];
    await for (final e in dir.list()) {
      final name = e.uri.pathSegments.last;
      if (!name.endsWith('.cache')) continue;
      try {
        out.add(utf8.decode(base64Url.decode(name.substring(0, name.length - 6))));
      } on FormatException {
        // Not one of ours.
      }
    }
    return out;
  }

  @override
  Future<void> clear() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
