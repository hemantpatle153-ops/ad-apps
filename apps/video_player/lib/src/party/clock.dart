/// A steady clock in microseconds that never jumps when the phone's wall
/// clock changes, so it is safe to compare two readings taken on one phone.
class Clock {
  Clock._();

  static final Stopwatch _watch = Stopwatch()..start();
  static final int _base = DateTime.now().microsecondsSinceEpoch;

  /// Microseconds on this phone's steady clock.
  static int nowUs() => _base + _watch.elapsedMicroseconds;
}

/// One ping round trip to the host.
class ClockSample {
  const ClockSample({required this.offsetUs, required this.rttUs});

  /// How far the host clock is ahead of ours.
  final int offsetUs;
  final int rttUs;
}

/// Estimates the host's clock from ping round trips (the NTP idea).
///
/// A guest sends its time `t0`, the host answers with its time `h`, and the
/// answer arrives at `t1`. If the network delay is the same both ways, the
/// host read its clock at our time (t0 + t1) / 2. Wi-Fi delay varies a lot,
/// so only the fastest round trips are trusted: their error is at most half
/// their round trip.
class ClockSync {
  ClockSync({this.window = 24});

  final int window;
  final List<ClockSample> _samples = [];

  bool get hasEstimate => _samples.isNotEmpty;

  void add({required int sentUs, required int hostUs, required int receivedUs}) {
    final rtt = receivedUs - sentUs;
    if (rtt < 0) return;
    final offset = hostUs - (sentUs + receivedUs) ~/ 2;
    _samples.add(ClockSample(offsetUs: offset, rttUs: rtt));
    if (_samples.length > window) _samples.removeAt(0);
  }

  /// Offset to add to [Clock.nowUs] to get host time. Uses the median
  /// offset of the three fastest recent samples.
  int get offsetUs {
    if (_samples.isEmpty) return 0;
    final best = [..._samples]..sort((a, b) => a.rttUs.compareTo(b.rttUs));
    final top = best.take(3).map((s) => s.offsetUs).toList()..sort();
    return top[top.length ~/ 2];
  }

  /// Round trip of the fastest recent sample, a bound on the estimate's
  /// error (the real error is at most half of it).
  int? get bestRttUs {
    if (_samples.isEmpty) return null;
    return _samples.map((s) => s.rttUs).reduce((a, b) => a < b ? a : b);
  }

  void clear() => _samples.clear();
}
