// Play Store screenshots. Run: flutter test screenshots/store_test.dart --update-goldens
//
// The host screen runs for real: a real PartyHost on a loopback socket, with
// three pretend guest phones joining over WebSocket, and a fake just_audio
// platform standing in for ExoPlayer.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:multi_speaker/src/app.dart';
import 'package:multi_speaker/src/net/party_host.dart';
import 'package:multi_speaker/src/settings.dart';
import 'package:multi_speaker/src/sync/protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../tool/screenshots/shot.dart';

// ---- Fake platform -------------------------------------------------------

class _FakeJustAudio extends JustAudioPlatform {
  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async =>
      _FakePlayer(request.id);

  @override
  Future<DisposePlayerResponse> disposePlayer(DisposePlayerRequest request) async =>
      DisposePlayerResponse();

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
          DisposeAllPlayersRequest request) async =>
      DisposeAllPlayersResponse();
}

class _FakePlayer extends AudioPlayerPlatform {
  _FakePlayer(super.id);

  static const length = Duration(minutes: 3, seconds: 42);
  final _events = StreamController<PlaybackEventMessage>.broadcast();
  final _data = StreamController<PlayerDataMessage>.broadcast();
  Duration _pos = Duration.zero;
  DateTime _since = DateTime.now();
  bool _playing = false;
  bool _loaded = false;

  Duration get _now =>
      _playing ? _pos + DateTime.now().difference(_since) : _pos;

  void _emit() {
    _events.add(PlaybackEventMessage(
      processingState:
          _loaded ? ProcessingStateMessage.ready : ProcessingStateMessage.idle,
      updateTime: DateTime.now(),
      updatePosition: _now,
      bufferedPosition: length,
      duration: _loaded ? length : null,
      icyMetadata: null,
      currentIndex: 0,
      androidAudioSessionId: null,
    ));
  }

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;
  @override
  Stream<PlayerDataMessage> get playerDataMessageStream => _data.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    _loaded = true;
    _pos = Duration.zero;
    _emit();
    return LoadResponse(duration: length);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    _pos = _now;
    _since = DateTime.now();
    _playing = true;
    _data.add(PlayerDataMessage(playing: true));
    _emit();
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    _pos = _now;
    _playing = false;
    _data.add(PlayerDataMessage(playing: false));
    _emit();
    return PauseResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    _pos = request.position ?? Duration.zero;
    _since = DateTime.now();
    _emit();
    return SeekResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();
  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();
  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async =>
      SetPitchResponse();
  @override
  Future<SetSkipSilenceResponse> setSkipSilence(SetSkipSilenceRequest request) async =>
      SetSkipSilenceResponse();
  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();
  @override
  Future<SetShuffleModeResponse> setShuffleMode(SetShuffleModeRequest request) async =>
      SetShuffleModeResponse();
  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(SetShuffleOrderRequest request) async =>
      SetShuffleOrderResponse();
  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
          SetAndroidAudioAttributesRequest request) async =>
      SetAndroidAudioAttributesResponse();
  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse>
      setAutomaticallyWaitsToMinimizeStalling(
              SetAutomaticallyWaitsToMinimizeStallingRequest request) async =>
          SetAutomaticallyWaitsToMinimizeStallingResponse();
  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    _playing = false;
    return DisposeResponse();
  }
}

late Directory _tmp;

void _mockChannels() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(
      const MethodChannel('in.onlysoftware.multi_speaker/native'), (call) async {
    switch (call.method) {
      case 'deviceName':
        return 'Pixel 8';
      case 'audioOutput':
        return {'bluetooth': true, 'name': 'JBL Charge 5'};
      case 'liveCaptureSupported':
      case 'liveCaptureStart':
        return true;
      case 'bluetoothFeatures':
        return {'maker': 'Google', 'leAudioBroadcast': false};
    }
    return null;
  });
  // Live capture: no audio chunks arrive, the stream just stays open.
  m.setMockStreamHandler(const EventChannel('in.onlysoftware.multi_speaker/capture'),
      MockStreamHandler.inline(onListen: (_, _) {}));
  m.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), (call) async {
    return _tmp.path;
  });
  m.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.audio_session'), (call) async => null);
  m.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.android_audio_manager'), (call) async => null);
}

// ---- Pretend guest phones ------------------------------------------------

class _Guest {
  _Guest(this.name, {required this.out, required this.bt, required this.vol, this.delay = 0});
  final String name;
  final String out;
  final bool bt;
  final int vol;
  final int delay;
  WebSocket? ws;

  Future<void> join(int port) async {
    final s = await WebSocket.connect('ws://127.0.0.1:$port/ws');
    ws = s;
    s.listen((_) {}, onError: (_) {});
    s.add(encodeMessage('hi', {'name': name}));
    s.add(encodeMessage('info',
        {'vol': vol, 'muted': false, 'delay': delay, 'out': out, 'bt': bt}));
  }

