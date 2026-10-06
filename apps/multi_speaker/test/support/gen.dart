import 'dart:async';
import 'dart:math';

import 'package:multi_speaker/src/sync/audio_engine.dart';

/// Names people give their phones, including characters that need escaping
/// in a URL query.
const trickyNames = <String>[
  'Host',
  "Rahul's phone",
  'Pixel 8 Pro',
  'Galaxy S24+',
  'A&B',
  'x=y',
  'what?',
  '#1 party',
  'comma, here',
  '100%',
  'slash/back\\slash',
  'émilie',
  'Ünïcödé',
  'पार्टी',
  '派对',
  'パーティー',
  '🎉 party 🎶',
  'tab\there',
  'a b  c',
  ' spaced ',
  'semi;colon',
  'quote"s',
  '<tag>',
  'plus+minus-',
  'dots...',
  'ALLCAPS',
  'tilde~',
  'at@sign',
  'colon:name',
  'brackets[]{}',
];

String randomIp(Random r) =>
    '${r.nextInt(256)}.${r.nextInt(256)}.${r.nextInt(256)}.${r.nextInt(256)}';

String randomId(Random r) => List.generate(
    8, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

const extensions = ['mp3', 'm4a', 'aac', 'flac', 'ogg', 'wav', 'opus'];

/// A player that only records what it was asked to do. Position is whatever
/// the test says, so the sync logic can be checked without real time.
class ScriptedEngine implements AudioEngine {
  ScriptedEngine({this.length = const Duration(minutes: 3)});

  Duration? length;
  final List<String> loads = [];
  final List<int> seeks = [];
  final List<double> speeds = [];
  int plays = 0;
  int pauses = 0;
  bool _playing = false;
  Duration _pos = Duration.zero;

  /// When set, [position] reports this instead of the last seek.
  Duration Function()? positionOverride;

  /// Runs after each seek, e.g. to move a fake clock along.
  void Function()? onSeek;

  final _playingChanges = StreamController<bool>.broadcast();

  @override
  Future<Duration?> load(String path,
      {required String id, required String title}) async {
    loads.add('$path|$id|$title');
    return length;
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position.inMicroseconds);
    _pos = position;
    onSeek?.call();
  }

  @override
  Future<void> play() async {
    plays++;
    _playing = true;
  }

  @override
  Future<void> pause() async {
    pauses++;
    _playing = false;
  }

  @override
  Future<void> setSpeed(double speed) async => speeds.add(speed);

  final List<double> volumes = [];

  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);

  @override
  Duration get position => positionOverride?.call() ?? _pos;

  @override
  bool get playing => _playing;

  /// Playback stopped by something other than the sync code.
  void externalStop() {
    _playing = false;
    _playingChanges.add(false);
  }

  void externalStart() {
    _playing = true;
    _playingChanges.add(true);
  }

  @override
  Stream<void> get completed => const Stream.empty();

  @override
  Stream<bool> get playingChanges => _playingChanges.stream;

  @override
  Future<void> dispose() async {}
}

/// A random non-negative int up to about 2^50, like a microsecond clock.
int randomBig(Random r) => r.nextInt(1 << 30) * (1 << 20) + r.nextInt(1 << 20);
