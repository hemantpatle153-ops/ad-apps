import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// The app's OpenSubtitles.com API key, passed at build time with
/// --dart-define=OPENSUBTITLES_API_KEY=... (CI reads a repository secret).
/// OpenSubtitles asks apps to use one key of their own and never to make
/// users create keys; users may sign in instead for their own daily limit.
const openSubtitlesApiKey = String.fromEnvironment('OPENSUBTITLES_API_KEY');

/// Where people make a free OpenSubtitles account.
const openSubtitlesSignUpPage =
    'https://www.opensubtitles.com/en/users/sign_up';

/// A signed-in OpenSubtitles account: the token and the server it was
/// given for. The password is never kept.
class CaptionAccount {
  const CaptionAccount(
      {required this.user,
      required this.token,
      this.host = 'api.opensubtitles.com'});

  final String user;
  final String token;
  final String host;
}

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
  const CaptionQuery(
      {required this.title, this.year, this.season, this.episode});

  final String title;
  final int? year;
  final int? season;
  final int? episode;

  static final _episode =
      RegExp(r'\bs(\d{1,2})[ ._-]?e(\d{1,3})\b', caseSensitive: false);
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
    s = s
        .replaceAll(RegExp(r'[._]+'), ' ')
        .replaceAll(RegExp(r'[\[\(].*?[\]\)]'), ' ');
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
        title: s.isEmpty ? name : s,
        year: year,
        season: season,
        episode: episode);
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
        release:
            '${a['release'] ?? (files.first as Map)['file_name'] ?? 'Subtitle'}',
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
  OpenSubtitles({
    this.apiKey = openSubtitlesApiKey,
    this.account,
    HttpClient? client,
    @visibleForTesting
    Uri Function(String host, String path, [Map<String, String>? query])? uri,
  })  : _client = client ??
            (HttpClient()..connectionTimeout = const Duration(seconds: 10)),
        _uri = uri ?? Uri.https;

  final String apiKey;

  /// Signed in: downloads count against this person's own daily limit.
  final CaptionAccount? account;
  final HttpClient _client;
  final Uri Function(String host, String path, [Map<String, String>? query])
      _uri;

  static const _agent = 'OnlySoftware VideoPlayer v2';

  String get _host => account?.host ?? 'api.opensubtitles.com';

  /// False in builds made without the app key.
  bool get available => apiKey.isNotEmpty;

  /// Signs in and returns the account to remember (not the password).
  Future<CaptionAccount> signIn(String user, String password) async {
    final r = await _call(
        'POST',
        _uri('api.opensubtitles.com', '/api/v1/login'),
        {'username': user.trim(), 'password': password},
        true);
    final token = r['token'];
    if (token is! String || token.isEmpty) {
      throw const CaptionException(
          "Couldn't sign in. Check the user name and password.");
    }
    final host = r['base_url'];
    return CaptionAccount(
        user: user.trim(),
        token: token,
        host: host is String && host.endsWith('opensubtitles.com')
            ? host
            : 'api.opensubtitles.com');
  }

  Future<Map<String, Object?>> _call(String method, Uri uri,
      [Object? body, bool signingIn = false]) async {
    if (!available) {
      throw const CaptionException(
          "Caption search isn't set up in this version of the app yet.");
    }
    try {
      final req = await _client.openUrl(method, uri);
      req.headers
        ..set('Api-Key', apiKey)
        ..set(HttpHeaders.userAgentHeader, _agent)
        ..set(HttpHeaders.acceptHeader, 'application/json');
      final a = account;
      if (a != null && !signingIn) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${a.token}');
      }
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close().timeout(const Duration(seconds: 20));
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode == 406 || res.statusCode == 429) {
        throw CaptionException(account == null
            ? "Today's free caption downloads are used up. Sign in under "
                'Settings > Caption account for your own daily downloads.'
            : "Today's caption downloads are used up. Try again tomorrow.");
      }
      if (signingIn && (res.statusCode == 400 || res.statusCode == 401)) {
        throw const CaptionException(
            "Couldn't sign in. Check the user name and password.");
      }
      if (res.statusCode == 401 || res.statusCode == 403) {
        throw CaptionException(account == null
            ? "Caption search isn't working right now. Try again later."
            : 'Your caption account sign-in ran out. Sign in again under '
                'Settings > Caption account.');
      }
      if (res.statusCode >= 400) {
        throw CaptionException('Caption search failed (${res.statusCode}).');
      }
      final v = jsonDecode(text);
      return v is Map<String, Object?> ? v : const {};
    } on CaptionException {
      rethrow;
    } catch (_) {
      throw const CaptionException(
          "Couldn't reach the caption service. Check your internet.");
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
    return _call('GET', _uri(_host, '/api/v1/subtitles', sorted))
        .then(CaptionResult.listFromJson);
  }

  /// Downloads a subtitle into [dir] and returns the file's path.
  Future<String> download(CaptionResult r, Directory dir) async {
    final info = await _call('POST', _uri(_host, '/api/v1/download'),
        {'file_id': r.fileId, 'sub_format': 'srt'});
    final link = info['link'];
    if (link is! String) {
      throw CaptionException(
          '${info['message'] ?? "Couldn't download this caption."}');
    }
    try {
      final req = await _client.getUrl(Uri.parse(link));
      req.headers.set(HttpHeaders.userAgentHeader, _agent);
      final res = await req.close().timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        throw const CaptionException("Couldn't download this caption.");
      }
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
