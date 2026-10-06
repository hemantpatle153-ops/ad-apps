import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'audio_engine.dart';
import 'protocol.dart';

enum SyncPhase { idle, waitingForSong, paused, starting, playing, pausedHere }

/// Keeps this phone's player on the shared timeline in a [PlayState].
///
/// Starts are scheduled on the host clock, and while playing a loop compares
/// the player's position with where the timeline says it should be:
/// small drift is fixed by playing up to 3% faster or slower for a moment
/// (not audible), big jumps by seeking and restarting on schedule.
///
/// [latencyUs] is this phone's speaker delay (Bluetooth speakers add
/// 150-300 ms): the player runs that far ahead so the sound comes out on
/// time.
class SyncController {
  SyncController({
    required this.engine,
    required this.hostNowUs,
    required this.latencyUs,
    required this.trackPath,
    required this.trackTitle,
  }) {
    _playingSub = engine.playingChanges.listen(_onPlayingChanged);
  }

  final AudioEngine engine;
  final int Function() hostNowUs;
  final int Function() latencyUs;

  /// Local file for a song, or null while it is still downloading.
  final String? Function(String trackId) trackPath;
  final String Function(String trackId) trackTitle;

  /// Called when playback stops without us asking, e.g. from the pause
  /// button in the notification.
  VoidCallback? onPausedHere;

  final ValueNotifier<SyncPhase> phase = ValueNotifier(SyncPhase.idle);

  /// Smoothed difference between this phone and the timeline, in ms
  /// (positive means ahead). Null when not playing.
  final ValueNotifier<int?> errorMs = ValueNotifier(null);

  static const _hardResyncUs = 150000;
  static const _startNudgeUs = 25000;
  static const _stopNudgeUs = 8000;
  static const _nudge = 0.03;

  PlayState _state = PlayState.idle;
  PlayState get state => _state;
  String? _loadedId;
  Duration? _duration;
  Duration? get duration => _duration;

  int _gen = 0;
  Timer? _startTimer;
  Timer? _ticker;
  int _playStartedUs = 0;
  bool _expectPlaying = false;
  double _speed = 1;
  double? _smoothedErrUs;
  StreamSubscription<bool>? _playingSub;
  bool _disposed = false;

  Future<void> apply(PlayState s) async {
    if (_disposed) return;
    _state = s;
    final gen = ++_gen;
    _startTimer?.cancel();
    _resetDrift();
    final id = s.trackId;
    if (id == null) {
      await _pause();
      phase.value = SyncPhase.idle;
      return;
    }
    if (_loadedId != id) {
      final path = trackPath(id);
      await _pause();
      if (path == null) {
        phase.value = SyncPhase.waitingForSong;
        return; // trackAvailable() re-applies once the file is here.
      }
      _loadedId = null;
      _duration = await engine.load(path, id: id, title: trackTitle(id));
      if (gen != _gen) return;
      _loadedId = id;
    }
    if (!s.playing) {
      await _pause();
      await engine.seek(Duration(microseconds: math.max(0, s.positionUs)));
      phase.value = SyncPhase.paused;
      return;
    }
    await _scheduleStart(gen);
  }

  /// Tells the controller a song file finished downloading.
  void trackAvailable(String trackId) {
    if (_state.trackId == trackId && _loadedId != trackId) apply(_state);
  }

  /// Starts again after the user paused this phone only.
  Future<void> rejoin() => apply(_state);

  int _targetUs(int hostUs) => _state.positionAt(hostUs) + latencyUs();

  Future<void> _scheduleStart(int gen, [int attempt = 0]) async {
    phase.value = SyncPhase.starting;
    await _pause();
    await _setSpeed(1);
    // Leave time for the seek to finish before the start moment.
    var startAt = hostNowUs() + 250000;
    final first = _targetUs(startAt);
    if (first < 0) startAt -= first; // A start scheduled in the future.
    final seekTo = _targetUs(startAt);
    if (_duration != null && seekTo >= _duration!.inMicroseconds) {
      phase.value = SyncPhase.paused; // This song is over on the timeline.
      return;
    }
    await engine.seek(Duration(microseconds: seekTo));
    if (gen != _gen) return;
    final wait = startAt - hostNowUs();
    if (wait < 0) {
      // The seek was slower than planned; plan again with the new time.
      if (attempt < 3) await _scheduleStart(gen, attempt + 1);
      return;
    }
    _startTimer = Timer(Duration(microseconds: wait), () {
      if (gen != _gen || _disposed) return;
      _expectPlaying = true;
      engine.play();
      _playStartedUs = hostNowUs();
      phase.value = SyncPhase.playing;
      _ticker ??= Timer.periodic(const Duration(milliseconds: 250), _onTick);
    });
  }

  void _onTick(Timer _) {
    if (!_state.playing ||
        _loadedId != _state.trackId ||
        phase.value != SyncPhase.playing ||
        !engine.playing) {
      return;
    }
    final now = hostNowUs();
    // Positions right after a start are unreliable while the player warms up.
    if (now - _playStartedUs < 700000) return;
    final err = engine.position.inMicroseconds - _targetUs(now);
    final prev = _smoothedErrUs;
    final smooth = prev == null ? err.toDouble() : prev * 0.6 + err * 0.4;
    _smoothedErrUs = smooth;
    errorMs.value = (smooth / 1000).round();

    if (err.abs() > _hardResyncUs && smooth.abs() > _hardResyncUs) {
      _scheduleStart(_gen);
      return;
    }
    if (_speed != 1) {
      // Keep nudging until we are back within a few ms.
      final overshot = (_speed < 1 && smooth < 0) || (_speed > 1 && smooth > 0);
      if (smooth.abs() < _stopNudgeUs || overshot) _setSpeed(1);
    } else if (smooth.abs() > _startNudgeUs) {
      _setSpeed(smooth > 0 ? 1 - _nudge : 1 + _nudge);
    }
  }

  Future<void> _setSpeed(double s) async {
    if (_speed == s) return;
    _speed = s;
    await engine.setSpeed(s);
  }

  Future<void> _pause() async {
    _expectPlaying = false;
    if (engine.playing) await engine.pause();
  }

  void _resetDrift() {
    _smoothedErrUs = null;
    errorMs.value = null;
  }

  void _onPlayingChanged(bool playing) {
    if (playing || !_expectPlaying || _disposed) return;
    _expectPlaying = false;
    _startTimer?.cancel();
    _resetDrift();
    phase.value = SyncPhase.pausedHere;
    onPausedHere?.call();
  }

  /// Stops playback and forgets the loaded song.
  Future<void> stop() async {
    _gen++;
    _startTimer?.cancel();
    await _pause();
    _loadedId = null;
    _state = PlayState.idle;
    phase.value = SyncPhase.idle;
  }

  Future<void> dispose() async {
    _disposed = true;
    _gen++;
    _startTimer?.cancel();
    _ticker?.cancel();
    await _playingSub?.cancel();
    await _pause();
  }
}
