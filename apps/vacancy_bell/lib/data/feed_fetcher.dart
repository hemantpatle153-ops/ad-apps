import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class FetchResponse {
  const FetchResponse(this.status, {this.body, this.etag});
  final int status;
  final String? body;
  final String? etag;
}

/// No connection, DNS failure, timeout: the request never got an answer.
class FeedNetworkException implements Exception {
  const FeedNetworkException(this.cause);
  final Object cause;
  @override
  String toString() => 'FeedNetworkException($cause)';
}

/// Downloads feed files. [HttpFeedFetcher] is the real one; tests use fakes.
abstract class FeedFetcher {
  /// GETs [path] below the feed base URL. With [etag] the request is
  /// conditional and may answer 304. Throws [FeedNetworkException].
  Future<FetchResponse> get(String path, {String? etag});
}

class HttpFeedFetcher implements FeedFetcher {
  HttpFeedFetcher(this.baseUrl, {http.Client? client, this.timeout = const Duration(seconds: 20)})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  final Duration timeout;

  /// Feed files are small; anything bigger is not ours.
  static const maxBytes = 8 * 1024 * 1024;

  Uri uriFor(String path) {
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return Uri.parse(base).resolve(path);
  }

  @override
  Future<FetchResponse> get(String path, {String? etag}) async {
    try {
      final res = await _client.get(uriFor(path), headers: {
        'Accept': 'application/json',
        if (etag != null) 'If-None-Match': etag,
      }).timeout(timeout);
      if (res.bodyBytes.length > maxBytes) {
        return const FetchResponse(413);
      }
      return FetchResponse(
        res.statusCode,
        body: res.statusCode == 200 ? utf8.decode(res.bodyBytes, allowMalformed: true) : null,
        etag: res.headers['etag'],
      );
    } on SocketException catch (e) {
      throw FeedNetworkException(e);
    } on TimeoutException catch (e) {
      throw FeedNetworkException(e);
    } on http.ClientException catch (e) {
      throw FeedNetworkException(e);
    } on HandshakeException catch (e) {
      throw FeedNetworkException(e);
    }
  }
}
