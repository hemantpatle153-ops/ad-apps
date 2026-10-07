import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_app/src/party/party.dart';
import 'package:video_player_app/src/party/protocol.dart';

/// Talks to a [PartyHost] over a real WebSocket on localhost.
class _Client {
  _Client(this.ws) {
    ws.listen((d) {
      final m = decodeMessage(d);
      if (m == null) return;
      inbox.add(m);
      if (!_arrived.isClosed) _arrived.add(m);
    });
  }

  static Future<_Client> connect(int port) async =>
      _Client(await WebSocket.connect('ws://127.0.0.1:$port/ws'));

  final WebSocket ws;
  final inbox = <Map<String, Object?>>[];
  final _arrived = StreamController<Map<String, Object?>>.broadcast();

  void send(String type, [Map<String, Object?> body = const {}]) =>
      ws.add(encodeMessage(type, body));

  /// Next message of [type], including one that already arrived.
  Future<Map<String, Object?>> next(String type, {bool Function(Map<String, Object?>)? where}) {
    bool ok(Map<String, Object?> m) => m['t'] == type && (where?.call(m) ?? true);
    for (final m in inbox) {
      if (ok(m)) {
        inbox.remove(m);
        return Future.value(m);
      }
    }
    return _arrived.stream.firstWhere(ok).then((m) {
      inbox.remove(m);
      return m;
    }).timeout(const Duration(seconds: 5));
  }

  Future<void> close() async {
    await ws.close();
    await _arrived.close();
  }
}

