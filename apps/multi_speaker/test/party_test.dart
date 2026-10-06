import 'dart:async';
import 'dart:io';

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:multi_speaker/src/live/live_audio.dart';
import 'package:multi_speaker/src/net/party_guest.dart';
import 'package:multi_speaker/src/net/party_host.dart';
import 'package:multi_speaker/src/sync/clock.dart';
import 'package:multi_speaker/src/sync/protocol.dart';
import 'package:multi_speaker/src/sync/speaker.dart';
import 'package:multi_speaker/src/sync/sync_controller.dart';

import 'fake_engine.dart';

/// A real host and real guests talking over this machine's network, with
/// pretend players. Checks songs reach every phone and they play together.
void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('msync'));
  tearDown(() async => tmp.delete(recursive: true));

  Future<void> waitFor(bool Function() ok, {int seconds = 10}) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (!ok()) {
      if (DateTime.now().isAfter(end)) throw TimeoutException('condition');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<PartyGuest> join(PartyHost host, String name, FakeEngine engine,
      {int latencyMs = 0, LiveOutput? live}) async {
    final dir = await Directory('${tmp.path}/$name').create();
    final g = PartyGuest(
      engine: engine,
      code: JoinCode(hosts: ['10.255.255.1', '127.0.0.1'], port: host.port, name: 'host'),
      name: name,
      folder: dir,
      speaker: SimpleSpeaker(delayMs: latencyMs),
      liveOutput: live,
    );
    await g.connect();
    return g;
  }

  test('two guests download the song and play in sync with the host', () async {
    final hostEngine = FakeEngine();
    final host = PartyHost(engine: hostEngine, name: 'host', speaker: SimpleSpeaker());
    await host.start(beacon: false);
    // Songs bigger than one network chunk.
    final song = File('${tmp.path}/song.mp3')..writeAsBytesSync(List.filled(300000, 7));
    await host.addTrack(song.path, 'Song');

    // One guest starts late like a real player; one has a Bluetooth delay.
    final slow = FakeEngine(startDelay: const Duration(milliseconds: 60));
    final bt = FakeEngine();
    final g1 = await join(host, 'slow', slow);
    final g2 = await join(host, 'bt', bt, latencyMs: 200);
    expect(g1.status, GuestStatus.connected);
    await waitFor(() => host.guests.length == 2);

    await host.play();
    await waitFor(() => g1.sync.phase.value == SyncPhase.playing &&
        g2.sync.phase.value == SyncPhase.playing);
    expect(File(slow.loaded!).lengthSync(), 300000);
    expect(g1.current!.title, 'Song');

    // The sync loop removes the 60 ms start lag within a few seconds.
    int errUs(FakeEngine e, int latencyUs) =>
        e.position.inMicroseconds - (host.state.positionAt(Clock.nowUs()) + latencyUs);
    bool allInSync() =>
        errUs(hostEngine, 0).abs() < 15000 &&
        errUs(slow, 0).abs() < 15000 &&
        errUs(bt, 200000).abs() < 15000;
    await waitFor(() => allInSync(), seconds: 12);
    // And they stay there.
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(errUs(slow, 0).abs(), lessThan(25000), reason: 'slow guest');
    expect(errUs(bt, 200000).abs(), lessThan(25000), reason: 'bluetooth guest');
    expect(slow.speeds, contains(greaterThan(1.0)), reason: 'caught up by nudging');

    // Pause and seek reach everyone.
    await host.pause();
    await waitFor(() => !slow.playing && !bt.playing);
    await host.seek(const Duration(seconds: 30));
    await host.play();
    await waitFor(() => bt.playing && slow.playing);
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(bt.position.inMilliseconds, inInclusiveRange(30000, 33500));

    await g1.leave();
    await waitFor(() => host.guests.length == 1);
    await host.close();
    await waitFor(() => g2.status == GuestStatus.hostLeft);
    await g2.leave();
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('a guest that joins mid-song starts at the right place', () async {
    final host = PartyHost(engine: FakeEngine(), name: 'host', speaker: SimpleSpeaker());
    await host.start(beacon: false);
    final song = File('${tmp.path}/a.m4a')..writeAsBytesSync(List.filled(1000, 1));
    await host.addTrack(song.path, 'A');
    await host.play();
    await Future<void>.delayed(const Duration(seconds: 2));

    final late = FakeEngine();
    final g = await join(host, 'late', late);
    await waitFor(() => g.sync.phase.value == SyncPhase.playing);
    await Future<void>.delayed(const Duration(seconds: 1));
    final target = host.state.positionAt(Clock.nowUs());
    expect((late.position.inMicroseconds - target).abs(), lessThan(15000));
    expect(late.loaded, endsWith('.m4a'));
    await g.leave();
    await host.close();
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('next song plays on every phone when one ends', () async {
    final hostEngine = FakeEngine();
    final host = PartyHost(engine: hostEngine, name: 'host', speaker: SimpleSpeaker());
    await host.start(beacon: false);
    for (final n in ['one', 'two']) {
      final f = File('${tmp.path}/$n.mp3')..writeAsBytesSync(List.filled(500, 2));
      await host.addTrack(f.path, n);
    }
    final guestEngine = FakeEngine();
    final g = await join(host, 'g', guestEngine);
    await waitFor(() => host.guests.length == 1 && host.guests.single.ready.length == 2);
    await host.play();
    await waitFor(() => guestEngine.playing);
    hostEngine.finish();
    await waitFor(() => g.current?.title == 'two' && guestEngine.playing);
    expect(host.current!.title, 'two');
    await g.leave();
    await host.close();
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('pausing from the host notification pauses the party', () async {
    final hostEngine = FakeEngine();
    final host = PartyHost(engine: hostEngine, name: 'host', speaker: SimpleSpeaker());
    await host.start(beacon: false);
    final f = File('${tmp.path}/x.mp3')..writeAsBytesSync(List.filled(500, 2));
    await host.addTrack(f.path, 'x');
    await host.play();
    await waitFor(() => hostEngine.playing);
    hostEngine.userPause();
    await waitFor(() => !host.state.playing);
    await host.close();
  });

  test('the host sets each speaker\'s volume, mute and delay, and can remove one',
      () async {
    final hostEngine = FakeEngine();
    final host = PartyHost(engine: hostEngine, name: 'host', speaker: SimpleSpeaker());
    await host.start(beacon: false);
    final aEngine = FakeEngine();
    final bEngine = FakeEngine();
    final a = await join(host, 'a', aEngine);
    final b = await join(host, 'b', bEngine, latencyMs: 200);
    await waitFor(() => host.guests.length == 2 &&
        host.guests.every((g) => g.name != 'Phone'));
    final ga = host.guests.firstWhere((g) => g.name == 'a');
    final gb = host.guests.firstWhere((g) => g.name == 'b');
    // Each guest reported its own setup.
    await waitFor(() => gb.delayMs == 200);

    host.setGuestLevel(ga, const SpeakerLevel(volume: 0.3));
    host.setGuestLevel(gb, const SpeakerLevel(volume: 0.8, muted: true));
    await waitFor(() => aEngine.volume == 0.3 && bEngine.volume == 0);
    expect(a.level.volume, 0.3);
    expect(b.level.muted, isTrue);

    // The guest changes its own volume; the host's list follows.
    a.setLevel(const SpeakerLevel(volume: 0.5));
    await waitFor(() => ga.level.volume == 0.5);

    host.setGuestDelay(gb, 260);
    await waitFor(() => b.speaker.delayMs == 260);

    host.setLevel(const SpeakerLevel(volume: 0.6));
    expect(hostEngine.volume, 0.6);

    await host.kick(ga);
    await waitFor(() => a.status == GuestStatus.removed);
    expect(host.guests.map((g) => g.name), ['b']);
    await a.leave();
    await b.leave();
    await host.close();
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('repeat starts the playlist again; songs can be reordered', () async {
    final hostEngine = FakeEngine();
    final host = PartyHost(engine: hostEngine, name: 'host', speaker: SimpleSpeaker());
    await host.start(beacon: false);
    for (final n in ['one', 'two', 'three']) {
      final f = File('${tmp.path}/$n.mp3')..writeAsBytesSync(List.filled(100, 3));
      await host.addTrack(f.path, n);
    }
    host.moveTrack(2, 0);
    expect(host.playlist.map((t) => t.title), ['three', 'one', 'two']);
    host.toggleRepeat();
    await host.playTrack(host.playlist.last.id);
    await waitFor(() => hostEngine.playing);
    hostEngine.finish();
    await waitFor(() => host.current?.title == 'three' && host.state.playing);
    await host.close();
  });

  test('live: what the host phone plays reaches every speaker on time', () async {
    final source = FakeLiveSource();
    final host = PartyHost(
        engine: FakeEngine(), name: 'host', speaker: SimpleSpeaker(), liveSource: source);
    await host.start(beacon: false);
    final song = File('${tmp.path}/song.mp3')..writeAsBytesSync(List.filled(100, 1));
    await host.addTrack(song.path, 'Song');
    final out1 = FakeLiveOutput();
    final out2 = FakeLiveOutput();
    final g1 = await join(host, 'one', FakeEngine(), live: out1);
    final g2 = await join(host, 'two', FakeEngine(), latencyMs: 200, live: out2);
    await waitFor(() => host.guests.length == 2 && g1.clock.hasEstimate && g2.clock.hasEstimate);

    // The user said no to Android's prompt.
    source.allow = false;
    expect(await host.startLive(), isFalse);
    expect(host.live, isFalse);

    source.allow = true;
    expect(await host.startLive(), isTrue);
    await waitFor(() => g1.live && g2.live && out1.started && out2.started);

    // 20 ms chunks, as the phone captures them.
    for (var i = 0; i < 10; i++) {
      source.emit(Uint8List.fromList(List.filled(3840, i)));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await waitFor(() => out1.pushes.length == 10 && out2.pushes.length == 10);
    expect(out1.pushes.last.pcm.first, 9);
    expect(out1.pushes.first.pcm.length, 3840);
    // Each chunk plays the live delay after capture, the Bluetooth speaker
    // 200 ms sooner to make up for its own delay.
    for (final p in out1.pushes) {
      expect(p.inUs, inInclusiveRange(liveDelayUs - 80000, liveDelayUs));
    }
    for (var i = 0; i < 10; i++) {
      final gap = out1.pushes[i].inUs - out2.pushes[i].inUs;
      expect(gap, inInclusiveRange(200000 - 30000, 200000 + 30000));
    }

    // Each speaker's volume reaches its live player.
    host.setGuestLevel(host.guests.first, const SpeakerLevel(volume: 0.4));
    await waitFor(() => out1.volume == 0.4 || out2.volume == 0.4);

    // Playing a song ends live mode everywhere.
    await host.play();
    expect(host.live, isFalse);
    expect(source.stopped, isTrue);
    await waitFor(() => !g1.live && out1.stopped && !g2.live);
    await waitFor(() => g1.sync.phase.value == SyncPhase.playing);

    // Android stopping the capture (its notification) ends live too.
    await host.startLive();
    await waitFor(() => g1.live);
    source.emit(Uint8List(0));
    await waitFor(() => !host.live && !g1.live);

    await g1.leave();
    await g2.leave();
    await host.close();
  }, timeout: const Timeout(Duration(seconds: 40)));
}

class FakeLiveSource implements LiveSource {
  bool allow = true;
  bool stopped = false;
  final _chunks = StreamController<Uint8List>.broadcast();

  void emit(Uint8List pcm) => _chunks.add(pcm);

  @override
  Future<bool> supported() async => true;

  @override
  Future<bool> start() async {
    stopped = false;
    return allow;
  }

  @override
  Stream<Uint8List> get chunks => _chunks.stream;

  @override
  Future<void> stop() async => stopped = true;
}

class FakeLiveOutput implements LiveOutput {
  bool started = false;
  bool stopped = false;
  double volume = 1;
  final pushes = <({Uint8List pcm, int inUs})>[];

  @override
  Future<void> start() async => started = true;

  @override
  void push(Uint8List pcm, int inUs) => pushes.add((pcm: Uint8List.fromList(pcm), inUs: inUs));

  @override
  Future<void> setVolume(double v) async => volume = v;

  @override
  Future<void> stop() async => stopped = true;
}
