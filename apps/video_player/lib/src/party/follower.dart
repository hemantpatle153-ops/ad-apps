import 'package:media_kit/media_kit.dart';

import 'clock.dart';
import 'protocol.dart';

/// Keeps a player on a shared timeline: small drift is fixed by playing a
/// little faster or slower, big gaps by seeking.
class TimelineFollower {
  TimelineFollower({required this.nowUs, this.nudgeAboveUs = 120000});

  /// The timeline's clock (the host's, or the server's).
  final int Function() nowUs;

  /// Drift below this is left alone. Internet clocks are rougher than
  /// Wi-Fi ones, so online parties use a wider band.
  final int nudgeAboveUs;

  /// Steady-clock time until which corrections wait, after a catch-up seek,
  /// so the player can settle.
  int _settleUntilUs = 0;
  bool _rateNudged = false;

  /// A new state arrived: correct right away.
  void reset() => _settleUntilUs = 0;

  void follow(Player p, PartyState s) {
    final target = s.positionAt(nowUs());
    if (p.state.duration > Duration.zero &&
        target > p.state.duration.inMicroseconds) {
      return;
    }
    if (s.playing != p.state.playing) {
      s.playing ? p.play() : p.pause();
    }
    final pos = p.state.position.inMicroseconds;
    final err = pos - target;
    if (!s.playing) {
      if (err.abs() > 300000) p.seek(Duration(microseconds: target));
      _resetRate(p, s);
      return;
    }
    if (p.state.buffering || Clock.nowUs() < _settleUntilUs) return;
    if (err.abs() > 1500000) {
      // Aim a little ahead: the seek itself takes time.
      p.seek(Duration(microseconds: target + 400000));
      _settleUntilUs = Clock.nowUs() + 1500000;
      _resetRate(p, s);
    } else if (err.abs() > nudgeAboveUs) {
      final nudge = (err / 4000000).clamp(-0.08, 0.08);
      p.setRate(s.rate * (1 - nudge));
      _rateNudged = true;
    } else {
      _resetRate(p, s);
    }
  }

  void _resetRate(Player p, PartyState s) {
    if (_rateNudged || p.state.rate != s.rate) {
      p.setRate(s.rate);
      _rateNudged = false;
    }
  }
}
