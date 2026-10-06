import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A built-in OpenSubtitles.com API key, optional: builds may pass one with
/// --dart-define=OPENSUBTITLES_API_KEY=... (CI reads a repository secret).
/// Otherwise each person pastes their own free key in Settings.
const openSubtitlesApiKey = String.fromEnvironment('OPENSUBTITLES_API_KEY');

/// Where people get their own free key.
const openSubtitlesKeyPage = 'https://www.opensubtitles.com/en/consumers';

/// The key to use: the person's own if they added one, else the build's.
String captionApiKey(String own) => own.trim().isNotEmpty ? own.trim() : openSubtitlesApiKey;

/// The OpenSubtitles "movie hash": file size plus the 64-bit sums of the
/// first and last 64 KB, read as little-endian numbers. Two copies of the
/// same file have the same hash, so captions found by it already fit.
Future<String?> movieHash(String path) async {
  RandomAccessFile? f;
  try {
    f = await File(path).open();
    final size = await f.length();
    const chunk = 65536;
    if (size < chunk) return null;
    final head = await f.read(chunk);
    await f.setPosition(size - chunk);
    final tail = await f.read(chunk);
    return movieHashOf(size, head, tail);
  } catch (_) {
    return null;
  } finally {
    await f?.close();
  }
}

/// [movieHash] on bytes already read; split out for tests.
String movieHashOf(int size, Uint8List head, Uint8List tail) {
  var hash = size;
  for (final part in [head, tail]) {
    final data = ByteData.sublistView(part);
    for (var i = 0; i + 8 <= part.length; i += 8) {
      // Dart ints are 64-bit and wrap on overflow, as the algorithm wants.
      hash += data.getUint64(i, Endian.little);
    }
  }
  return hash.toUnsigned(64).toRadixString(16).padLeft(16, '0');
}

/// What to search for, read from a file name like
/// "The.Movie.2019.1080p.WEB-DL.x264.mkv" or "Show.S02E05.720p.mp4".
class CaptionQuery {
  const CaptionQuery({required this.title, this.year, this.season, this.episode});

  final String title;
  final int? year;
  final int? season;
  final int? episode;

  static final _episode = RegExp(r'\bs(\d{1,2})[ ._-]?e(\d{1,3})\b', caseSensitive: false);
  static final _episodeX = RegExp(r'\b(\d{1,2})x(\d{2,3})\b');
  static final _year = RegExp(r'\b(19[2-9]\d|20[0-4]\d)\b');
  static final _noise = RegExp(
      r'\b(2160p|1080p|720p|480p|360p|4k|uhd|hdr|web[ -]?dl|webrip|bluray|blu[ -]?ray|brrip|'
      r'bdrip|dvdrip|hdtv|hdrip|x26[45]|h ?26[45]|hevc|aac|ac3|ddp?5 ?1|10bit|proper|repack|'
      r'extended|unrated|yify|yts|rarbg|hindi|dual audio|esubs?)\b.*$',
      caseSensitive: false);

  factory CaptionQuery.fromFileName(String name) {
    var s = name;
    final dot = s.lastIndexOf('.');
    if (dot > 0 && s.length - dot <= 5) s = s.substring(0, dot);
    s = s.replaceAll(RegExp(r'[._]+'), ' ').replaceAll(RegExp(r'[\[\(].*?[\]\)]'), ' ');
    int? season, episode, year;
    final ep = _episode.firstMatch(s) ?? _episodeX.firstMatch(s);
    if (ep != null) {
      season = int.parse(ep.group(1)!);
      episode = int.parse(ep.group(2)!);
      s = s.substring(0, ep.start);
    }
    final y = _year.firstMatch(s);
    if (y != null && y.start > 0) {
      year = int.parse(y.group(1)!);
      s = s.substring(0, y.start);
    }
    s = s.replaceAll(_noise, '').replaceAll(RegExp(r'\s*-\s*$'), '');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return CaptionQuery(
        title: s.isEmpty ? name : s, year: year, season: season, episode: episode);
  }
}

/// One subtitle file found online.
class CaptionResult {
  const CaptionResult({
    required this.fileId,
    required this.language,
    required this.release,
    required this.downloads,
    required this.exactMatch,
    this.hearingImpaired = false,
  });

  final int fileId;
  final String language;
  final String release;
  final int downloads;

  /// Made for this exact file, so its timing fits.
  final bool exactMatch;
  final bool hearingImpaired;

