import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_app/src/captions/opensubtitles.dart';
import 'package:video_player_app/src/settings.dart';

void main() {
  group('movie hash', () {
    test('matches an independent implementation', () {
      final head = Uint8List.fromList(
          [for (var i = 0; i < 65536; i++) (i * 7 + 3) % 256]);
      final tail = Uint8List.fromList(
          [for (var i = 0; i < 65536; i++) (i * 13 + 255) % 256]);
      expect(movieHashOf(12909756, head, tail), '5fe05fdf60a53cbc');
    });

    test('wraps around 64 bits', () {
      final ones = Uint8List(65536)..fillRange(0, 65536, 255);
      expect(movieHashOf(70000, ones, ones), '000000000000d170');
    });
  });

  group('caption query from a file name', () {
    test('movie with year and release tags', () {
      final q = CaptionQuery.fromFileName(
          'The.Dark.Knight.2008.1080p.BluRay.x264-YTS.mkv');
      expect(q.title, 'The Dark Knight');
      expect(q.year, 2008);
      expect(q.season, isNull);
    });

    test('show episode', () {
      final q = CaptionQuery.fromFileName('Mirzapur_S02E05_720p_WEB-DL.mp4');
      expect(q.title, 'Mirzapur');
      expect(q.season, 2);
      expect(q.episode, 5);
    });

    test('1x05 style and plain names', () {
      expect(CaptionQuery.fromFileName('Friends 1x05.avi').episode, 5);
      expect(CaptionQuery.fromFileName('holiday video.mp4').title,
          'holiday video');
      expect(CaptionQuery.fromFileName('2012.mkv').title, '2012');
    });
  });

  test('results put exact file matches first, then popular ones', () {
    Map<String, Object?> item(int id, int downloads, bool exact) => {
          'attributes': {
            'language': 'en',
            'release': 'r$id',
            'download_count': downloads,
            'moviehash_match': exact,
            'files': [
              {'file_id': id, 'file_name': 'f$id.srt'}
            ],
          }
        };
    final r = CaptionResult.listFromJson({
      'data': [
        item(1, 900, false),
        item(2, 5, true),
        item(3, 2000, false),
        {'bad': 1}
      ],
    });
    expect([for (final x in r) x.fileId], [2, 3, 1]);
    expect(r.first.exactMatch, isTrue);
  });

  test('search without an API key explains instead of calling out', () async {
    final api = OpenSubtitles(apiKey: '');
    expect(api.available, isFalse);
    expect(
        () => api
            .search(query: const CaptionQuery(title: 'x'), languages: ['en']),
        throwsA(isA<CaptionException>()));
  });

  test('downloaded captions and languages are remembered', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await Settings.open();
    expect(s.captionLanguages, ['en']);
    s.setCaptionLanguages(['en', 'hi']);
    s.setCaption('video1', '/data/captions/1-en.srt');
    final again = await Settings.open();
    expect(again.captionLanguages, ['en', 'hi']);
    expect(again.captionFor('video1'), '/data/captions/1-en.srt');
    again.setCaption('video1', null);
    expect((await Settings.open()).captionFor('video1'), isNull);
  });

  test('a caption sign-in is remembered without the password', () async {
    SharedPreferences.setMockInitialValues({'osKey': 'old'});
    final s = await Settings.open();
    expect(s.captionAccount, isNull);
    s.setCaptionAccount(const CaptionAccount(
        user: 'rahul', token: 'tok', host: 'vip-api.opensubtitles.com'));
    final again = await Settings.open();
    expect(again.captionAccount?.user, 'rahul');
    expect(again.captionAccount?.token, 'tok');
    expect(again.captionAccount?.host, 'vip-api.opensubtitles.com');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.startsWith('os')),
        {'osToken', 'osUser', 'osHost'});
    again.setCaptionAccount(null);
    expect((await Settings.open()).captionAccount, isNull);
  });

  group('sign-in', () {
    late HttpServer server;
    late List<HttpRequest> seen;
    late List<String> hosts;
    late int status;
    late Map<String, Object?> reply;

    setUp(() async {
      seen = [];
      hosts = [];
      status = 200;
      reply = {};
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        seen.add(req);
        await utf8.decoder.bind(req).join();
        req.response.statusCode = status;
        req.response.write(jsonEncode(reply));
        await req.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    /// Sends every request to the local server instead of OpenSubtitles,
    /// noting which server it was meant for.
    OpenSubtitles api({CaptionAccount? account}) => OpenSubtitles(
        apiKey: 'k',
        account: account,
        uri: (host, path, [query]) {
          hosts.add(host);
          return Uri.http('127.0.0.1:${server.port}', path, query);
        });

    test('keeps the token and the server it was given', () async {
      reply = {'token': 'abc', 'base_url': 'vip-api.opensubtitles.com'};
      final a = await api().signIn(' rahul ', 'pw');
      expect(a.user, 'rahul');
      expect(a.token, 'abc');
      expect(a.host, 'vip-api.opensubtitles.com');
      expect(seen.single.uri.path, '/api/v1/login');
      expect(hosts.single, 'api.opensubtitles.com');
      expect(seen.single.headers.value('Api-Key'), 'k');
      expect(
          seen.single.headers.value(HttpHeaders.authorizationHeader), isNull);
    });

    test('a strange server name falls back to the main one', () async {
      reply = {'token': 'abc', 'base_url': 'evil.example.com'};
      final a = await api().signIn('r', 'pw');
      expect(a.host, 'api.opensubtitles.com');
    });

    test('wrong password says so', () async {
      status = 401;
      expect(
          api().signIn('r', 'bad'),
          throwsA(isA<CaptionException>()
              .having((e) => e.message, 'message', contains('password'))));
    });

    test('signed-in searches carry the token', () async {
      reply = {'data': []};
      final signedIn = api(
          account: const CaptionAccount(
              user: 'r', token: 'tok', host: 'vip-api.opensubtitles.com'));
      await signedIn
          .search(query: const CaptionQuery(title: 'x'), languages: ['en']);
      expect(seen.single.headers.value(HttpHeaders.authorizationHeader),
          'Bearer tok');
      expect(hosts.single, 'vip-api.opensubtitles.com');
    });

    test('used-up downloads suggest signing in only when signed out', () async {
      status = 406;
      expect(
          api()
              .search(query: const CaptionQuery(title: 'x'), languages: ['en']),
          throwsA(isA<CaptionException>()
              .having((e) => e.message, 'message', contains('Sign in'))));
      final signedIn =
          api(account: const CaptionAccount(user: 'r', token: 't'));
      expect(
          signedIn
              .search(query: const CaptionQuery(title: 'x'), languages: ['en']),
          throwsA(isA<CaptionException>()
              .having((e) => e.message, 'message', contains('tomorrow'))));
    });
  });
}
