import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// The app's subtitle search key, set at build time:
///   flutter build apk --dart-define=OPENSUBTITLES_API_KEY=...
/// Without it the "Find subtitles online" option explains it is unavailable.
/// The service forbids asking users for their own key; users raise their
/// daily limit by signing in with their own account instead.
const openSubtitlesKey = String.fromEnvironment('OPENSUBTITLES_API_KEY');

const _host = 'api.opensubtitles.com';
const _userAgent = 'OnlySoftware Video Player v1.0';

bool get onlineSubtitlesAvailable => openSubtitlesKey.isNotEmpty;

/// Languages offered in the search, most used first.
const subtitleLanguages = {
  'en': 'English',
  'hi': 'Hindi',
  'es': 'Spanish',
  'ar': 'Arabic',
  'pt-BR': 'Portuguese (Brazil)',
  'fr': 'French',
  'de': 'German',
  'it': 'Italian',
  'ru': 'Russian',
  'tr': 'Turkish',
  'id': 'Indonesian',
  'bn': 'Bengali',
  'ta': 'Tamil',
  'te': 'Telugu',
  'ml': 'Malayalam',
  'ur': 'Urdu',
  'zh-CN': 'Chinese (simplified)',
  'ja': 'Japanese',
  'ko': 'Korean',
};

/// One downloadable subtitle file from a search.
class OnlineSubtitle {
  const OnlineSubtitle({
    required this.fileId,
    required this.name,
    required this.language,
    required this.downloads,
    required this.hashMatch,
  });

  final int fileId;

  /// Release name, or the file name when there is none.
  final String name;
  final String language;
  final int downloads;

  /// Made for this exact video file, so its timing should already fit.
  final bool hashMatch;
}

