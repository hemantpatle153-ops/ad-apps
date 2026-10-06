import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:multi_speaker/src/live/live_audio.dart';

void main() {
  test('a live frame carries its time and sound', () {
    final pcm = Uint8List.fromList([1, 2, 3, 4, 250]);
    final f = decodeLiveFrame(encodeLiveFrame(123456789012, pcm))!;
    expect(f.hostUs, 123456789012);
    expect(f.pcm, pcm);
    expect(decodeLiveFrame([1, 2, 3]), isNull);
    expect(decodeLiveFrame('text'), isNull);
  });

  test('chunk times stay steady when chunks arrive unevenly', () {
    final s = LiveStamper();
    const chunk = 3840; // 20 ms
    final stamps = <int>[];
    // Arrivals wobble by up to 8 ms around a steady 20 ms beat.
    const wobble = [0, 8000, -5000, 3000, -8000, 6000, 0, -2000];
    for (var i = 0; i < 200; i++) {
      stamps.add(s.stamp(1000000 + i * 20000 + wobble[i % wobble.length], chunk));
    }
    for (var i = 1; i < stamps.length; i++) {
      final step = stamps[i] - stamps[i - 1];
      expect(step, inInclusiveRange(19800, 20200), reason: 'chunk $i');
    }
    // Still tracks the arrivals overall.
    expect((stamps.last - (1000000 + 199 * 20000 - 20000)).abs(), lessThan(10000));
  });

  test('a long gap starts the times again', () {
    final s = LiveStamper();
    s.stamp(1000000, 3840);
    expect(s.stamp(5000000, 3840), 5000000 - 20000);
  });
}
