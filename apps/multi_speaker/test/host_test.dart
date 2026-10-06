import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:multi_speaker/src/net/party_guest.dart';
import 'package:multi_speaker/src/net/party_host.dart';
import 'package:multi_speaker/src/sync/speaker.dart';
import 'package:multi_speaker/src/sync/clock.dart';
import 'package:multi_speaker/src/sync/protocol.dart';

import 'fake_engine.dart';

void main() {
  late Directory tmp;
  final hosts = <PartyHost>[];

  setUp(() async => tmp = await Directory.systemTemp.createTemp('mshost'));
  tearDown(() async {
    for (final h in hosts) {
      await h.close();
    }
    hosts.clear();
    await tmp.delete(recursive: true);
  });

  PartyHost newHost({String name = 'host'}) {
    final h = PartyHost(engine: FakeEngine(), name: name, speaker: SimpleSpeaker());
    hosts.add(h);
    return h;
  }

  var fileNo = 0;
  Future<String> song({String ext = 'mp3', int size = 100}) async {
    final f = File('${tmp.path}/song${fileNo++}.$ext');
    await f.writeAsBytes(List.filled(size, 3));
    return f.path;
  }

  Future<PartyHost> hostWith(int n) async {
    final h = newHost();
    for (var i = 0; i < n; i++) {
      await h.addTrack(await song(), 'Song $i');
    }
    return h;
  }

  group('adding songs', () {
    const exts = {
      'mp3': 'mp3',
      'MP3': 'mp3',
      'm4a': 'm4a',
      'M4A': 'm4a',
      'Flac': 'flac',
      'ogg': 'ogg',
      'wav': 'wav',
      'opus': 'opus',
      'aac': 'aac',
      'WeBm': 'webm',
    };
    exts.forEach((given, stored) {
      test('a .$given file is served as .$stored', () async {
        final h = newHost();
        await h.addTrack(await song(ext: given), 'x');
        expect(h.playlist.single.ext, stored);
      });
    });
    for (final size in [0, 1, 1000, 123457]) {
      test('a $size-byte file reports size $size', () async {
        final h = newHost();
        await h.addTrack(await song(size: size), 'x');
        expect(h.playlist.single.size, size);
      });
    }
    test('ids are 16 hex digits and all different', () async {
      final h = await hostWith(20);
      final ids = h.playlist.map((t) => t.id).toList();
      for (final id in ids) {
        expect(id, matches(RegExp(r'^[0-9a-f]{16}$')));
      }
      expect(ids.toSet(), hasLength(20));
    });
    test('the first song becomes current, paused at the start', () async {
      final h = await hostWith(3);
      expect(h.current!.title, 'Song 0');
      expect(h.currentIndex, 0);
      expect(h.state.playing, isFalse);
      expect(h.state.positionUs, 0);
    });
    test('titles keep their order', () async {
      final h = await hostWith(6);
      expect(h.playlist.map((t) => t.title), [for (var i = 0; i < 6; i++) 'Song $i']);
    });
    test('adding notifies listeners', () async {
      final h = newHost();
      var n = 0;
      h.addListener(() => n++);
      await h.addTrack(await song(), 'x');
      expect(n, greaterThan(0));
    });
  });

  group('next and previous while paused', () {
    for (var n = 1; n <= 5; n++) {
      for (var i = 0; i < n; i++) {
        test('$n songs, on #$i: next goes to #${min(i + 1, n - 1)}', () async {
          final h = await hostWith(n);
          await h.playTrack(h.playlist[i].id, autoplay: false);
          await h.next();
          expect(h.currentIndex, min(i + 1, n - 1));
          expect(h.state.playing, isFalse);
        });
        test('$n songs, on #$i: previous goes to #${max(i - 1, 0)}', () async {
          final h = await hostWith(n);
          await h.playTrack(h.playlist[i].id, autoplay: false);
          await h.previous();
          expect(h.currentIndex, max(i - 1, 0));
          expect(h.state.positionUs, 0);
          expect(h.state.playing, isFalse);
        });
      }
    }
    for (var n = 1; n <= 4; n++) {
      test('$n songs: the last one ending stops at its start', () async {
        final h = await hostWith(n);
        await h.playTrack(h.playlist.last.id, autoplay: false);
        await h.seek(const Duration(seconds: 20));
        await h.next(fromEnd: true);
        expect(h.currentIndex, n - 1);
        expect(h.state.positionUs, 0);
        expect(h.state.playing, isFalse);
      });
    }
    test('previous more than 3 s into a song goes back to its start', () async {
      final h = await hostWith(3);
      await h.playTrack(h.playlist[2].id, autoplay: false);
      await h.seek(const Duration(seconds: 4));
      await h.previous();
      expect(h.currentIndex, 2);
      expect(h.state.positionUs, 0);
    });
    test('next and previous with no songs do nothing', () async {
      final h = newHost();
      await h.next();
      await h.previous();
      await h.next(fromEnd: true);
      expect(h.state.trackId, isNull);
    });
  });

  group('removing songs', () {
    for (var n = 1; n <= 4; n++) {
      for (var c = 0; c < n; c++) {
        for (var r = 0; r < n; r++) {
          test('$n songs, current #$c, remove #$r', () async {
            final h = await hostWith(n);
            await h.playTrack(h.playlist[c].id, autoplay: false);
            final titles = h.playlist.map((t) => t.title).toList();
            final removed = h.playlist[r];
            final currentTitle = titles[c];
            await h.removeTrack(removed.id);
            titles.removeAt(r);
            expect(h.playlist.map((t) => t.title), titles);
            if (titles.isEmpty) {
              expect(h.state.trackId, isNull);
              expect(h.current, isNull);
            } else if (r == c) {
              expect(h.current!.title, titles[min(r, titles.length - 1)]);
              expect(h.state.positionUs, 0);
            } else {
              expect(h.current!.title, currentTitle);
            }
          });
        }
      }
    }
    test('the removed file is deleted', () async {
      final h = newHost();
      final path = await song();
      await h.addTrack(path, 'x');
      await h.removeTrack(h.playlist.single.id);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(File(path).existsSync(), isFalse);
    });
    test('removing an unknown id changes nothing', () async {
      final h = await hostWith(2);
      await h.removeTrack('nope');
      expect(h.playlist, hasLength(2));
      expect(h.currentIndex, 0);
    });
  });

  group('seek, play and pause', () {
    for (final s in [0, 1, 15, 90, 179]) {
      test('seek to $s s while paused', () async {
        final h = await hostWith(1);
        await h.seek(Duration(seconds: s));
        expect(h.state.positionUs, s * 1000000);
        expect(h.state.playing, isFalse);
        expect(h.position, Duration(seconds: s));
      });
    }
    for (final s in [180, 181, 600]) {
      test('position is capped at the song length when seeking to $s s', () async {
        final h = await hostWith(1);
        await h.seek(Duration(seconds: s));
        expect(h.position, const Duration(minutes: 3));
      });
    }
    test('seek with no song does nothing', () async {
      final h = newHost();
      await h.seek(const Duration(seconds: 5));
      expect(h.state.trackId, isNull);
    });
    test('play schedules the start a moment ahead', () async {
      final h = await hostWith(1);
      final before = Clock.nowUs();
      await h.play();
      expect(h.state.playing, isTrue);
      expect(h.state.positionUs, 0);
      expect(h.state.anchorUs - before,
          inInclusiveRange(PartyHost.startLead.inMicroseconds, PartyHost.startLead.inMicroseconds + 500000));
      expect(h.position, Duration.zero, reason: 'not started yet');
    });
    test('play from a paused spot keeps it', () async {
      final h = await hostWith(1);
      await h.seek(const Duration(seconds: 42));
      await h.play();
      expect(h.state.positionUs, 42000000);
    });
    test('play at the end of the song starts it over', () async {
      final h = await hostWith(1);
      await h.seek(const Duration(minutes: 3));
      await h.play();
      expect(h.state.positionUs, 0);
    });
    test('play with nothing added does nothing', () async {
      final h = newHost();
      await h.play();
      expect(h.state.playing, isFalse);
    });
    test('play twice keeps the first schedule', () async {
      final h = await hostWith(1);
      await h.play();
      final s = h.state;
      await h.play();
      expect(identical(h.state, s), isTrue);
    });
    test('pause while paused changes nothing', () async {
      final h = await hostWith(1);
      final s = h.state;
      await h.pause();
      expect(identical(h.state, s), isTrue);
    });
    test('togglePlay plays then pauses', () async {
      final h = await hostWith(1);
      await h.togglePlay();
      expect(h.state.playing, isTrue);
      await h.togglePlay();
      expect(h.state.playing, isFalse);
    });
    test('seek while playing restarts from there, still playing', () async {
      final h = await hostWith(1);
      await h.play();
      await h.seek(const Duration(seconds: 77));
      expect(h.state.playing, isTrue);
      expect(h.state.positionUs, 77000000);
    });
    test('next while playing plays the next song', () async {
      final h = await hostWith(2);
      await h.play();
      await h.next();
      expect(h.currentIndex, 1);
      expect(h.state.playing, isTrue);
    });
    test('playTrack picks a song and plays it from the start', () async {
      final h = await hostWith(3);
      await h.seek(const Duration(seconds: 9));
      await h.playTrack(h.playlist[2].id);
      expect(h.currentIndex, 2);
      expect(h.state.playing, isTrue);
      expect(h.state.positionUs, 0);
    });
    test('before start the join code has no addresses and the default port', () {
      final h = newHost(name: 'Asha');
      expect(h.joinCode.hosts, isEmpty);
      expect(h.joinCode.port, hostPort);
      expect(h.joinCode.name, 'Asha');
    });
  });

  group('talking to a guest over the network', () {
    late PartyHost host;
    late WebSocket ws;
    late List<Map<String, Object?>> got;

    Future<void> waitFor(bool Function() ok) async {
      final end = DateTime.now().add(const Duration(seconds: 5));
      while (!ok()) {
        if (DateTime.now().isAfter(end)) throw TimeoutException('condition');
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    Iterable<Map<String, Object?>> of(String t) => got.where((m) => m['t'] == t);

    setUp(() async {
      host = newHost(name: 'Party');
      await host.start(beacon: false);
      await host.addTrack(await song(size: 70000), 'First');
      ws = await WebSocket.connect('ws://127.0.0.1:${host.port}/ws');
      got = [];
      ws.listen((d) {
        final m = decodeMessage(d);
        if (m != null) got.add(m);
      });
      await waitFor(() => host.guests.length == 1);
    });
    tearDown(() async => ws.close());

    test('"hi" is answered with the playlist, the state and live mode', () async {
      ws.add(encodeMessage('hi', {'name': 'Kitchen', 'v': protocolVersion}));
      await waitFor(() => of('live').isNotEmpty);
      expect(got.map((m) => m['t']), ['playlist', 'state', 'live']);
      expect(got[2]['on'], isFalse);
      final tracks = (got.first['tracks'] as List).cast<Map<String, Object?>>();
      expect(Track.fromJson(tracks.single).title, 'First');
      expect(PlayState.fromJson(got[1]).trackId, host.state.trackId);
      expect(host.guests.single.name, 'Kitchen');
    });
    test('"hi" without a name is called Phone', () async {
      ws.add(encodeMessage('hi'));
      await waitFor(() => of('state').isNotEmpty);
      expect(host.guests.single.name, 'Phone');
    });
    for (final c in [0, 1, 123456789, 9007199254740]) {
      test('ping $c gets a pong echoing it with the host time', () async {
        final before = Clock.nowUs();
        ws.add(encodeMessage('ping', {'c': c}));
        await waitFor(() => of('pong').isNotEmpty);
        final pong = of('pong').single;
        expect(pong['c'], c);
        expect(pong['h'] as int, inInclusiveRange(before, Clock.nowUs()));
      });
    }
    for (final (err, expected) in [(12, 12), (-30, -30), (null, null), ('x', null)]) {
      test('ping reporting err ${jsonEncode(err)} stores $expected', () async {
        ws.add(encodeMessage('ping', {'c': 1, 'err': err}));
        await waitFor(() => of('pong').isNotEmpty);
        expect(host.guests.single.errorMs, expected);
      });
    }
    test('"ready" marks the song as on that phone', () async {
      final id = host.playlist.single.id;
      ws.add(encodeMessage('ready', {'id': id}));
      await waitFor(() => host.guests.single.ready.isNotEmpty);
      expect(host.guests.single.ready, {id});
    });
    test('"ready" without a text id is ignored', () async {
      ws.add(encodeMessage('ready', {'id': 5}));
      ws.add(encodeMessage('ping', {'c': 1}));
      await waitFor(() => of('pong').isNotEmpty);
      expect(host.guests.single.ready, isEmpty);
    });
    test('garbage is ignored and the guest stays', () async {
      ws.add('not json');
      ws.add('[1,2,3]');
      ws.add(encodeMessage('unknown'));
      ws.add(encodeMessage('ping', {'c': 7}));
      await waitFor(() => of('pong').isNotEmpty);
      expect(host.guests, hasLength(1));
    });
    test('adding a song sends the new playlist', () async {
      await host.addTrack(await song(), 'Second');
      await waitFor(() => of('playlist').isNotEmpty);
      final tracks = (of('playlist').last['tracks'] as List);
      expect(tracks, hasLength(2));
    });
    test('play waits for a ready guest and sends the playing state', () async {
      ws.add(encodeMessage('ready', {'id': host.playlist.single.id}));
      await waitFor(() => host.guests.single.ready.isNotEmpty);
      await host.play();
      await waitFor(() => of('state').any((m) => m['playing'] == true));
      expect(PlayState.fromJson(of('state').last).anchorUs, host.state.anchorUs);
    });
    test('closing the party says bye', () async {
      await host.close();
      await waitFor(() => of('bye').isNotEmpty);
    });
    test('a guest that hangs up is removed', () async {
      await ws.close();
      await waitFor(() => host.guests.isEmpty);
    });
    test('songs are served over HTTP byte for byte', () async {
      final t = host.playlist.single;
      final client = HttpClient();
      final res = await (await client
              .getUrl(Uri.parse('http://127.0.0.1:${host.port}/track/${t.id}')))
          .close();
      final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
      client.close();
      expect(res.statusCode, 200);
      expect(bytes, hasLength(70000));
      expect(bytes.every((b) => b == 3), isTrue);
    });
    for (final path in ['/track/unknown', '/', '/ws', '/track/']) {
      test('GET $path is not found', () async {
        final client = HttpClient();
        final res =
            await (await client.getUrl(Uri.parse('http://127.0.0.1:${host.port}$path'))).close();
        await res.drain<void>();
        client.close();
        expect(res.statusCode, 404);
      });
    }
  });

  group('PartyGuest before connecting', () {
    test('starts connecting with nothing to play', () async {
      final dir = await Directory('${tmp.path}/g').create();
      final g = PartyGuest(
        engine: FakeEngine(),
        code: const JoinCode(hosts: ['10.0.0.1'], port: 1, name: 'h'),
        name: 'me',
        folder: dir,
        speaker: SimpleSpeaker(),
      );
      expect(g.status, GuestStatus.connecting);
      expect(g.current, isNull);
      expect(g.position, Duration.zero);
      expect(g.playlist, isEmpty);
      expect((g.hostNowUs() - Clock.nowUs()).abs(), lessThan(1000000));
      await g.leave();
    });
    test('an address nobody answers on fails', () async {
      final dir = await Directory('${tmp.path}/g2').create();
      // Grab a free port and release it so nothing listens there.
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = s.port;
      await s.close();
      final g = PartyGuest(
        engine: FakeEngine(),
        code: JoinCode(hosts: ['127.0.0.1'], port: port, name: 'h'),
        name: 'me',
        folder: dir,
        speaker: SimpleSpeaker(),
      );
      await g.connect();
      expect(g.status, GuestStatus.failed);
      await g.leave();
    });
  });
}
