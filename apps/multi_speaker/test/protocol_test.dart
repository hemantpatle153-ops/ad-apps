import 'package:flutter_test/flutter_test.dart';
import 'package:multi_speaker/src/sync/clock.dart';
import 'package:multi_speaker/src/sync/protocol.dart';

void main() {
  group('JoinCode', () {
    test('round-trips through the QR text', () {
      const c = JoinCode(hosts: ['192.168.1.5', '10.0.0.2'], port: 47800, name: "Rahul's phone");
      final back = JoinCode.parse(c.encode())!;
      expect(back.hosts, c.hosts);
      expect(back.port, 47800);
      expect(back.name, "Rahul's phone");
    });

    test('accepts a typed address with or without port', () {
      expect(JoinCode.parse(' 192.168.43.1 ')!.port, hostPort);
      expect(JoinCode.parse('192.168.43.1:5000')!.port, 5000);
      expect(JoinCode.parse('192.168.43.1')!.hosts, ['192.168.43.1']);
    });

    test('rejects other QR codes', () {
      expect(JoinCode.parse('https://example.com'), isNull);
      expect(JoinCode.parse('300.1.1.1'), isNull);
      expect(JoinCode.parse('msync://join?p=1'), isNull);
    });
  });

  test('PlayState positions follow the anchor', () {
    const s = PlayState(trackId: 'a', playing: true, positionUs: 1000000, anchorUs: 5000000);
    expect(s.positionAt(5000000), 1000000);
    expect(s.positionAt(6500000), 2500000);
    expect(s.positionAt(4000000), 0); // scheduled start one second away
    final back = PlayState.fromJson(s.toJson());
    expect(back.positionAt(6000000), 2000000);
    const paused = PlayState(trackId: 'a', playing: false, positionUs: 42, anchorUs: 0);
    expect(paused.positionAt(999999), 42);
  });

  group('ClockSync', () {
    test('finds the offset from symmetric round trips', () {
      final c = ClockSync();
      // Host is 10 s ahead; 20 ms each way.
      c.add(sentUs: 0, hostUs: 10000000 + 20000, receivedUs: 40000);
      expect(c.offsetUs, 10000000);
    });

    test('trusts the fastest round trips over slow, lopsided ones', () {
      final c = ClockSync();
      const offset = 3000000;
      var t = 0;
      // Slow samples where the reply was stuck in the network (lopsided).
      for (var i = 0; i < 10; i++) {
        c.add(sentUs: t, hostUs: t + offset + 5000, receivedUs: t + 300000);
        t += 100000;
      }
      // A few fast, honest ones.
      for (var i = 0; i < 3; i++) {
        c.add(sentUs: t, hostUs: t + offset + 2000, receivedUs: t + 4000);
        t += 100000;
      }
      expect((c.offsetUs - offset).abs(), lessThan(1000));
      expect(c.bestRttUs, 4000);
    });
  });
}
