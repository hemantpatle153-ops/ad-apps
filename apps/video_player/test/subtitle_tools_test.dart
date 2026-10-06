import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_app/src/library/subtitle_cues.dart';
import 'package:video_player_app/src/library/subtitle_sync.dart';
import 'package:video_player_app/src/player/subtitle_session.dart';

/// Lines of 1-4 s with 0.5-6 s gaps, like dialogue, over [lengthMs].
List<Cue> _dialogue(int lengthMs, Random r) {
  final cues = <Cue>[];
  var t = 2000;
  while (t < lengthMs) {
    final len = 1000 + r.nextInt(3000);
    cues.add(Cue(t, t + len));
    t += len + 500 + r.nextInt(5500);
  }
  return cues;
}

/// Sound for a video whose speech follows [cues] shown at
/// v = s * speed + delay: louder while someone talks, plus noise.
List<AudioWindow> _sound(List<Cue> cues, int durationMs, double speed, int delayMs,
    Random r, {bool unrelated = false}) {
  // Who is talking, per 10 ms of subtitle time.
  final talk = Uint8List(durationMs ~/ 10 + 1);
  for (final c in cues) {
    for (var k = c.startMs ~/ 10; k < c.endMs ~/ 10 && k < talk.length; k++) {
      talk[k] = 1;
    }
  }
  final windows = <AudioWindow>[];
  for (final (start, length) in syncWindows(durationMs)) {
    final n = length ~/ 100;
    final e = Float32List(n);
    for (var f = 0; f < n; f++) {
      final v = start + f * 100;
      final s = (v - delayMs) / speed;
      final talking = unrelated
          ? r.nextDouble() < 0.4
          : s >= 0 && s < durationMs && talk[s ~/ 10] == 1;
      e[f] = (talking ? -22 : -34) + r.nextDouble() * 14 - 7;
    }
    windows.add(AudioWindow(start, e));
  }
  return windows;
}

void main() {
  group('cue parsing', () {
    test('timestamps in srt, vtt and ass forms', () {
      expect(parseTimestamp('00:01:02,345'), 62345);
      expect(parseTimestamp('01:02:03.004'), 3723004);
      expect(parseTimestamp('01:02.500'), 62500);
      expect(parseTimestamp('0:00:03.50'), 3500);
      expect(parseTimestamp('nonsense'), isNull);
    });

    test('srt', () {
      const srt = '﻿1\r\n00:00:01,000 --> 00:00:03,500\r\nHello\r\n\r\n'
          '2\r\n00:00:05,000 --> 00:00:06,000\r\nWorld\r\n';
      final cues = parseCues(srt);
      expect(cues.length, 2);
      expect(cues[0].startMs, 1000);
      expect(cues[0].endMs, 3500);
      expect(cues[1].startMs, 5000);
    });

    test('webvtt with cue settings', () {
      const vtt = 'WEBVTT\n\n00:01.000 --> 00:04.000 align:start\nHi\n\n'
          '00:00:10.000 --> 00:00:12.250\nThere\n';
      final cues = parseCues(vtt);
      expect(cues.map((c) => c.startMs), [1000, 10000]);
      expect(cues.last.endMs, 12250);
    });

    test('ass dialogue lines, sorted', () {
      const ass = '[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, '
          'MarginR, MarginV, Effect, Text\n'
          'Dialogue: 0,0:00:09.00,0:00:10.00,Default,,0,0,0,,Later, with comma\n'
          'Dialogue: 0,0:00:01.50,0:00:03.00,Default,,0,0,0,,First\n';
      final cues = parseCues(ass);
      expect(cues.map((c) => c.startMs), [1500, 9000]);
    });

    test('skips broken and empty cues', () {
      final cues = parseCues('00:00:05,000 --> 00:00:04,000\nx\n\n'
          '00:00:xx,000 --> 00:00:06,000\ny\n');
      expect(cues, isEmpty);
    });
  });

  group('auto sync', () {
    const duration = 2 * 3600 * 1000;

    test('listening windows avoid titles and credits', () {
      final w = syncWindows(duration);
      expect(w.length, 3);
      expect(w.first.$1, greaterThanOrEqualTo(duration * 0.05 - 1));
      expect(w.last.$1 + w.last.$2, lessThanOrEqualTo(duration * 0.95 + 1));
      expect(syncWindows(300000), [(0, 300000)]);
      expect(syncWindows(0), isEmpty);
    });

    for (final (speed, delay) in [
      (1.0, 2300),
      (1.0, -45000),
      (25 / 23.976, -1500),
      (23.976 / 25, 800),
    ]) {
      test('finds speed ${speed.toStringAsFixed(4)} and delay $delay ms', () {
        final r = Random(7);
        final cues = _dialogue(duration, r);
        final result = findSync(cues, _sound(cues, duration, speed, delay, r))!;
        expect(result.speed, speed);
        expect((result.delayMs - delay).abs(), lessThanOrEqualTo(200));
        expect(result.confidence, greaterThan(minSyncConfidence));
      });
    }

    test('sound unrelated to the subtitles is not trusted', () {
      final r = Random(3);
      final cues = _dialogue(duration, r);
      final result = findSync(cues, _sound(cues, duration, 1, 0, r, unrelated: true));
      expect(result == null || result.confidence < minSyncConfidence, isTrue);
    });

    test('nothing to compare', () {
      expect(findSync(const [], [AudioWindow(0, Float32List(10))]), isNull);
      expect(findSync(const [Cue(0, 1000)], const []), isNull);
    });

    test('delay labels', () {
      expect(formatDelay(1500), '+1.5 s');
      expect(formatDelay(-300), '-0.3 s');
      expect(formatDelay(0), '0.0 s');
    });
  });
}
