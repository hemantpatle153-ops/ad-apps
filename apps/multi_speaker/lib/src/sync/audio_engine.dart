import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

/// The little the sync code needs from a player, so tests can use a fake.
abstract class AudioEngine {
  /// Loads a song file and returns its length (null if unknown).
  Future<Duration?> load(String path, {required String id, required String title});

  Future<void> seek(Duration position);

  /// Starts playback and returns as soon as it has started.
  Future<void> play();

  Future<void> pause();

  Future<void> setSpeed(double speed);

  /// 0..1, this player only (the phone's own volume buttons still work).
  Future<void> setVolume(double volume);

  Duration get position;

  bool get playing;

  /// Fires when the loaded song plays to its end.
  Stream<void> get completed;

  /// Fires when playback stops or starts for any reason, including the
  /// pause button in the notification.
  Stream<bool> get playingChanges;

  Future<void> dispose();
}

/// The real player (ExoPlayer under just_audio), with the media
/// notification so music keeps playing when the screen is off.
class JustAudioEngine implements AudioEngine {
  final AudioPlayer _player = AudioPlayer();

  @override
  Future<Duration?> load(String path,
          {required String id, required String title}) =>
      _player.setAudioSource(
        AudioSource.file(
          path,
          tag: MediaItem(id: id, title: title, album: 'Multi Speaker'),
        ),
      );

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> play() {
    // just_audio's play() completes only when playback stops again.
    unawaited(_player.play());
    return Future.value();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Duration get position => _player.position;

  @override
  bool get playing => _player.playing;

  @override
  Stream<void> get completed => _player.processingStateStream
      .where((s) => s == ProcessingState.completed);

  @override
  Stream<bool> get playingChanges => _player.playingStream.distinct();

  @override
  Future<void> dispose() => _player.dispose();
}