  void ready(Iterable<String> ids, int err) {
    for (final id in ids) {
      ws?.add(encodeMessage('ready', {'id': id}));
    }
    ws?.add(encodeMessage('ping', {'c': 0, 'err': err}));
  }
}

const _songs = [
  'Summer Nights',
  'Midnight Drive',
  'Golden Hour Groove',
  'Neon Skyline',
  'Ocean Breeze',
  'Dance All Night',
];

Future<Settings> _settings() async {
  SharedPreferences.setMockInitialValues({'seen_intro': true, 'name': 'Pixel 8'});
  return Settings.load();
}

/// Paint real elevation shadows from the first frame (see water_habit).
void _realShadows() {
  debugDisableShadows = false;
  addTearDown(() => debugDisableShadows = true);
}

/// Runs [f] to completion, alternating real time (for sockets and files)
/// with test frames (for work scheduled in the test's fake zone).
Future<T> drive<T>(WidgetTester tester, Future<T> f) async {
  var done = false;
  late T value;
  Object? error;
  f.then((v) {
    value = v;
    done = true;
  }, onError: (Object e) {
    error = e;
    done = true;
  });
  for (var i = 0; !done; i++) {
    if (i > 600) throw StateError('drive timed out');
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  if (error != null) throw error!;
  return value;
}

Future<void> waitReal(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    await loadRealFonts();
    JustAudioPlatform.instance = _FakeJustAudio();
  });
  setUp(() async {
    _tmp = await Directory.systemTemp.createTemp('ms_shots');
    _mockChannels();
  });

  testWidgets('home', (tester) async {
    usePhone(tester);
    _realShadows();
    final s = await _settings();
    await tester.pumpWidget(MultiSpeakerApp(settings: s));
    await tester.pump(const Duration(milliseconds: 900));
    await shot(tester, '01_home');
  });

  // Starts the host screen, adds songs, lets three guests join and plays.
  Future<PartyHost> party(WidgetTester tester, {bool play = true}) async {
    final s = await _settings();
    await tester.pumpWidget(MultiSpeakerApp(settings: s));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Host a party'));
    await tester.pump(const Duration(milliseconds: 500));
    await settleReal(tester);
    PartyHost? host;
    for (final w in tester.widgetList<ListenableBuilder>(find.byType(ListenableBuilder))) {
      if (w.listenable is PartyHost) host = w.listenable as PartyHost;
    }
    expect(host, isNotNull, reason: 'host did not start');
    final h = host!;
    await drive(tester, () async {
      for (var i = 0; i < _songs.length; i++) {
        final f = File('${_tmp.path}/song$i.mp3');
        await f.writeAsBytes(List.filled(2048, i));
        await h.addTrack(f.path, _songs[i]);
      }
    }());
    final guests = [
      _Guest("Rahul's Galaxy", out: 'Bluetooth: Bose SoundLink', bt: true, vol: 80, delay: 180),
      _Guest('Kitchen phone', out: 'Phone speaker or wired', bt: false, vol: 55),
      _Guest('Moto G', out: 'Bluetooth: Sony SRS-XB13', bt: true, vol: 95, delay: 220),
    ];
    for (final g in guests) {
      await drive(tester, g.join(h.port));
    }
    await waitReal(tester, 300);
    for (final (i, g) in guests.indexed) {
      g.ready(h.playlist.map((t) => t.id), 4 + i * 3);
    }
    await waitReal(tester, 300);
    expect(h.guests.length, 3);
    if (play) {
      await drive(tester, h.playTrack(h.playlist[1].id));
      await waitReal(tester, 1500);
      await drive(tester, h.seek(const Duration(minutes: 1, seconds: 18)));
      await waitReal(tester, 1500);
    }
    await settleReal(tester);
    addTearDown(() async {
      for (final g in guests) {
        unawaited(g.ws?.close());
      }
    });
    return h;
  }

  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settleReal(tester, rounds: 10);
  }

  testWidgets('player', (tester) async {
    usePhone(tester);
    _realShadows();
    await party(tester);
    await tester.tap(find.text('Songs'));
    await tester.pump(const Duration(milliseconds: 500));
    await settleReal(tester, rounds: 6);
    await shot(tester, '02_player');
    await leave(tester);
  });

  testWidgets('speakers', (tester) async {
    usePhone(tester);
    _realShadows();
    await party(tester);
    await tester.tap(find.text('Speakers'));
    await tester.pump(const Duration(milliseconds: 500));
    await settleReal(tester, rounds: 6);
    await shot(tester, '03_speakers');
    await leave(tester);
  });

  testWidgets('live', (tester) async {
    usePhone(tester);
    _realShadows();
    final h = await party(tester, play: false);
    expect(await drive(tester, h.startLive()), isTrue);
    await tester.pump(const Duration(milliseconds: 500));
    await settleReal(tester, rounds: 6);
    await shot(tester, '04_live');
    await leave(tester);
  });
}
