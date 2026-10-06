import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_app/src/format.dart';
import 'package:video_player_app/src/player/player_sheets.dart' show speeds;

import 'support/fixtures.dart';

/// Parses "h:mm:ss" / "m:ss" (optionally negative) back to seconds.
int parseClock(String s) {
  final neg = s.startsWith('-');
  final parts = (neg ? s.substring(1) : s).split(':').map(int.parse).toList();
  var total = 0;
  for (final p in parts) {
    total = total * 60 + p;
  }
  return neg ? -total : total;
}

void main() {
  group('formatDuration table', () {
    const table = <int, String>{
      0: '0:00',
      1: '0:01',
      9: '0:09',
      10: '0:10',
      59: '0:59',
      60: '1:00',
      61: '1:01',
      75: '1:15',
      599: '9:59',
      600: '10:00',
      3599: '59:59',
      3600: '1:00:00',
      3601: '1:00:01',
      3660: '1:01:00',
      3725: '1:02:05',
      7199: '1:59:59',
      36000: '10:00:00',
      86399: '23:59:59',
      86400: '24:00:00',
      360000: '100:00:00',
      -1: '-0:01',
      -12: '-0:12',
      -60: '-1:00',
      -3725: '-1:02:05',
    };
    table.forEach((secs, expected) {
      test('$secs s -> "$expected"', () {
        expect(formatDuration(Duration(seconds: secs)), expected);
      });
    });
  });

  group('formatDuration sub-second truncation', () {
    for (final ms in [1, 499, 500, 999, 1001, 59999, 60500, 3600999]) {
      test('$ms ms drops the fraction', () {
        expect(formatDuration(Duration(milliseconds: ms)),
            formatDuration(Duration(seconds: ms ~/ 1000)));
      });
    }
  });

  group('formatDuration round trip', () {
    final values = distinctInts(101, 160, 400000);
    for (final secs in values) {
      test('$secs s parses back and is well formed', () {
        final text = formatDuration(Duration(seconds: secs));
        expect(parseClock(text), secs);
        final parts = text.split(':');
        expect(parts.length, secs >= 3600 ? 3 : 2);
        for (final p in parts.skip(1)) {
          expect(p.length, 2, reason: text);
          expect(int.parse(p), lessThan(60));
        }
        expect(parts.first.startsWith('0') && parts.first.length > 1, isFalse);
      });
    }
    for (final secs in distinctInts(102, 40, 100000, min: 1)) {
      test('-$secs s mirrors the positive text', () {
        expect(formatDuration(Duration(seconds: -secs)),
            '-${formatDuration(Duration(seconds: secs))}');
      });
    }
  });

  group('formatSize table', () {
    const kb = 1024, mb = 1024 * 1024, gb = 1024 * 1024 * 1024;
    final table = <int, String>{
      -5: '',
      0: '',
      1: '1 B',
      512: '512 B',
      1023: '1023 B',
      kb: '1 KB',
      1536: '2 KB',
      740 * kb: '740 KB',
      1023 * kb: '1023 KB',
      mb: '1.00 MB',
      (1.5 * mb).round(): '1.50 MB',
      (9.994 * mb).round(): '9.99 MB',
      10 * mb: '10.0 MB',
      (12.4 * mb).round(): '12.4 MB',
      (99.94 * mb).round(): '99.9 MB',
      100 * mb: '100 MB',
      (512.3 * mb).round(): '512 MB',
      gb: '1.00 GB',
      (1.27 * gb).round(): '1.27 GB',
      (25.5 * gb).round(): '25.5 GB',
      250 * gb: '250 GB',
      1024 * gb: '1.00 TB',
      2048 * 1024 * gb: '2048 TB',
    };
    table.forEach((bytes, expected) {
      test('$bytes bytes -> "$expected"', () {
        expect(formatSize(bytes), expected);
      });
    });
  });

  group('formatSize invariants', () {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    final r = Random(7);
    final values = <int>{};
    while (values.length < 150) {
      // Spread over magnitudes: 2^0 .. 2^45.
      final exp = r.nextInt(46);
      values.add((pow(2, exp) * (1 + r.nextDouble())).floor());
    }
    for (final bytes in values) {
      test('$bytes bytes uses a sensible unit and precision', () {
        final text = formatSize(bytes);
        final parts = text.split(' ');
        expect(parts.length, 2);
        final unit = units.indexOf(parts[1]);
        expect(unit, greaterThanOrEqualTo(0));
        final scaled = bytes / pow(1024, unit);
        expect(scaled, greaterThanOrEqualTo(1));
        if (unit < units.length - 1) expect(scaled, lessThan(1024));
        final number = double.parse(parts[0]);
        final decimals =
            parts[0].contains('.') ? parts[0].split('.')[1].length : 0;
        final expectedDecimals =
            unit <= 1 || scaled >= 100 ? 0 : (scaled >= 10 ? 1 : 2);
        expect(decimals, expectedDecimals);
        expect((number - scaled).abs(),
            lessThanOrEqualTo(0.5 * pow(10, -decimals) + 1e-9));
      });
    }
  });

  group('qualityLabel', () {
    const table = <List<int>, String>{
      [3840, 2160]: '4K',
      [2160, 3840]: '4K',
      [4096, 2160]: '4K',
      [7680, 4320]: '4K',
      [2560, 2000]: '4K',
      [2560, 1999]: '1440p',
      [2560, 1440]: '1440p',
      [1440, 2560]: '1440p',
      [2000, 1400]: '1440p',
      [1920, 1399]: '1080p',
      [1920, 1080]: '1080p',
      [1080, 1920]: '1080p',
      [1920, 1000]: '1080p',
      [1440, 1080]: '1080p',
      [1280, 999]: '720p',
      [1280, 720]: '720p',
      [720, 1280]: '720p',
      [1000, 700]: '720p',
      [960, 699]: '480p',
      [854, 480]: '480p',
      [640, 480]: '480p',
      [480, 640]: '480p',
      [800, 460]: '480p',
      [800, 459]: '459p',
      [640, 360]: '360p',
      [426, 240]: '240p',
      [256, 144]: '144p',
      [1, 1]: '1p',
      [0, 0]: '',
      [1920, 0]: '',
      [0, 1080]: '',
      [-1, 720]: '',
      [1280, -720]: '',
    };
    table.forEach((wh, expected) {
      test('${wh[0]}x${wh[1]} -> "$expected"', () {
        expect(qualityLabel(wh[0], wh[1]), expected);
      });
    });

    String bucket(int p) {
      if (p <= 0) return '';
      if (p >= 2000) return '4K';
      if (p >= 1400) return '1440p';
      if (p >= 1000) return '1080p';
      if (p >= 700) return '720p';
      if (p >= 460) return '480p';
      return '${p}p';
    }

    final r = Random(33);
    final pairs = <String>{};
    while (pairs.length < 60) {
      pairs.add('${1 + r.nextInt(5000)}x${1 + r.nextInt(5000)}');
    }
    for (final pair in pairs) {
      final w = int.parse(pair.split('x')[0]),
          h = int.parse(pair.split('x')[1]);
      test('$pair is symmetric and buckets on the short side', () {
        expect(qualityLabel(w, h), qualityLabel(h, w));
        expect(qualityLabel(w, h), bucket(min(w, h)));
      });
    }
  });

  group('formatSpeed', () {
    final table = <double, String>{
      1: '1x',
      0.25: '0.25x',
      0.5: '0.5x',
      0.75: '0.75x',
      1.25: '1.25x',
      1.5: '1.5x',
      2: '2x',
      2.5: '2.5x',
      3: '3x',
      4: '4x',
      10: '10x',
      0.05: '0.05x',
      1.006: '1.01x',
      0.999: '1x',
      1.333333: '1.33x',
      0: '0x',
    };
    table.forEach((speed, expected) {
      test('$speed -> "$expected"', () {
        expect(formatSpeed(speed), expected);
      });
    });

    for (var i = 5; i <= 80; i++) {
      final s = i / 20;
      test(
          'slider step ${s.toStringAsFixed(2)} round-trips without trailing zeros',
          () {
        final text = formatSpeed(s);
        expect(text.endsWith('x'), isTrue);
        final body = text.substring(0, text.length - 1);
        expect(double.parse(body), closeTo(s, 1e-9));
        expect(body.endsWith('.'), isFalse);
        if (body.contains('.')) expect(body.endsWith('0'), isFalse);
      });
    }

    for (final s in speeds) {
      test('preset chip $s is labelled exactly', () {
        expect(double.parse(formatSpeed(s).replaceAll('x', '')), s);
      });
    }
  });
}
