import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:multi_speaker/src/net/discovery.dart';
import 'package:multi_speaker/src/sync/protocol.dart';

import 'support/gen.dart';

void main() {
  group('Track JSON', () {
    final r = Random(11);
    for (var i = 0; i < 60; i++) {
      final t = Track(
        id: randomId(r),
        title: trickyNames[i % trickyNames.length],
        ext: extensions[i % extensions.length],
        size: r.nextInt(1 << 30),
      );
      test('round-trip #$i "${t.title}" .${t.ext} ${t.size} bytes', () {
        // Through real JSON text, as it travels over the WebSocket.
        final j = jsonDecode(jsonEncode(t.toJson())) as Map<String, Object?>;
        final back = Track.fromJson(j);
        expect(back.id, t.id);
        expect(back.title, t.title);
        expect(back.ext, t.ext);
        expect(back.size, t.size);
        expect(j.keys.toSet(), {'id', 'title', 'ext', 'size'});
      });
    }
    for (final missing in ['id', 'title', 'ext', 'size']) {
      test('fromJson rejects a track without "$missing"', () {
        final j = <String, Object?>{'id': 'a', 'title': 'b', 'ext': 'mp3', 'size': 1}
          ..remove(missing);
        expect(() => Track.fromJson(j), throwsA(isA<TypeError>()));
      });
    }
    test('fromJson rejects a size sent as text', () {
      expect(
          () => Track.fromJson({'id': 'a', 'title': 'b', 'ext': 'mp3', 'size': '1'}),
          throwsA(isA<TypeError>()));
    });
    test('zero-byte track keeps size 0', () {
      final t = Track.fromJson(
          const Track(id: 'z', title: '', ext: 'mp3', size: 0).toJson());
      expect(t.size, 0);
      expect(t.title, '');
    });
  });

  group('PlayState.positionAt while playing', () {
    final r = Random(22);
    for (var i = 0; i < 120; i++) {
      final pos = r.nextInt(600000000);
      final anchor = randomBig(r);
      final delta = r.nextInt(400000000) - 100000000;
      test('#$i pos=$pos anchor=$anchor now=anchor${delta >= 0 ? '+' : ''}$delta', () {
        final s = PlayState(
            trackId: 't', playing: true, positionUs: pos, anchorUs: anchor);
        expect(s.positionAt(anchor + delta), pos + delta);
        expect(s.positionAt(anchor), pos);
        // Advances one microsecond per microsecond.
        expect(s.positionAt(anchor + delta + 1000) - s.positionAt(anchor + delta), 1000);
      });
    }
    for (final lead in [1, 1000, 250000, 700000, 1000000, 5000000]) {
      test('start scheduled $lead us ahead reads -$lead us before it', () {
        final s = PlayState(
            trackId: 't', playing: true, positionUs: 0, anchorUs: 10000000 + lead);
        expect(s.positionAt(10000000), -lead);
        expect(s.positionAt(10000000 + lead), 0);
      });
    }
  });

  group('PlayState.positionAt while paused', () {
    final r = Random(33);
    for (var i = 0; i < 40; i++) {
      final pos = r.nextInt(600000000);
      final anchor = randomBig(r);
      final now = randomBig(r);
      test('#$i stays at $pos whatever the time', () {
        final s = PlayState(
            trackId: i.isEven ? 't$i' : null,
            playing: false,
            positionUs: pos,
            anchorUs: anchor);
        expect(s.positionAt(now), pos);
        expect(s.positionAt(anchor), pos);
        expect(s.positionAt(0), pos);
      });
    }
    test('idle has no track, is paused at 0', () {
      expect(PlayState.idle.trackId, isNull);
      expect(PlayState.idle.playing, isFalse);
      expect(PlayState.idle.positionAt(123456789), 0);
    });
  });

  group('PlayState JSON', () {
    final r = Random(44);
    for (var i = 0; i < 60; i++) {
      final s = PlayState(
        trackId: i % 5 == 0 ? null : randomId(r),
        playing: r.nextBool(),
        positionUs: r.nextInt(1 << 32),
        anchorUs: randomBig(r),
      );
      test('#$i round-trips inside a "state" message (track ${s.trackId}, playing ${s.playing})', () {
        final m = decodeMessage(encodeMessage('state', s.toJson()))!;
        expect(m['t'], 'state');
        final back = PlayState.fromJson(m);
        expect(back.trackId, s.trackId);
        expect(back.playing, s.playing);
        expect(back.positionUs, s.positionUs);
        expect(back.anchorUs, s.anchorUs);
        final now = s.anchorUs + r.nextInt(1000000);
        expect(back.positionAt(now), s.positionAt(now));
      });
    }
    test('uses the short wire keys', () {
      const s = PlayState(trackId: 'x', playing: true, positionUs: 1, anchorUs: 2);
      expect(s.toJson(), {'track': 'x', 'playing': true, 'pos': 1, 'at': 2});
    });
  });

  group('encodeMessage / decodeMessage', () {
    final types = ['ping', 'pong', 'hi', 'ready', 'state', 'playlist', 'bye', 'x'];
    final bodies = <Map<String, Object?>>[
      {},
      {'c': 123456789012},
      {'name': "Rahul's phone", 'v': 1},
      {'id': 'abcdef0123456789'},
      {'err': null},
      {'tracks': []},
      {'nested': {'a': [1, 2, 3]}},
      {'flag': true, 'n': -5, 'f': 1.5},
    ];
    for (final t in types) {
      for (var b = 0; b < bodies.length; b++) {
        test('"$t" with body #$b round-trips', () {
          final m = decodeMessage(encodeMessage(t, bodies[b]))!;
          expect(m['t'], t);
          expect(m.length, bodies[b].length + 1);
          for (final e in bodies[b].entries) {
            expect(m[e.key], e.value);
          }
        });
      }
    }
    final rejected = <String, Object?>{
      'null': null,
      'an int': 42,
      'bytes': <int>[123, 125],
      'a map object': {'t': 'ping'},
      'empty text': '',
      'broken JSON': '{"t":',
      'plain words': 'hello',
      'a JSON array': '[1,2]',
      'a JSON string': '"ping"',
      'a JSON number': '7',
      'JSON null': 'null',
      'an object without t': '{"c":1}',
      'a numeric t': '{"t":1}',
      'a null t': '{"t":null}',
      'a list t': '{"t":["ping"]}',
      'an object t': '{"t":{}}',
    };
    rejected.forEach((what, data) {
      test('ignores $what', () => expect(decodeMessage(data), isNull));
    });
  });

  group('JoinCode QR round-trip', () {
    final r = Random(55);
    for (var i = 0; i < 90; i++) {
      final hosts = List.generate(1 + r.nextInt(4), (_) => randomIp(r));
      final port = 1 + r.nextInt(65535);
      final name = trickyNames[i % trickyNames.length];
      test('#$i ${hosts.length} host(s), port $port, name "$name"', () {
        final code = JoinCode(hosts: hosts, port: port, name: name);
        final text = code.encode();
        expect(text, startsWith('msync://join?'));
        final back = JoinCode.parse(text)!;
        expect(back.hosts, hosts);
        expect(back.port, port);
        expect(back.name, name);
        expect(Uri.parse(text).queryParameters['v'], '$protocolVersion');
        // Scanners sometimes add whitespace around the text.
        expect(JoinCode.parse('  $text\n')!.hosts, hosts);
      });
    }
    test('an empty name survives', () {
      final back = JoinCode.parse(
          const JoinCode(hosts: ['10.0.0.1'], port: 1, name: '').encode())!;
      expect(back.name, '');
    });
    test('a missing name becomes "Host"', () {
      expect(JoinCode.parse('msync://join?h=10.0.0.1&p=47800')!.name, 'Host');
    });
    test('empty entries in the host list are skipped', () {
      expect(JoinCode.parse('msync://join?h=,10.0.0.1,,10.0.0.2,&p=5')!.hosts,
          ['10.0.0.1', '10.0.0.2']);
    });
    test('an upper-case scheme is still ours', () {
      expect(JoinCode.parse('MSYNC://join?h=10.0.0.1&p=5')!.port, 5);
    });
    const badQr = {
      'no hosts': 'msync://join?p=47800',
      'empty hosts': 'msync://join?h=&p=47800',
      'only commas': 'msync://join?h=,,,&p=47800',
      'no port': 'msync://join?h=10.0.0.1',
      'text port': 'msync://join?h=10.0.0.1&p=abc',
      'empty port': 'msync://join?h=10.0.0.1&p=',
      'decimal port': 'msync://join?h=10.0.0.1&p=1.5',
      'other scheme': 'https://join?h=10.0.0.1&p=1',
      'similar scheme': 'msyncx://join?h=10.0.0.1&p=1',
      'web link': 'https://example.com/?h=10.0.0.1&p=1',
      'wifi QR': 'WIFI:S:home;T:WPA;P:secret;;',
      'mail link': 'mailto:someone@example.com',
    };
    badQr.forEach((what, text) {
      test('rejects a code with $what', () => expect(JoinCode.parse(text), isNull));
    });
  });

  group('JoinCode typed address', () {
    final r = Random(66);
    for (var i = 0; i < 50; i++) {
      final ip = randomIp(r);
      test('#$i "$ip" uses the default port', () {
        final c = JoinCode.parse(ip)!;
        expect(c.hosts, [ip]);
        expect(c.port, hostPort);
        expect(c.name, ip);
      });
    }
    for (var i = 0; i < 40; i++) {
      final ip = randomIp(r);
      final port = 1 + r.nextInt(65535);
      test('#$i "$ip:$port" keeps the port', () {
        final c = JoinCode.parse('$ip:$port')!;
        expect(c.hosts, [ip]);
        expect(c.port, port);
        expect(c.name, ip);
      });
    }
    for (final edge in ['0.0.0.0', '255.255.255.255', '127.0.0.1', '1.2.3.4']) {
      test('edge address $edge is accepted', () {
        expect(JoinCode.parse(edge)!.hosts, [edge]);
      });
    }
    for (final pad in [' ', '\t', '\n', '  \r\n']) {
      test('surrounding ${jsonEncode(pad)} is trimmed', () {
        expect(JoinCode.parse('${pad}192.168.1.9:6000$pad')!.port, 6000);
      });
    }
    const bad = [
      '',
      ' ',
      '256.1.1.1',
      '1.256.1.1',
      '1.1.256.1',
      '1.1.1.256',
      '999.999.999.999',
      '1.2.3',
      '1.2.3.4.5',
      '1.2.3.',
      '.1.2.3',
      '1..2.3',
      '1234.1.1.1',
      'a.b.c.d',
      '1.2.3.4:',
      ':47800',
      '1.2.3.4:123456',
      '1.2.3.4:-1',
      '1.2.3.4:port',
      '1.2.3.4 :80',
      '1.2.3.4/24',
      'http://1.2.3.4',
      '::1',
      'fe80::1',
      'localhost',
      'example.com',
      '192.168.1.5:47800:1',
      '1,2,3,4',
      '1.2.3.4a',
      'x1.2.3.4',
    ];
    for (final b in bad) {
      test('rejects typed ${jsonEncode(b)}', () => expect(JoinCode.parse(b), isNull));
    }
  });

  group('FoundHost', () {
    final r = Random(77);
    for (var i = 0; i < 30; i++) {
      final ip = randomIp(r);
      final port = 1 + r.nextInt(65535);
      final name = trickyNames[i % trickyNames.length];
      test('#$i joinCode for $ip:$port "$name" survives the QR text', () {
        final h = FoundHost(address: ip, port: port, name: name);
        final c = h.joinCode;
        expect(c.hosts, [ip]);
        expect(c.port, port);
        expect(c.name, name);
        final back = JoinCode.parse(c.encode())!;
        expect(back.hosts, [ip]);
        expect(back.port, port);
        expect(back.name, name);
      });
    }
  });

  test('localAddresses only lists private, non-loopback IPv4 addresses', () async {
    final list = await localAddresses();
    for (final a in list) {
      final p = a.split('.').map(int.parse).toList();
      expect(p, hasLength(4));
      final private = p[0] == 10 ||
          (p[0] == 172 && p[1] >= 16 && p[1] < 32) ||
          (p[0] == 192 && p[1] == 168);
      expect(private, isTrue, reason: a);
    }
  });
}
