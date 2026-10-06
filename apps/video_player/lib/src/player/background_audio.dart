import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:media_kit/media_kit.dart';

/// Keeps a video's sound playing with the screen off or in another app,
/// with play, pause and seek controls in the notification.
class BackgroundAudio {
  BackgroundAudio._();

  static final BackgroundAudio instance = BackgroundAudio._();

  _Handler? _handler;
  Future<void>? _init;

  bool get available => _handler != null;

  Future<void> init() => _init ??= _start();

  Future<void> _start() async {
    try {
      _handler = await AudioService.init(
        builder: _Handler.new,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'in.onlysoftware.video_player.audio',
          androidNotificationChannelName: 'Background playback',
          androidNotificationIcon: 'drawable/ic_stat_play',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );
    } catch (_) {
      _handler = null;
    }
  }

  /// Starts mirroring [player] into the media notification. Must be called
  /// while the app is on screen, because Android won't start the service
  /// from the background.
  Future<void> attach(Player player, String title) async {
    await init();
    _handler?.attach(player, title);
  }

  void detach() => _handler?.detach();
}

class _Handler extends BaseAudioHandler with SeekHandler {
  Player? _player;
  final _subs = <StreamSubscription>[];

  void attach(Player player, String title) {
    detach();
    _player = player;
    mediaItem.add(MediaItem(
      id: title,
      title: title,
      album: 'Video Player',
      duration: player.state.duration,
    ));
    _subs.addAll([
      player.stream.playing.listen((_) => _broadcast()),
      player.stream.buffering.listen((_) => _broadcast()),
      player.stream.rate.listen((_) => _broadcast()),
      player.stream.duration.listen((d) {
        final item = mediaItem.value;
        if (item != null) mediaItem.add(item.copyWith(duration: d));
      }),
      // Position only needs an occasional refresh; the notification
      // extrapolates between updates.
      Stream<void>.periodic(const Duration(seconds: 5)).listen((_) => _broadcast()),
    ]);
    _broadcast();
  }

  void detach() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    if (_player != null) {
      _player = null;
      playbackState.add(PlaybackState(processingState: AudioProcessingState.idle));
    }
  }

  void _broadcast() {
    final p = _player;
    if (p == null) return;
    final playing = p.state.playing;
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.rewind,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.fastForward,
        MediaControl.stop,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: p.state.buffering
          ? AudioProcessingState.buffering
          : AudioProcessingState.ready,
      playing: playing,
      updatePosition: p.state.position,
      speed: p.state.rate,
    ));
  }

  @override
  Future<void> play() async => _player?.play();

  @override
  Future<void> pause() async => _player?.pause();

  @override
  Future<void> seek(Duration position) async => _player?.seek(position);

  @override
  Future<void> fastForward() async {
    final p = _player;
    if (p != null) await p.seek(p.state.position + const Duration(seconds: 10));
  }

  @override
  Future<void> rewind() async {
    final p = _player;
    if (p == null) return;
    final t = p.state.position - const Duration(seconds: 10);
    await p.seek(t.isNegative ? Duration.zero : t);
  }

  @override
  Future<void> stop() async {
    await _player?.pause();
    detach();
    await super.stop();
  }
}
