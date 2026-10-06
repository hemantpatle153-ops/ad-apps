import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:multi_speaker/src/sync/clock.dart';

import 'support/gen.dart';

void main() {
  group('symmetric round trip gives the exact offset', () {
    final r = Random(101);
    for (var i = 0; i < 70; i++) {
      final sent = randomBig(r);
      final oneWay = r.nextInt(200000);
      final offset = r.nextInt(2000000000) - 1000000000;
      test('#$i offset $offset us, $oneWay us each way', () {
        final c = ClockSync();
        c.add(
            sentUs: sent,
            hostUs: sent + oneWay + offset,
            receivedUs: sent + 2 * oneWay);
        expect(c.hasEstimate, isTrue);
        expect(c.offsetUs, offset);
        expect(c.bestRttUs, 2 * oneWay);
      });
    }
  });

  group('lopsided delay error stays within half the round trip', () {
    final r = Random(202);
    for (var i = 0; i < 60; i++) {
      final sent = randomBig(r);
      final rtt = 1 + r.nextInt(300000);
      final there = r.nextInt(rtt + 1); // delay on the way to the host
      final offset = r.nextInt(100000000) - 50000000;
      test('#$i rtt $rtt us, $there us out', () {
        final c = ClockSync()
          ..add(
              sentUs: sent,
              hostUs: sent + there + offset,
              receivedUs: sent + rtt);
        expect((c.offsetUs - offset).abs(), lessThanOrEqualTo(rtt ~/ 2 + 1));
      });
    }
  });

  group('answers that arrive before they were sent are ignored', () {
    final r = Random(303);
    for (var i = 0; i < 20; i++) {
      final sent = 1000000 + randomBig(r);
      final back = 1 + r.nextInt(1000000);
      test('#$i received $back us before sending', () {
        final c = ClockSync()
          ..add(sentUs: sent, hostUs: sent, receivedUs: sent - back);
        expect(c.hasEstimate, isFalse);
        expect(c.offsetUs, 0);
        expect(c.bestRttUs, isNull);
      });
    }
    test('a zero round trip is kept', () {
      final c = ClockSync()..add(sentUs: 5, hostUs: 105, receivedUs: 5);
      expect(c.offsetUs, 100);
      expect(c.bestRttUs, 0);
    });
    test('an ignored sample does not disturb earlier ones', () {
      final c = ClockSync()
        ..add(sentUs: 0, hostUs: 1010, receivedUs: 20)
        ..add(sentUs: 100, hostUs: 999999, receivedUs: 50);
      expect(c.offsetUs, 1000);
      expect(c.bestRttUs, 20);
    });
  });

  group('median of the three fastest samples', () {
    final r = Random(404);
    for (var i = 0; i < 50; i++) {
      final fast = List.generate(3, (_) => r.nextInt(2000000) - 1000000);
      final slowCount = r.nextInt(15);
      test('#$i fast offsets $fast with $slowCount slow outliers', () {
        final c = ClockSync();
        var t = 0;
        final order = <int>[
          for (var k = 0; k < slowCount; k++) -1,
          0, 1, 2,
        ]..shuffle(Random(i));
        for (final k in order) {
          if (k < 0) {
            // Slow and wildly wrong.
            c.add(sentUs: t, hostUs: t + 90000000, receivedUs: t + 500000 + r.nextInt(100000));
          } else {
            c.add(sentUs: t, hostUs: t + 1000 + k + fast[k], receivedUs: t + 2000 + 2 * k);
          }
          t += 1000000;
        }
        final sorted = [...fast]..sort();
        expect(c.offsetUs, sorted[1]);
        expect(c.bestRttUs, 2000);
      });
    }
    for (var i = 0; i < 15; i++) {
      final a = Random(500 + i).nextInt(1000000);
      final b = Random(600 + i).nextInt(1000000);
      test('#$i with two samples ($a, $b) the larger offset is used', () {
        final c = ClockSync()
          ..add(sentUs: 0, hostUs: 500 + a, receivedUs: 1000)
          ..add(sentUs: 0, hostUs: 600 + b, receivedUs: 1200);
        expect(c.offsetUs, max(a, b));
      });
    }
  });

  group('only the most recent window is remembered', () {
    for (var w = 1; w <= 30; w++) {
      test('window $w forgets an old fast sample after $w newer ones', () {
        final c = ClockSync(window: w);
        // An old, very fast sample with its own offset.
        c.add(sentUs: 0, hostUs: 7777777, receivedUs: 0);
        expect(c.offsetUs, 7777777);
        for (var k = 1; k <= w; k++) {
          c.add(sentUs: k * 1000000, hostUs: k * 1000000 + 5000 + 42, receivedUs: k * 1000000 + 10000);
        }
        expect(c.offsetUs, 42);
        expect(c.bestRttUs, 10000);
      });
    }
    test('default window is 24', () => expect(ClockSync().window, 24));
    test('within the window an old fast sample still wins', () {
      final c = ClockSync()..add(sentUs: 0, hostUs: 500, receivedUs: 0);
      for (var k = 1; k < 24; k++) {
        c.add(sentUs: k, hostUs: k + 99999, receivedUs: k + 100000);
      }
      expect(c.bestRttUs, 0);
    });
  });

  group('bestRttUs is the fastest round trip', () {
    final r = Random(707);
    for (var i = 0; i < 25; i++) {
      final rtts = List.generate(1 + r.nextInt(20), (_) => r.nextInt(500000));
      test('#$i of ${rtts.length} samples', () {
        final c = ClockSync(window: 100);
        var t = 0;
        for (final rtt in rtts) {
          c.add(sentUs: t, hostUs: t, receivedUs: t + rtt);
          t += 1000000;
        }
        expect(c.bestRttUs, rtts.reduce(min));
      });
    }
  });

  group('clear', () {
    for (var n = 0; n < 10; n++) {
      test('forgets $n samples', () {
        final c = ClockSync();
        for (var k = 0; k < n; k++) {
          c.add(sentUs: k, hostUs: k + 1000, receivedUs: k + 10);
        }
        c.clear();
        expect(c.hasEstimate, isFalse);
        expect(c.offsetUs, 0);
        expect(c.bestRttUs, isNull);
        c.add(sentUs: 0, hostUs: 33, receivedUs: 0);
        expect(c.offsetUs, 33);
      });
    }
  });

  group('Clock.nowUs', () {
    test('never goes backwards over many readings', () {
      var prev = Clock.nowUs();
      for (var i = 0; i < 10000; i++) {
        final now = Clock.nowUs();
        expect(now, greaterThanOrEqualTo(prev));
        prev = now;
      }
    });
    test('is close to wall-clock microseconds since epoch', () {
      final diff = (Clock.nowUs() - DateTime.now().microsecondsSinceEpoch).abs();
      expect(diff, lessThan(60 * 1000000));
    });
    test('advances with real time', () async {
      final a = Clock.nowUs();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(Clock.nowUs() - a, greaterThanOrEqualTo(15000));
    });
  });
}
