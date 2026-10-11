import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

enum FeedErrorKind { offline, notFound, server, badData }

class FeedException implements Exception {
  const FeedException(this.kind, [this.detail]);
  final FeedErrorKind kind;
  final String? detail;

  @override
  String toString() => 'FeedException($kind${detail == null ? '' : ', $detail'})';
}

/// Reads one feed file as text.
abstract class FeedClient {
  Future<String> get(String path);
}

/// Feed files from the published branch over HTTPS.
class HttpFeedClient implements FeedClient {
  HttpFeedClient(this.baseUrl, {http.Client? client, this.timeout = const Duration(seconds: 15)})
      : _client = client ?? http.Client();

  final String baseUrl;
  final Duration timeout;
  final http.Client _client;

  /// Feed files are small; anything bigger is not ours.
  static const maxBytes = 8 * 1024 * 1024;

  static final _safePath = RegExp(r'^[a-z0-9_./-]+\.json$');

  Uri uriFor(String path) {
    if (!_safePath.hasMatch(path) || path.contains('..')) {
      throw FeedException(FeedErrorKind.badData, 'bad path $path');
    }
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return Uri.parse(base).resolve(path);
  }

  @override
  Future<String> get(String path) async {
    final uri = uriFor(path);
    final http.Response res;
    try {
      res = await _client.get(uri).timeout(timeout);
    } on TimeoutException {
      throw const FeedException(FeedErrorKind.offline, 'timeout');
    } on SocketException catch (e) {
      throw FeedException(FeedErrorKind.offline, e.message);
    } on http.ClientException catch (e) {
      throw FeedException(FeedErrorKind.offline, e.message);
    } on HandshakeException catch (e) {
      throw FeedException(FeedErrorKind.offline, e.message);
    }
    if (res.statusCode == 404) throw const FeedException(FeedErrorKind.notFound);
    if (res.statusCode != 200) {
      throw FeedException(FeedErrorKind.server, 'HTTP ${res.statusCode}');
    }
    if (res.bodyBytes.length > maxBytes) {
      throw const FeedException(FeedErrorKind.badData, 'too large');
    }
    try {
      return utf8.decode(res.bodyBytes);
    } on FormatException {
      throw const FeedException(FeedErrorKind.badData, 'not utf-8');
    }
  }
}
