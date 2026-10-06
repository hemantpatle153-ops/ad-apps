import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:water_habit/store.dart';

const day = 24 * 60;

void main() {
  group('waterReminderTimes table', () {
    final cases = <(int, int, int, List<int>)>[
      (480, 1320, 120, [600, 720, 840, 960, 1080, 1200, 1320]),
      (1200, 120, 180, [1380, 120]),
      (480, 1320, 60, [for (var t = 540; t <= 1320; t += 60) t]),
      (480, 1320, 90, [570, 660, 750, 840, 930, 1020, 1110, 1200, 1290]),
      (480, 1320, 180, [660, 840, 1020, 1200]),
      (480, 540, 60, [540]),
      (480, 539, 60, []),
      (480, 1320, 840, [1320]),
      (480, 1320, 841, []),
      (0, 1439, 720, [720]),
      (1380, 60, 30, [1410, 0, 30, 60]),
      (1430, 10, 10, [0, 10]),
      (600, 600, 360, [960, 1320, 240, 600]),
      (600, 600, 1440, [600]),
      (600, 600, 1441, []),
      (0, 0, 480, [480, 960, 0]),
      (22 * 60, 6 * 60, 120, [0, 120, 240, 360]),
      (360, 1380, 300, [660, 960, 1260]),
      (450, 1305, 45, [for (var t = 495; t <= 1305; t += 45) t]),
      (700, 690, 1430, [690]),
    ];
    for (final (w, s, i, exp) in cases) {
      test('wake $w sleep $s every $i', () {
        expect(waterReminderTimes(w, s, i), exp);
      });
    }
  });

  group('non-positive interval gives no reminders', () {
    for (final i in [0, -1, -5, -60, -120, -1440, -99999]) {
      test('interval $i', () {
        expect(waterReminderTimes(480, 1320, i), isEmpty);
        expect(waterReminderTimes(1320, 480, i), isEmpty);
      });
    }
  });

  group('random windows satisfy invariants', () {
    final r = Random(42);
    for (var n = 0; n < 220; n++) {
      final wake = r.nextInt(day);
      final sleep = r.nextInt(day);
      final interval = 1 + r.nextInt(n.isEven ? 240 : 900);
      test('#$n wake $wake sleep $sleep every $interval', () {
        final times = waterReminderTimes(wake, sleep, interval);
        final end = sleep > wake ? sleep : sleep + day;
        final span = end - wake;
        expect(times.length, span ~/ interval);
        for (var k = 0; k < times.length; k++) {
          expect(times[k], (wake + (k + 1) * interval) % day);
          expect(times[k], inInclusiveRange(0, day - 1));
          // Offset from wake, unwrapped, lies inside the window.
          final off = (times[k] - wake + day) % day;
          expect(off == 0 ? day : off, lessThanOrEqualTo(span));
        }
        expect(times.contains(wake) && span < day, isFalse);
      });
    }
  });
}
