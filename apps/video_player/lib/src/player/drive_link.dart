import 'dart:convert';
import 'dart:io';

/// Google Drive share links, so a watch party can stream a video one friend
/// put in their Drive. The file must be shared as "Anyone with the link".
/// Same rules as web_party/sync.js.

final _idPattern = RegExp(r'^[A-Za-z0-9_-]{10,}$');

/// The file id in a Drive link, or null if it isn't one. Accepts
/// `drive.google.com/file/d/ID/view`, `open?id=ID`, `uc?id=ID` and
/// `drive.usercontent.google.com/download?id=ID`.
String? driveFileId(String link) {
  final u = Uri.tryParse(link.trim());
  if (u == null || !u.hasScheme) return null;
  final host = u.host.toLowerCase();
  if (host != 'drive.google.com' && host != 'docs.google.com' &&
      host != 'drive.usercontent.google.com') {
    return null;
  }
  String? id;
  final seg = u.pathSegments;
  final d = seg.indexOf('d');
  if (seg.contains('file') && d >= 0 && d + 1 < seg.length) id = seg[d + 1];
  id ??= u.queryParameters['id'];
  return id != null && _idPattern.hasMatch(id) ? id : null;
}

/// A direct address the player can stream and seek, skipping Drive's
/// "can't scan this file for viruses" page on big files.
String driveStreamUrl(String id) =>
    'https://drive.usercontent.google.com/download?id=$id&export=download&confirm=t';

/// Drive links become their stream address; other links stay as they are.
String streamUrlFor(String link) {
  final id = driveFileId(link);
  return id == null ? link : driveStreamUrl(id);
}

/// The file's name from its Drive page title ("Name - Google Drive"), or
/// null when Drive doesn't answer (not shared, offline).
Future<String?> driveFileName(String id) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  try {
    final req = await client
        .getUrl(Uri.parse('https://drive.google.com/file/d/$id/view'));
    final res = await req.close().timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final html = await res
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 8));
    return driveTitleFromHtml(html);
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

String? driveTitleFromHtml(String html) {
  final m = RegExp(r'<title>([^<]*)</title>').firstMatch(html);
  if (m == null) return null;
  var t = _unescape(m.group(1)!).trim();
  const suffix = ' - Google Drive';
  if (!t.endsWith(suffix)) return null; // the sign-in page: not shared
  t = t.substring(0, t.length - suffix.length).trim();
  return t.isEmpty ? null : t;
}

String _unescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&#39;', "'")
    .replaceAll('&quot;', '"')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>');