/// Size plus the sum of the first and last 64 KB as little-endian 64-bit
/// words, as 16 hex digits. Null for files under 128 KB.
Future<String?> movieHash(File file) async {
  const chunk = 65536;
  final size = await file.length();
  if (size < chunk * 2) return null;
  final raf = await file.open();
  try {
    final head = await raf.read(chunk);
    await raf.setPosition(size - chunk);
    final tail = await raf.read(chunk);
    var h = size;
    for (final bytes in [head, tail]) {
      final words = bytes.buffer.asByteData(bytes.offsetInBytes, bytes.length);
      for (var i = 0; i < chunk; i += 8) {
        // Wraps around at 64 bits, which is what the hash wants.
        h += words.getUint64(i, Endian.little);
      }
    }
    // Two 32-bit halves, since a 64-bit int prints as signed.
    return (h >>> 32).toRadixString(16).padLeft(8, '0') +
        (h & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
  } finally {
    await raf.close();
  }
}

final _junk = RegExp(
    r'\b(2160p|1080p|720p|480p|4k|uhd|hdr|x264|x265|h264|h265|hevc|web-?dl|webrip|'
    r'bluray|brrip|bdrip|dvdrip|hdtv|hdrip|aac|ac3|ddp?5\.1|10bit|proper|repack|'
    r'extended|unrated|yify|rarbg)\b.*$',
    caseSensitive: false);

/// A search phrase from a file name: "The.Movie.2019.1080p.WEB.mkv" ->
/// "The Movie 2019", "Show_S01E02_720p.mp4" -> "Show S01E02".
String searchQueryFor(String fileName) {
  var s = fileName;
  final dot = s.lastIndexOf('.');
  if (dot > 0 && s.length - dot <= 5) s = s.substring(0, dot);
  s = s.replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)'), ' ');
  s = s.replaceAll(RegExp(r'[._]+'), ' ');
  final year = RegExp(r'\b(19|20)\d{2}\b').firstMatch(s);
  final episode = RegExp(r'\bS\d{1,2}E\d{1,3}\b', caseSensitive: false).firstMatch(s);
  final cut = episode ?? year;
  if (cut != null) s = s.substring(0, cut.end);
  s = s.replaceFirst(_junk, '');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Search results from the API's JSON, best first: exact file matches,
/// then the most downloaded.
List<OnlineSubtitle> parseSearch(Map<String, Object?> json) {
  final out = <OnlineSubtitle>[];
  for (final item in (json['data'] as List? ?? const []).whereType<Map>()) {
    final a = (item['attributes'] as Map?) ?? const {};
    final files = (a['files'] as List? ?? const []).whereType<Map>();
    for (final f in files) {
      final id = f['file_id'];
      if (id is! num) continue;
      final release = (a['release'] as String?)?.trim() ?? '';
      out.add(OnlineSubtitle(
        fileId: id.toInt(),
        name: release.isNotEmpty ? release : (f['file_name'] as String? ?? 'Subtitle'),
        language: a['language'] as String? ?? '',
        downloads: (a['download_count'] as num?)?.toInt() ?? 0,
        hashMatch: a['moviehash_match'] == true,
      ));
      break; // The first file is the subtitle; others are extra CDs.
    }
  }
  out.sort((x, y) {
    if (x.hashMatch != y.hashMatch) return x.hashMatch ? -1 : 1;
    return y.downloads.compareTo(x.downloads);
  });
  return out;
}

/// Something the user should read, e.g. the daily download limit.
class SubtitleServiceException implements Exception {
  const SubtitleServiceException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A signed-in session: the token and the server the service assigned.
class SubtitleLogin {
  const SubtitleLogin(this.token, this.host, this.allowedDownloads);
  final String token;
  final String host;
  final int? allowedDownloads;
}

/// Reads the login reply; null when it has no token.
SubtitleLogin? parseLogin(Map<String, Object?> json) {
  final token = json['token'];
  if (token is! String || token.isEmpty) return null;
  var host = json['base_url'] as String? ?? _host;
  host = host.replaceFirst(RegExp(r'^https?://'), '').split('/').first;
  if (host.isEmpty) host = _host;
  final user = json['user'] as Map?;
  return SubtitleLogin(token, host, (user?['allowed_downloads'] as num?)?.toInt());
}

class OnlineSubtitles {
  OnlineSubtitles({HttpClient? client, this.token, String? host})
      : _client = client ?? HttpClient(),
        host = host ?? _host;
  final HttpClient _client;

  /// Signed-in token, if any, and the server to use with it.
  final String? token;
  final String host;

  /// Signs in with the user's own account. Throws
  /// [SubtitleServiceException] with a readable message on failure.
  Future<SubtitleLogin> login(String username, String password) async {
    final json = await _send('POST', Uri.https(_host, '/api/v1/login'),
        {'username': username, 'password': password});
    final login = parseLogin(json);
    if (login == null) throw const SubtitleServiceException('Sign-in failed.');
    return login;
  }

  Future<void> logout() async {
    if (token == null) return;
    try {
      await _send('DELETE', Uri.https(host, '/api/v1/logout'));
    } catch (_) {}
  }

  Future<Map<String, Object?>> _send(String method, Uri uri, [Object? body]) async {
    final req = await _client.openUrl(method, uri).timeout(const Duration(seconds: 20));
    req.headers
      ..set('Api-Key', openSubtitlesKey)
      ..set(HttpHeaders.userAgentHeader, _userAgent)
      ..set(HttpHeaders.acceptHeader, 'application/json');
    if (token != null) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close().timeout(const Duration(seconds: 30));
    final text = await res.transform(utf8.decoder).join();
    Object? json;
    try {
      json = jsonDecode(text);
    } catch (_) {}
    final map = json is Map ? json.cast<String, Object?>() : <String, Object?>{};
    if (res.statusCode >= 400) {
      final msg = map['message'] ?? map['errors']?.toString();
      throw SubtitleServiceException(switch (res.statusCode) {
        401 when uri.path.endsWith('/login') => 'Wrong username or password.',
        401 => 'Your subtitle sign-in has expired. Sign in again in Settings.',
        406 || 429 => token == null
            ? 'Daily download limit reached. Sign in with a free account in '
                'Settings for more, or try again tomorrow.'
            : 'Daily download limit reached. Try again tomorrow.',
        _ => 'Subtitle service error (${msg ?? res.statusCode}).',
      });
    }
    return map;
  }

  /// Searches by the video's hash (when known) and by [query].
  Future<List<OnlineSubtitle>> search({
    required String query,
    required String language,
    String? hash,
  }) async {
    // The API wants parameters sorted and lower case, or it redirects.
    final params = <String, String>{
      'languages': language.toLowerCase(),
      if (hash != null) 'moviehash': hash,
      if (query.isNotEmpty) 'query': query.toLowerCase(),
    };
    final sorted = Map.fromEntries(
        params.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
    final json = await _send('GET', Uri.https(host, '/api/v1/subtitles', sorted));
    return parseSearch(json);
  }

  /// Downloads [s] into the app's own storage and returns the file path.
  Future<String> download(OnlineSubtitle s, String videoTitle) async {
    final json = await _send('POST', Uri.https(host, '/api/v1/download'),
        {'file_id': s.fileId, 'sub_format': 'srt'});
    final link = json['link'] as String?;
    if (link == null) {
      throw SubtitleServiceException(
          json['message'] as String? ?? 'This subtitle could not be downloaded.');
    }
    final req = await _client.getUrl(Uri.parse(link)).timeout(const Duration(seconds: 20));
    final res = await req.close().timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      throw SubtitleServiceException('Download failed (${res.statusCode}).');
    }
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/subtitles');
    await dir.create(recursive: true);
    final safe = videoTitle.replaceAll(RegExp(r'[^\w\- ]+'), '_');
    final file = File('${dir.path}/$safe.${s.language}.${s.fileId}.srt');
    await res.pipe(file.openWrite());
    return file.path;
  }
}
