import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_app/src/party/clock.dart';
import 'package:video_player_app/src/party/discovery.dart';
import 'package:video_player_app/src/party/protocol.dart';

import 'support/fixtures.dart';

void main() {
  group('protocol constants', () {
    test('ports are distinct and in the user range', () {
      expect(partyPort, 47810);
      expect(partyBeaconPort, 47811);
      expect(partyPort, isNot(partyBeaconPort));
    });
    test('protocol version is 1', () => expect(partyProtocol, 1));
    test('QR scheme is vparty', () => expect(JoinCode.scheme, 'vparty'));
  });

  group('parseRange table', () {
    final cases = <(String?, int, (int, int)?)>[
      ('bytes=0-0', 10, (0, 0)),
      ('bytes=0-9', 10, (0, 9)),
      ('bytes=0-10', 10, (0, 9)),
      ('bytes=0-', 10, (0, 9)),
      ('bytes=9-', 10, (9, 9)),
      ('bytes=10-', 10, null),
      ('bytes=11-20', 10, null),
      ('bytes=5-4', 10, null),
      ('bytes=3-3', 10, (3, 3)),
      ('bytes=-1', 10, (9, 9)),
      ('bytes=-10', 10, (0, 9)),
      ('bytes=-11', 10, (0, 9)),
      ('bytes=-0', 10, null),
      ('bytes=-', 10, null),
      ('bytes=', 10, null),
      ('bytes=0-9', 0, null),
      ('bytes=0-9', -5, null),
      (null, 10, null),
      ('', 10, null),
      ('  bytes=2-5  ', 10, (2, 5)),
      ('bytes = 2-5', 10, null),
      ('Bytes=2-5', 10, null),
      ('bytes=a-5', 10, null),
      ('bytes=2-5,7-8', 10, null),
      ('bytes=1-2-3', 10, null),
      ('bytes=+1-2', 10, null),
      ('items=0-1', 10, null),
      ('bytes=0-1048575', 5000000, (0, 1048575)),
      ('bytes=4999999-', 5000000, (4999999, 4999999)),
      ('bytes=-500', 5000000, (4999500, 4999999)),
      ('bytes=1000000-1999999', 5000000, (1000000, 1999999)),
      ('bytes=0-999999999999', 1 << 33, (0, (1 << 33) - 1)),
      ('bytes=007-009', 10, (7, 9)),
    ];
    for (final (header, length, expected) in cases) {
      test('"$header" of $length -> $expected', () {
        expect(parseRange(header, length), expected);
      });
    }
  });

  group('parseRange random invariants', () {
    final r = Random(4711);
    for (var i = 0; i < 60; i++) {
      final length = 1 + r.nextInt(1 << 20);
      final kind = i % 3;
      final a = r.nextInt(length + length ~/ 4 + 1);
      final b = r.nextInt(length + length ~/ 4 + 1);
      final header = switch (kind) {
        0 => 'bytes=$a-$b',
        1 => 'bytes=$a-',
        _ => 'bytes=-$b',
      };
      test('#$i "$header" of $length', () {
        final got = parseRange(header, length);
        switch (kind) {
          case 0:
            if (a >= length || b < a) {
              expect(got, isNull);
            } else {
              expect(got, (a, min(b, length - 1)));
            }
          case 1:
            expect(got, a >= length ? isNull : (a, length - 1));
          default:
            expect(got, b == 0 ? isNull : (max(0, length - b), length - 1));
        }
        if (got != null) {
          final (s, e) = got;
          expect(s, inInclusiveRange(0, length - 1));
          expect(e, inInclusiveRange(s, length - 1));
        }
      });
    }
  });

  group('PartyState.positionAt', () {
    final cases = <(PartyState, int, int)>[
      (PartyState.start, 0, 0),
      (PartyState.start, 123456789, 0),
      (const PartyState(playing: false, positionUs: 7, anchorUs: 100), 999, 7),
      (const PartyState(playing: true, positionUs: 0, anchorUs: 0), 1000000, 1000000),
      (const PartyState(playing: true, positionUs: 5000000, anchorUs: 1000000), 3000000, 7000000),
      (const PartyState(playing: true, positionUs: 0, anchorUs: 0, rate: 0.5), 1000000, 500000),
      (const PartyState(playing: true, positionUs: 0, anchorUs: 0, rate: 2), 1000000, 2000000),
      (const PartyState(playing: true, positionUs: 0, anchorUs: 0, rate: 1.25), 4, 5),
      (const PartyState(playing: true, positionUs: 0, anchorUs: 0, rate: 1.5), 3, 5),
      (const PartyState(playing: true, positionUs: 10, anchorUs: 100, rate: 1), 100, 10),
      (const PartyState(playing: true, positionUs: 1000000, anchorUs: 2000000), 1500000, 500000),
      (const PartyState(playing: false, positionUs: -3, anchorUs: 0, rate: 4), 50, -3),
    ];
    for (final (s, now, expected) in cases) {
      test('playing=${s.playing} pos=${s.positionUs} at=${s.anchorUs} rate=${s.rate} '
          'now=$now -> $expected', () {
        expect(s.positionAt(now), expected);
      });
    }

    final r = Random(99);
    for (var i = 0; i < 25; i++) {
      final rate = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0][r.nextInt(7)];
      final pos = r.nextInt(1 << 31);
      final anchor = r.nextInt(1 << 31);
      final dt = r.nextInt(1 << 28);
      test('random #$i rate $rate advances by dt*rate and pauses freeze', () {
        final playing = PartyState(playing: true, positionUs: pos, anchorUs: anchor, rate: rate);
        expect(playing.positionAt(anchor), pos);
        expect(playing.positionAt(anchor + dt), pos + (dt * rate).round());
        final paused = PartyState(playing: false, positionUs: pos, anchorUs: anchor, rate: rate);
        expect(paused.positionAt(anchor + dt), pos);
      });
    }
  });

  group('PartyState json', () {
    final r = Random(5);
    for (var i = 0; i < 20; i++) {
      final s = PartyState(
        playing: r.nextBool(),
        positionUs: r.nextInt(1 << 32),
        anchorUs: r.nextInt(1 << 32),
        rate: [0.5, 1.0, 1.75, 2.0][r.nextInt(4)],
      );
      test('round trip #$i through jsonEncode', () {
        final back = PartyState.fromJson(
            (jsonDecode(jsonEncode(s.toJson())) as Map).cast<String, Object?>());
        expect(back.playing, s.playing);
        expect(back.positionUs, s.positionUs);
        expect(back.anchorUs, s.anchorUs);
        expect(back.rate, s.rate);
      });
    }

    test('uses short keys', () {
      expect(const PartyState(playing: true, positionUs: 1, anchorUs: 2, rate: 3).toJson(),
          {'playing': true, 'pos': 1, 'at': 2, 'rate': 3.0});
    });

    final partial = <String, (Map<String, Object?>, bool, int, int, double)>{
      'empty map': ({}, false, 0, 0, 1),
      'playing as string is false': ({'playing': 'true'}, false, 0, 0, 1),
      'playing 1 is false': ({'playing': 1}, false, 0, 0, 1),
      'doubles truncate': ({'pos': 12.9, 'at': 3.2}, false, 12, 3, 1),
      'int rate becomes double': ({'rate': 2}, false, 0, 0, 2),
      'null values default': ({'pos': null, 'at': null, 'rate': null}, false, 0, 0, 1),
      'full': ({'playing': true, 'pos': 9, 'at': 8, 'rate': 0.5}, true, 9, 8, 0.5),
    };
    partial.forEach((name, c) {
      test('fromJson $name', () {
        final s = PartyState.fromJson(c.$1);
        expect(s.playing, c.$2);
        expect(s.positionUs, c.$3);
        expect(s.anchorUs, c.$4);
        expect(s.rate, c.$5);
      });
    });

    test('fromJson of a whole "state" message ignores the type key', () {
      final m = decodeMessage(encodeMessage(
          'state', const PartyState(playing: true, positionUs: 5, anchorUs: 6).toJson()))!;
      final s = PartyState.fromJson(m);
      expect((s.playing, s.positionUs, s.anchorUs, s.rate), (true, 5, 6, 1.0));
    });
  });

  group('PartyVideo json', () {
    final cases = <(String, String?)>[
      ('Movie.mkv', null),
      ('Live', 'https://cdn.example.com/live.m3u8'),
      ('फिल्म', null),
      ('', 'http://10.0.0.1/a.mp4'),
      ('a "quoted" title', null),
    ];
    for (final (title, url) in cases) {
      test('round trip "$title" url=$url', () {
        final back = PartyVideo.fromJson((jsonDecode(
                jsonEncode(PartyVideo(title: title, url: url).toJson())) as Map)
            .cast<String, Object?>());
        expect(back.title, title);
        expect(back.url, url);
      });
    }
    test('missing title becomes "Video"', () {
      expect(PartyVideo.fromJson({}).title, 'Video');
      expect(PartyVideo.fromJson({}).url, isNull);
    });
    test('non-string title is stringified', () {
      expect(PartyVideo.fromJson({'title': 42}).title, '42');
    });
  });

  group('PartyMessage', () {
    test('defaults to text and stamps time', () {
      final before = DateTime.now();
      final m = PartyMessage(from: 'A', text: 'hi');
      expect(m.emoji, isFalse);
      expect(m.at.isBefore(before), isFalse);
    });
    test('emoji flag kept', () {
      expect(PartyMessage(from: 'A', text: '🎉', emoji: true).emoji, isTrue);
    });
  });

  group('encodeMessage / decodeMessage', () {
    final round = <(String, Map<String, Object?>)>[
      ('ping', {'c': 123}),
      ('pong', {'c': 1, 'h': 2}),
      ('hi', {'name': 'Asha', 'v': 1}),
      ('chat', {'text': 'hello there'}),
      ('chat', {'from': 'राम', 'text': 'नमस्ते'}),
      ('react', {'e': '😂'}),
      ('req', {'a': 'seek', 'v': 90000000}),
      ('req', {'a': 'rate', 'v': 1.5}),
      ('members', {'names': ['a', 'b', 'c']}),
      ('bye', {}),
      ('welcome', {
        'video': {'title': 'T', 'url': null},
        'state': {'playing': false, 'pos': 0, 'at': 0, 'rate': 1.0},
      }),
    ];
    for (final (type, body) in round) {
      test('round trip $type $body', () {
        final m = decodeMessage(encodeMessage(type, body))!;
        expect(m['t'], type);
        for (final e in body.entries) {
          expect(m[e.key], e.value);
        }
        expect(m.length, body.length + 1);
      });
    }

    test('body defaults to empty', () {
      expect(jsonDecode(encodeMessage('bye')), {'t': 'bye'});
    });

    final bad = <String, Object?>{
      'null': null,
      'int': 5,
      'bytes': [123, 125],
      'invalid json': '{not json',
      'empty string': '',
      'json list': '[1,2]',
      'json number': '3',
      'json string': '"t"',
      'no type': '{"a":1}',
      'numeric type': '{"t":1}',
      'null type': '{"t":null}',
      'map not string': {'t': 'chat'},
    };
    bad.forEach((name, data) {
      test('rejects $name', () => expect(decodeMessage(data), isNull));
    });
  });

  group('JoinCode encode/parse', () {
    test('encode uses vparty://join with h, p, n, v', () {
      final u = Uri.parse(
          const JoinCode(hosts: ['192.168.1.5', '10.0.0.2'], port: 47810, name: 'Rahul')
              .encode());
      expect(u.scheme, 'vparty');
      expect(u.host, 'join');
      expect(u.queryParameters,
          {'h': '192.168.1.5,10.0.0.2', 'p': '47810', 'n': 'Rahul', 'v': '1'});
    });

    final r = Random(321);
    for (var i = 0; i < 40; i++) {
      final hosts = [
        for (var k = 0; k < 1 + r.nextInt(4); k++)
          '${[10, 172, 192][r.nextInt(3)]}.${r.nextInt(256)}.${r.nextInt(256)}.${r.nextInt(256)}'
      ];
      final port = 1 + r.nextInt(65535);
      final extras = ['', ' & co', '=x', '?#', ', comma', '+plus', '%20', 'é😀'];
      final name = randomWord(r) + extras[i % extras.length];
      test('round trip #$i "$name" ${hosts.length} hosts port $port', () {
        final back = JoinCode.parse(JoinCode(hosts: hosts, port: port, name: name).encode())!;
        expect(back.hosts, hosts);
        expect(back.port, port);
        expect(back.name, name);
      });
    }

    final qr = <String, (List<String>, int, String)?>{
      'vparty://join?h=1.2.3.4&p=5': (['1.2.3.4'], 5, 'Party'),
      'vparty://join?h=1.2.3.4&p=5&n=Me': (['1.2.3.4'], 5, 'Me'),
      'vparty://join?h=1.2.3.4,,5.6.7.8,&p=5&n=x': (['1.2.3.4', '5.6.7.8'], 5, 'x'),
      'vparty://join?h=a.local&p=80&n=': (['a.local'], 80, ''),
      '  vparty://join?h=1.2.3.4&p=5&n=sp  ': (['1.2.3.4'], 5, 'sp'),
      'VPARTY://join?h=1.2.3.4&p=5&n=up': (['1.2.3.4'], 5, 'up'),
      'vparty://anything?h=1.2.3.4&p=7': (['1.2.3.4'], 7, 'Party'),
      'vparty://join?h=&p=5': null,
      'vparty://join?h=,,,&p=5': null,
      'vparty://join?p=5': null,
      'vparty://join?h=1.2.3.4': null,
      'vparty://join?h=1.2.3.4&p=abc': null,
      'vparty://join?h=1.2.3.4&p=': null,
      'vparty://join': null,
      'http://join?h=1.2.3.4&p=5': null,
    };
    qr.forEach((raw, expected) {
      test('parse "$raw"', () {
        final c = JoinCode.parse(raw);
        if (expected == null) {
          expect(c, isNull);
        } else {
          expect(c, isNotNull);
          expect(c!.hosts, expected.$1);
          expect((c.port, c.name), (expected.$2, expected.$3));
        }
      });
    });
  });

  group('JoinCode typed address', () {
    final ok = <String, (String, int)>{
      '192.168.43.1': ('192.168.43.1', partyPort),
      ' 192.168.43.1 ': ('192.168.43.1', partyPort),
      '\n10.0.0.2\t': ('10.0.0.2', partyPort),
      '192.168.43.1:5000': ('192.168.43.1', 5000),
      '10.0.0.1:1': ('10.0.0.1', 1),
      '172.16.0.9:47810': ('172.16.0.9', 47810),
      '0.0.0.0': ('0.0.0.0', partyPort),
      '255.255.255.255': ('255.255.255.255', partyPort),
      '1.2.3.4:65535': ('1.2.3.4', 65535),
    };
    ok.forEach((raw, e) {
      test('"$raw" -> ${e.$1}:${e.$2}', () {
        final c = JoinCode.parse(raw)!;
        expect(c.hosts, [e.$1]);
        expect(c.port, e.$2);
        expect(c.name, e.$1);
      });
    });

    const bad = [
      '300.1.1.1',
      '1.256.1.1',
      '1.1.1.999',
      '1.2.3',
      '1.2.3.4.5',
      '1.2.3.4:',
      '1.2.3.4:123456',
      '1.2.3.4:port',
      '1234.1.1.1',
      'hello',
      '',
      '   ',
      'http://1.2.3.4',
      '1.2.3.4/video',
      '1.2.3.4 :80',
      '::1',
      'a.b.c.d',
    ];
    for (final raw in bad) {
      test('rejects "$raw"', () => expect(JoinCode.parse(raw), isNull));
    }
  });

  group('FoundHost', () {
    for (final (ip, port, name) in [
      ('192.168.1.7', 47810, 'Living room'),
      ('10.0.0.3', 50123, 'Phone'),
      ('172.20.1.1', 1, ''),
    ]) {
      test('$ip:$port "$name" makes a one-host join code', () {
        final h = FoundHost(address: ip, port: port, name: name);
        final c = h.joinCode;
        expect(c.hosts, [ip]);
        expect(c.port, port);
        expect(c.name, name);
        final back = JoinCode.parse(c.encode())!;
        expect(back.hosts, [ip]);
        expect((back.port, back.name), (port, name));
        expect(DateTime.now().difference(h.lastSeen).inSeconds, lessThan(5));
      });
    }
  });

  group('Clock', () {
    test('is monotonic', () {
      var last = Clock.nowUs();
      for (var i = 0; i < 1000; i++) {
        final now = Clock.nowUs();
        expect(now, greaterThanOrEqualTo(last));
        last = now;
      }
    });
    test('starts near wall clock', () {
      final diff = (Clock.nowUs() - DateTime.now().microsecondsSinceEpoch).abs();
      expect(diff, lessThan(60 * 1000000));
    });
  });

  group('ClockSync basics', () {
    test('empty has no estimate', () {
      final c = ClockSync();
      expect(c.hasEstimate, isFalse);
      expect(c.offsetUs, 0);
      expect(c.bestRttUs, isNull);
    });
    test('negative round trip is ignored', () {
      final c = ClockSync()..add(sentUs: 100, hostUs: 5, receivedUs: 50);
      expect(c.hasEstimate, isFalse);
    });
    test('zero round trip is accepted', () {
      final c = ClockSync()..add(sentUs: 100, hostUs: 600, receivedUs: 100);
      expect(c.offsetUs, 500);
      expect(c.bestRttUs, 0);
    });
    test('one sample gives its offset', () {
      final c = ClockSync()..add(sentUs: 1000, hostUs: 9000, receivedUs: 3000);
      expect(c.offsetUs, 7000);
      expect(c.bestRttUs, 2000);
    });
    test('median of the three fastest', () {
      final c = ClockSync()
        ..add(sentUs: 0, hostUs: 100 + 5, receivedUs: 10) // rtt 10, off 100
        ..add(sentUs: 0, hostUs: 300 + 10, receivedUs: 20) // rtt 20, off 300
        ..add(sentUs: 0, hostUs: 200 + 15, receivedUs: 30) // rtt 30, off 200
        ..add(sentUs: 0, hostUs: 9999 + 500, receivedUs: 1000); // slow outlier
      expect(c.offsetUs, 200);
      expect(c.bestRttUs, 10);
    });
    test('two samples use the slower-index median', () {
      final c = ClockSync()
        ..add(sentUs: 0, hostUs: 5 + 10, receivedUs: 10)
        ..add(sentUs: 0, hostUs: 10 + 50, receivedUs: 20);
      // offsets 10 and 50 sorted -> index 1
      expect(c.offsetUs, 50);
    });
    test('clear forgets everything', () {
      final c = ClockSync()..add(sentUs: 0, hostUs: 10, receivedUs: 2);
      c.clear();
      expect(c.hasEstimate, isFalse);
      expect(c.bestRttUs, isNull);
    });
    for (final w in [1, 3, 5, 24]) {
      test('window $w drops old fast samples', () {
        final c = ClockSync(window: w)
          ..add(sentUs: 0, hostUs: 1000000, receivedUs: 0); // rtt 0, wrong
        for (var i = 0; i < w; i++) {
          c.add(sentUs: 0, hostUs: 50 + 777, receivedUs: 100); // rtt 100, off 777
        }
        expect(c.offsetUs, 777);
        expect(c.bestRttUs, 100);
      });
      test('window $w keeps the fast sample while it fits', () {
        final c = ClockSync(window: w)..add(sentUs: 0, hostUs: 1000000, receivedUs: 0);
        for (var i = 0; i < w - 1; i++) {
          c.add(sentUs: 0, hostUs: 50 + 777, receivedUs: 100);
        }
        expect(c.bestRttUs, 0);
      });
    }
    test('default window is 24', () => expect(ClockSync().window, 24));
  });

  group('ClockSync recovers a simulated host clock', () {
    for (var seed = 0; seed < 40; seed++) {
      final r = Random(seed);
      final trueOffset = (r.nextInt(1 << 30) - (1 << 29)) * 2;
      final symmetric = seed.isEven;
      test('seed $seed offset $trueOffset ${symmetric ? 'symmetric' : 'jittery'}', () {
        final c = ClockSync();
        var t = 1000000 + r.nextInt(1 << 20);
        final kept = <(int, int)>[]; // (rtt, offset error)
        for (var i = 0; i < 30; i++) {
          final up = 1000 + r.nextInt(200000);
          final down = symmetric ? up : 1000 + r.nextInt(200000);
          final sent = t;
          final host = sent + up + trueOffset;
          final recv = sent + up + down;
          c.add(sentUs: sent, hostUs: host, receivedUs: recv);
          kept.add((up + down, (up - down) ~/ 2));
          t = recv + r.nextInt(500000);
        }
        final window = kept.sublist(kept.length - c.window);
        final fastest = window.map((e) => e.$1).reduce(min);
        expect(c.bestRttUs, fastest);
        final err = (c.offsetUs - trueOffset).abs();
        if (symmetric) {
          expect(err, lessThanOrEqualTo(1));
        } else {
          final top3 = [...window]..sort((a, b) => a.$1.compareTo(b.$1));
          final bound = top3.take(3).map((e) => e.$1).reduce(max) ~/ 2 + 1;
          expect(err, lessThanOrEqualTo(bound));
        }
      });
    }
  });
}
