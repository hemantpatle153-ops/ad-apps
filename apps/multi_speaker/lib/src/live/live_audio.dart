import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Live mode: the host sends whatever its phone is playing (YouTube, a
/// music app, a game) to every speaker as it plays, instead of song files.
///
/// Sound travels as raw 16-bit stereo PCM at 48 kHz in 20 ms chunks:
/// 1.5 Mbit/s per speaker, easy for local Wi-Fi or a hotspot, and no codec
/// delay.
const liveSampleRate = 48000;
const liveChannels = 2;
const liveBytesPerFrame = 2 * liveChannels;

/// How long after the host captured a chunk every speaker plays it. It
/// covers the trip over Wi-Fi plus room for the hiccups Wi-Fi has.
const liveDelayUs = 400000;

/// First byte of a binary WebSocket message carrying sound.
const _liveTag = 0x4C; // 'L'

/// A chunk of sound and the host time it was captured at.
Uint8List encodeLiveFrame(int hostUs, Uint8List pcm) {
  final out = Uint8List(9 + pcm.length);
  out[0] = _liveTag;
  ByteData.sublistView(out).setInt64(1, hostUs, Endian.little);
  out.setRange(9, out.length, pcm);
  return out;
}

({int hostUs, Uint8List pcm})? decodeLiveFrame(Object? data) {
  if (data is! List<int> || data.length < 9 || data[0] != _liveTag) return null;
  final bytes = data is Uint8List ? data : Uint8List.fromList(data);
  final hostUs = ByteData.sublistView(bytes).getInt64(1, Endian.little);
  return (hostUs: hostUs, pcm: Uint8List.sublistView(bytes, 9));
}

/// Gives each chunk a steady timestamp. Chunks reach Dart a few ms early or
/// late; stamping each with its arrival time would make every speaker
/// stutter, so the clock follows arrivals slowly instead.
class LiveStamper {
  int? _nextUs;

  int stamp(int arrivedUs, int bytes) {
    final durationUs = bytes ~/ liveBytesPerFrame * 1000000 ~/ liveSampleRate;
    var next = _nextUs;
    if (next == null || (arrivedUs - next).abs() > 200000) {
      // First chunk, or capture paused for a while: start again.
      next = arrivedUs - durationUs;
    } else {
      next += (arrivedUs - durationUs - next) ~/ 100;
    }
    _nextUs = next + durationUs;
    return next;
  }

  void reset() => _nextUs = null;
}

/// Where the host's sound comes from.
abstract class LiveSource {
  /// Whether this phone can capture other apps' sound (Android 10+).
  Future<bool> supported();

  /// Asks Android for permission and starts capturing. False when the user
  /// said no.
  Future<bool> start();

  Stream<Uint8List> get chunks;

  Future<void> stop();
}

/// Plays the live sound on a speaker phone.
abstract class LiveOutput {
  Future<void> start();

  /// Queues [pcm] to come out of the speaker in [inUs] microseconds.
  void push(Uint8List pcm, int inUs);

  Future<void> setVolume(double volume);

  Future<void> stop();
}

const _channel = MethodChannel('in.onlysoftware.multi_speaker/native');
const _captureEvents = EventChannel('in.onlysoftware.multi_speaker/capture');

/// Android's playback capture, in CaptureService.kt.
class NativeLiveSource implements LiveSource {
  Stream<Uint8List>? _chunks;

  @override
  Future<bool> supported() async =>
      await _invoke<bool>('liveCaptureSupported') ?? false;

  @override
  Future<bool> start() async =>
      await _invoke<bool>('liveCaptureStart') ?? false;

  @override
  Stream<Uint8List> get chunks =>
      _chunks ??= _captureEvents.receiveBroadcastStream().cast<Uint8List>();

  @override
  Future<void> stop() => _invoke<void>('liveCaptureStop');
}

/// An AudioTrack that plays each chunk at its time, in LivePlayer.kt.
class NativeLiveOutput implements LiveOutput {
  @override
  Future<void> start() => _invoke<void>('livePlayStart');

  @override
  void push(Uint8List pcm, int inUs) {
    _channel.invokeMethod<void>('livePlayPush', {
      'pcm': pcm,
      'in': inUs,
    }).ignore();
  }

  @override
  Future<void> setVolume(double volume) =>
      _invoke<void>('livePlayVolume', {'v': volume});

  @override
  Future<void> stop() => _invoke<void>('livePlayStop');
}

Future<T?> _invoke<T>(String method, [Object? args]) async {
  try {
    return await _channel.invokeMethod<T>(method, args);
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}