  static List<CaptionResult> listFromJson(Map<String, Object?> json) {
    final out = <CaptionResult>[];
    for (final item in (json['data'] as List? ?? const [])) {
      if (item is! Map) continue;
      final a = item['attributes'];
      if (a is! Map) continue;
      final files = a['files'];
      if (files is! List || files.isEmpty || files.first is! Map) continue;
      final id = (files.first as Map)['file_id'];
      if (id is! num) continue;
      out.add(CaptionResult(
        fileId: id.toInt(),
        language: '${a['language'] ?? ''}',
        release: '${a['release'] ?? (files.first as Map)['file_name'] ?? 'Subtitle'}',
        downloads: (a['download_count'] as num?)?.toInt() ?? 0,
        exactMatch: a['moviehash_match'] == true,
        hearingImpaired: a['hearing_impaired'] == true,
      ));
    }
    // Exact file matches first, then the most downloaded.
    out.sort((x, y) {
      if (x.exactMatch != y.exactMatch) return x.exactMatch ? -1 : 1;
      return y.downloads.compareTo(x.downloads);
    });
    return out;
  }
}

class CaptionException implements Exception {
  const CaptionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Talks to api.opensubtitles.com.
class OpenSubtitles {
  OpenSubtitles({this.apiKey = openSubtitlesApiKey, HttpClient? client})
      : _client = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 10));

  final String apiKey;
  final HttpClient _client;

  static const _host = 'api.opensubtitles.com';
  static const _agent = 'OnlySoftware VideoPlayer v2';

  bool get available => apiKey.isNotEmpty;

  Future<Map<String, Object?>> _call(String method, Uri uri, [Object? body]) async {
    if (!available) {
      throw const CaptionException('Add your free OpenSubtitles key in Settings first.');
    }
    try {
      final req = await _client.openUrl(method, uri);
      req.headers
        ..set('Api-Key', apiKey)
        ..set(HttpHeaders.userAgentHeader, _agent)
        ..set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close().timeout(const Duration(seconds: 20));
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode == 406 || res.statusCode == 429) {
        throw const CaptionException(
            "Today's free caption downloads are used up. Try again tomorrow.");
      }
      if (res.statusCode == 401 || res.statusCode == 403) {
        throw const CaptionException(
            "The OpenSubtitles key isn't valid. Check it in Settings > Caption search key.");
      }
      if (res.statusCode >= 400) {
        throw CaptionException('Caption search failed (${res.statusCode}).');
      }
      final v = jsonDecode(text);
      return v is Map<String, Object?> ? v : const {};
    } on CaptionException {
      rethrow;
    } catch (_) {
      throw const CaptionException("Couldn't reach the caption service. Check your internet.");
    }
  }

  /// Searches by the file's hash (exact matches) and by its name.
  Future<List<CaptionResult>> search({
    String? hash,
    required CaptionQuery query,
    required List<String> languages,
  }) {
    final params = <String, String>{
      'languages': (languages.toList()..sort()).join(','),
      if (hash != null) 'moviehash': hash,
      'query': query.title.toLowerCase(),
      if (query.year != null && query.season == null) 'year': '${query.year}',
      if (query.season != null) 'season_number': '${query.season}',
      if (query.episode != null) 'episode_number': '${query.episode}',
    };
    // The API asks for parameters in alphabetical order.
    final sorted = Map.fromEntries(
        params.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
    return _call('GET', Uri.https(_host, '/api/v1/subtitles', sorted))
        .then(CaptionResult.listFromJson);
  }

  /// Downloads a subtitle into [dir] and returns the file's path.
  Future<String> download(CaptionResult r, Directory dir) async {
    final info = await _call(
        'POST', Uri.https(_host, '/api/v1/download'), {'file_id': r.fileId, 'sub_format': 'srt'});
    final link = info['link'];
    if (link is! String) {
      throw CaptionException('${info['message'] ?? "Couldn't download this caption."}');
    }
    try {
      final req = await _client.getUrl(Uri.parse(link));
      req.headers.set(HttpHeaders.userAgentHeader, _agent);
      final res = await req.close().timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw const CaptionException("Couldn't download this caption.");
      await dir.create(recursive: true);
      final file = File('${dir.path}/${r.fileId}-${r.language}.srt');
      final sink = file.openWrite();
      await res.pipe(sink);
      return file.path;
    } on CaptionException {
      rethrow;
    } catch (_) {
      throw const CaptionException("Couldn't download this caption.");
    }
  }
}

/// Languages offered in the caption search, as OpenSubtitles codes.
const captionLanguages = <String, String>{
  'en': 'English',
  'hi': 'Hindi',
  'bn': 'Bengali',
  'ta': 'Tamil',
  'te': 'Telugu',
  'ml': 'Malayalam',
  'mr': 'Marathi',
  'ur': 'Urdu',
  'ar': 'Arabic',
  'es': 'Spanish',
  'fr': 'French',
  'de': 'German',
  'pt-BR': 'Portuguese (Brazil)',
  'id': 'Indonesian',
  'tr': 'Turkish',
  'ru': 'Russian',
  'zh-CN': 'Chinese',
  'ja': 'Japanese',
  'ko': 'Korean',
};