Future<void> _until(bool Function() cond) async {
  for (var i = 0; i < 250 && !cond(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(cond(), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding replaces HttpClient with a mock; these tests talk to a
  // real local server.
  HttpOverrides.global = null;

  late Directory dir;
  late File video;
  final bytes = List<int>.generate(100000, (i) => (i * 31 + 7) % 256);

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('vparty_test');
    video = File('${dir.path}/movie.mp4')..writeAsBytesSync(bytes);
  });
  tearDownAll(() => dir.delete(recursive: true));

  group('PartyHost HTTP video', () {
    late PartyHost host;
    late HttpClient http;
    setUpAll(() async {
      host = PartyHost('Host', video: const PartyVideo(title: 'movie.mp4'), filePath: video.path);
      await host.start();
      http = HttpClient();
    });
    tearDownAll(() async {
      http.close(force: true);
      await host.close();
      host.dispose();
    });

    Future<(HttpClientResponse, List<int>)> get(String path,
        {String? range, String method = 'GET'}) async {
      final req = await http.openUrl(method, Uri.parse('http://127.0.0.1:${host.port}$path'));
      if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
      final res = await req.close();
      final body = <int>[];
      await res.forEach(body.addAll);
      return (res, body);
    }

    test('start fills members, port and join code', () {
      expect(host.isHost, isTrue);
      expect(host.members, ['Host']);
      expect(host.port, greaterThan(0));
      expect(host.joinCode.port, host.port);
      expect(host.joinCode.name, 'Host');
      expect(host.joinCode.hosts, host.addresses);
      expect(host.guestCount, 0);
    });

    test('whole file without a range', () async {
      final (res, body) = await get('/video');
      expect(res.statusCode, 200);
      expect(res.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
      expect(res.headers.contentType?.mimeType, 'video/mp4');
      expect(res.contentLength, bytes.length);
      expect(body, bytes);
    });

    test('HEAD sends headers only', () async {
      final (res, body) = await get('/video', method: 'HEAD');
      expect(res.statusCode, 200);
      expect(res.contentLength, bytes.length);
      expect(body, isEmpty);
    });

    final ranges = <String, (int, int)>{
      'bytes=0-0': (0, 0),
      'bytes=0-1023': (0, 1023),
      'bytes=50000-': (50000, 99999),
      'bytes=-500': (99500, 99999),
      'bytes=99999-': (99999, 99999),
      'bytes=12345-23456': (12345, 23456),
      'bytes=90000-200000': (90000, 99999),
    };
    ranges.forEach((header, r) {
      test('range "$header" -> 206 bytes ${r.$1}-${r.$2}', () async {
        final (res, body) = await get('/video', range: header);
        expect(res.statusCode, 206);
        expect(res.headers.value(HttpHeaders.contentRangeHeader),
            'bytes ${r.$1}-${r.$2}/${bytes.length}');
        expect(res.contentLength, r.$2 - r.$1 + 1);
        expect(body, bytes.sublist(r.$1, r.$2 + 1));
      });
    });

    test('HEAD with range sends 206 headers only', () async {
      final (res, body) = await get('/video', range: 'bytes=10-19', method: 'HEAD');
      expect(res.statusCode, 206);
      expect(res.contentLength, 10);
      expect(body, isEmpty);
    });

    for (final header in ['bytes=100000-', 'bytes=5-1', 'bytes=1-2,4-5', 'lines=1-2']) {
      test('unusable range "$header" sends the whole file', () async {
        final (res, body) = await get('/video', range: header);
        expect(res.statusCode, 200);
        expect(body.length, bytes.length);
      });
    }

    for (final path in ['/', '/ws', '/video.mp4', '/other']) {
      test('$path is 404', () async {
        final (res, _) = await get(path);
        expect(res.statusCode, 404);
      });
    }
  });

  group('PartyHost content types', () {
    final types = {
      'mkv': 'video/x-matroska',
      'MKV': 'video/x-matroska',
      'webm': 'video/webm',
      'avi': 'video/x-msvideo',
      '3gp': 'video/3gpp',
      'mov': 'video/quicktime',
      'ts': 'video/mp2t',
      'mp4': 'video/mp4',
      'm4v': 'video/mp4',
    };
    types.forEach((ext, mime) {
      test('.$ext served as $mime', () async {
        final f = File('${dir.path}/clip.$ext')..writeAsBytesSync([1, 2, 3]);
        final host = PartyHost('H', video: const PartyVideo(title: 'c'), filePath: f.path);
        await host.start();
        final http = HttpClient();
        try {
          final res = await (await http.getUrl(
                  Uri.parse('http://127.0.0.1:${host.port}/video')))
              .close();
          await res.drain<void>();
          expect(res.headers.contentType?.mimeType, mime);
        } finally {
          http.close(force: true);
          await host.close();
          host.dispose();
        }
      });
    });

    test('link party has no /video', () async {
      final host = PartyHost('H', video: const PartyVideo(title: 'L', url: 'https://x/y.mp4'));
      await host.start();
      final http = HttpClient();
      try {
        final res = await (await http.getUrl(
                Uri.parse('http://127.0.0.1:${host.port}/video')))
            .close();
        await res.drain<void>();
        expect(res.statusCode, 404);
      } finally {
        http.close(force: true);
        await host.close();
        host.dispose();
      }
    });
  });

  group('PartyHost WebSocket protocol', () {
    late PartyHost host;
    setUp(() async {
      host = PartyHost('Host', video: const PartyVideo(title: 'movie.mp4'), filePath: video.path);
      await host.start();
    });
    tearDown(() async {
      await host.close();
      host.dispose();
    });

    test('ping is answered with the same c and a host time', () async {
      final c = await _Client.connect(host.port);
      c.send('ping', {'c': 4242});
      final pong = await c.next('pong');
      expect(pong['c'], 4242);
      expect(pong['h'], isA<int>());
      await c.close();
    });

    test('hi gets welcome with video and state, and members', () async {
      final c = await _Client.connect(host.port);
      c.send('hi', {'name': 'Asha', 'v': partyProtocol});
      final w = await c.next('welcome');
      expect(w['video'], {'title': 'movie.mp4', 'url': null});
      expect(PartyState.fromJson((w['state'] as Map).cast()).playing, isFalse);
      final m = await c.next('members');
      expect(m['names'], ['Host', 'Asha']);
      await _until(() => host.members.length == 2);
      expect(host.guestCount, 1);
      expect(host.messages.last.from, 'Asha');
      expect(host.messages.last.text, 'joined');
      await c.close();
    });

    test('hi without a name is "Friend"', () async {
      final c = await _Client.connect(host.port);
      c.send('hi');
      final m = await c.next('members');
      expect(m['names'], ['Host', 'Friend']);
      await c.close();
    });

    test('chat and reactions go to others but not back to the sender', () async {
      final a = await _Client.connect(host.port);
      a.send('hi', {'name': 'A'});
      await a.next('welcome');
      final b = await _Client.connect(host.port);
      b.send('hi', {'name': 'B'});
      await b.next('welcome');
      final joined = await a.next('chat');
      expect(joined, {'t': 'chat', 'from': 'B', 'text': 'joined'});

      a.send('chat', {'text': '  hello  '});
      final got = await b.next('chat', where: (m) => m['text'] != 'joined');
      expect(got['from'], 'A');
      expect(got['text'], 'hello');

      b.send('react', {'e': '🎉'});
      final r = await a.next('react');
      expect(r['from'], 'B');
      expect(r['e'], '🎉');

      await _until(() => host.messages.any((m) => m.emoji));
      final texts = host.messages.map((m) => '${m.from}:${m.text}:${m.emoji}').toList();
      expect(texts, containsAll(['A:hello:false', 'B:🎉:true']));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(a.inbox.where((m) => m['t'] == 'chat' && m['from'] == 'A'), isEmpty);
      expect(b.inbox.where((m) => m['t'] == 'react'), isEmpty);
      await a.close();
      await b.close();
    });

    test('blank chat and empty reaction are dropped', () async {
      final c = await _Client.connect(host.port);
      c.send('hi', {'name': 'C'});
      await c.next('welcome');
      final before = host.messages.length;
      c.send('chat', {'text': '   '});
      c.send('chat');
      c.send('react', {'e': ''});
      c.send('nonsense', {'x': 1});
      c.ws.add('not json at all');
      c.send('ping', {'c': 1});
      await c.next('pong');
      expect(host.messages.length, before);
      await c.close();
    });

    test('host chat and reactions are broadcast', () async {
      final c = await _Client.connect(host.port);
      c.send('hi', {'name': 'C'});
      await c.next('welcome');
      await _until(() => host.guestCount == 1);
      host.sendChat('  hi all ');
      host.sendChat('   ');
      host.sendReaction('❤️');
      expect((await c.next('chat', where: (m) => m['from'] == 'Host'))['text'], 'hi all');
      expect((await c.next('react'))['e'], '❤️');
      expect(host.messages.where((m) => m.from == 'Host').length, 2);
      await c.close();
    });

    test('a guest leaving updates members and logs "left"', () async {
      final a = await _Client.connect(host.port);
      a.send('hi', {'name': 'A'});
      await a.next('welcome');
      final b = await _Client.connect(host.port);
      b.send('hi', {'name': 'B'});
      await b.next('welcome');
      await _until(() => host.guestCount == 2);
      await b.close();
      await _until(() => host.guestCount == 1);
      expect(host.members, ['Host', 'A']);
      expect(host.messages.last.text, 'left');
      expect(host.messages.last.from, 'B');
      final m = await a.next('members', where: (m) => (m['names'] as List).length == 2);
      expect(m['names'], ['Host', 'A']);
      await a.close();
    });

    test('requests without a player are ignored', () async {
      final c = await _Client.connect(host.port);
      c.send('req', {'a': 'play'});
      c.send('req', {'a': 'seek', 'v': 1000});
      c.send('ping', {'c': 2});
      await c.next('pong');
      expect(host.state.playing, isFalse);
      await c.close();
    });

    test('close says bye to guests', () async {
      final c = await _Client.connect(host.port);
      c.send('hi', {'name': 'C'});
      await c.next('welcome');
      await _until(() => host.guestCount == 1);
      await host.close();
      expect(await c.next('bye'), {'t': 'bye'});
      await c.close();
    });

    test('incoming stream fires for messages', () async {
      final seen = <String>[];
      final sub = host.incoming.listen((m) => seen.add(m.text));
      host.sendChat('one');
      host.sendReaction('👍');
      await Future<void>.delayed(Duration.zero);
      expect(seen, ['one', '👍']);
      await sub.cancel();
    });

    test('message log keeps the last 200', () {
      for (var i = 0; i < 250; i++) {
        host.sendChat('m$i');
      }
      expect(host.messages.length, 200);
      expect(host.messages.first.text, 'm50');
      expect(host.messages.last.text, 'm249');
    });
  });

  group('PartyGuest with a real host', () {
    late PartyHost host;
    setUp(() async {
      host = PartyHost('Host', video: const PartyVideo(title: 'movie.mp4'), filePath: video.path);
      await host.start();
    });
    tearDown(() async {
      await host.close();
      host.dispose();
    });

    test('connects, gets the video and members, learns the clock', () async {
      final g = PartyGuest('Ravi', JoinCode(hosts: const ['127.0.0.1'], port: host.port, name: 'Host'));
      expect(g.isHost, isFalse);
      expect(g.status, GuestStatus.connecting);
      expect(await g.connect(), isTrue);
      expect(g.status, GuestStatus.connected);
      expect(g.hostAddress, '127.0.0.1');
      expect(g.video?.title, 'movie.mp4');
      expect(g.videoUri, 'http://127.0.0.1:${host.port}/video');
      await _until(() => g.members.length == 2);
      expect(g.members, ['Host', 'Ravi']);
      await _until(() => g.clock.hasEstimate);
      // Same machine, same steady clock, so the true offset is 0. The
      // estimate is the median of the three fastest samples, whose round
      // trips can be well above bestRttUs on a busy CI runner; allow 100 ms.
      expect(g.clock.offsetUs.abs(), lessThan(100 * 1000));
      expect((g.hostNowUs() - DateTime.now().microsecondsSinceEpoch).abs(),
          lessThan(60 * 1000000));
      await g.close();
      g.dispose();
    });

    test('skips dead addresses and uses the next one', () async {
      final g = PartyGuest('Ravi',
          JoinCode(hosts: const ['127.0.0.2', '127.0.0.1'], port: host.port, name: 'Host'));
      expect(await g.connect(), isTrue);
      expect(g.hostAddress, anyOf('127.0.0.1', '127.0.0.2'));
      await g.close();
      g.dispose();
    });

    test('chat both ways', () async {
      final g = PartyGuest('Ravi', JoinCode(hosts: const ['127.0.0.1'], port: host.port, name: 'Host'));
      await g.connect();
      await _until(() => host.guestCount == 1);
      g.sendChat('  namaste ');
      g.sendChat('  ');
      g.sendReaction('🔥');
      await _until(() => host.messages.any((m) => m.text == '🔥'));
      expect(host.messages.any((m) => m.from == 'Ravi' && m.text == 'namaste'), isTrue);
      host.sendChat('welcome Ravi');
      host.sendReaction('😀');
      await _until(() => g.messages.any((m) => m.text == '😀'));
      final log = g.messages.map((m) => '${m.from}:${m.text}:${m.emoji}').toList();
      expect(log, containsAllInOrder(
          ['Ravi:namaste:false', 'Ravi:🔥:true', 'Host:welcome Ravi:false', 'Host:😀:true']));
      await g.close();
      g.dispose();
    });

    test('a link party gives the link as the video uri', () async {
      final linkHost = PartyHost('L', video: const PartyVideo(title: 'Live', url: 'https://cdn/x.m3u8'));
      await linkHost.start();
      final g = PartyGuest('G', JoinCode(hosts: const ['127.0.0.1'], port: linkHost.port, name: 'L'));
      expect(await g.connect(), isTrue);
      expect(g.videoUri, 'https://cdn/x.m3u8');
      await g.close();
      g.dispose();
      await linkHost.close();
      linkHost.dispose();
    });

    test('host closing ends the guest with a reason', () async {
      final g = PartyGuest('Ravi', JoinCode(hosts: const ['127.0.0.1'], port: host.port, name: 'Host'));
      await g.connect();
      await _until(() => host.guestCount == 1);
      await host.close();
      await _until(() => g.status == GuestStatus.ended);
      expect(g.endedReason, 'The host ended the watch party');
      g.dispose();
    });

    test('guest requests reach the host without a player harmlessly', () async {
      final g = PartyGuest('Ravi', JoinCode(hosts: const ['127.0.0.1'], port: host.port, name: 'Host'));
      await g.connect();
      await g.requestPlay();
      await g.requestPause();
      await g.requestSeek(const Duration(seconds: 3));
      await g.requestRate(1.5);
      g.sendChat('still here');
      await _until(() => host.messages.any((m) => m.text == 'still here'));
      expect(host.state.playing, isFalse);
      await g.close();
      g.dispose();
    });
  });

  group('PartyGuest without a host', () {
    test('no listening address -> failed', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close();
      final g = PartyGuest('G', JoinCode(hosts: const ['127.0.0.1'], port: port, name: 'x'));
      expect(await g.connect(), isFalse);
      expect(g.status, GuestStatus.failed);
      await g.close();
      g.dispose();
    });

    test('close before connect returns false', () async {
      final g = PartyGuest('G', const JoinCode(hosts: ['127.0.0.1'], port: 1, name: 'x'));
      await g.close();
      expect(await g.connect(), isFalse);
      g.dispose();
    });

    test('default video uri points at the host /video', () {
      final g = PartyGuest('G', const JoinCode(hosts: ['10.0.0.5'], port: 47810, name: 'x'))
        ..hostAddress = '10.0.0.5';
      expect(g.videoUri, 'http://10.0.0.5:47810/video');
      g.dispose();
    });

    test('local chat is logged and streamed even offline', () async {
      final g = PartyGuest('G', const JoinCode(hosts: ['10.0.0.5'], port: 1, name: 'x'));
      final seen = <String>[];
      final sub = g.incoming.listen((m) => seen.add('${m.text}/${m.emoji}'));
      g.sendChat('hey');
      g.sendReaction('👏');
      await Future<void>.delayed(Duration.zero);
      expect(seen, ['hey/false', '👏/true']);
      await sub.cancel();
      g.dispose();
    });
  });

}
