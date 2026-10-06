import 'dart:async';

import 'package:multi_speaker/src/sync/audio_engine.dart';
import 'package:multi_speaker/src/sync/clock.dart';

/// A pretend player on the real clock. Like a real one it takes a moment
/// to actually start after play() ([startDelay]), which the sync loop has
/// to correct.
class FakeEngine implements AudioEngine {
  FakeEngine({this.startDelay = Duration.zero, this.length = const Duration(minutes: 3)});

  final Duration startDelay;
  final Duration length;
  String? loaded;
  bool _playing = false;
  double _speed = 1;
  int _baseUs = 0;
  int _sinceUs = 0;
  final _completed = StreamController<void>.broadcast();
  final _playingChanges = StreamController<bool>.broadcast();
  final List<double> speeds = [];
  double volume = 1;

  @override
  Future<void> setVolume(double v) async => volume = v;

  @override
  Future<Duration?> load(String path, {required String id, required String title}) async {
    loaded = path;
    _baseUs = 0;
    return length;
  }

  int get _nowPosUs {
    if (!_playing) return _baseUs;
    final elapsed = Clock.nowUs() - _sinceUs;
    return elapsed < 0 ? _baseUs : _baseUs + (elapsed * _speed).round();
  }

  @override
  Duration get position => Duration(microseconds: _nowPosUs);

  @override
  bool get playing => _playing;

  @override
  Future<void> seek(Duration position) async {
    _baseUs = position.inMicroseconds;
    _sinceUs = Clock.nowUs();
  }

  @override
  Future<void> play() async {
    _baseUs = _nowPosUs;
    _playing = true;
    _sinceUs = Clock.nowUs() + startDelay.inMicroseconds;
    _playingChanges.add(true);
  }

  @override
  Future<void> pause() async {
    _baseUs = _nowPosUs;
    _playing = false;
    _playingChanges.add(false);
  }

  @override
  Future<void> setSpeed(double speed) async {
    _baseUs = _nowPosUs;
    _sinceUs = Clock.nowUs() > _sinceUs ? Clock.nowUs() : _sinceUs;
    _speed = speed;
    speeds.add(speed);
  }

  /// Simulates the user pressing pause in the notification.
  void userPause() {
    _baseUs = _nowPosUs;
    _playing = false;
    _playingChanges.add(false);
  }

  void finish() => _completed.add(null);

  @override
  Stream<void> get completed => _completed.stream;

  @override
  Stream<bool> get playingChanges => _playingChanges.stream;

  @override
  Future<void> dispose() async {}
}
