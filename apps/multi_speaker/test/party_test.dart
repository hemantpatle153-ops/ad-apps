import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:multi_speaker/src/net/party_guest.dart';
import 'package:multi_speaker/src/net/party_host.dart';
import 'package:multi_speaker/src/sync/clock.dart';
import 'package:multi_speaker/src/sync/protocol.dart';
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
      {int latencyMs = 0}) async {
    final dir = await Directory('${tmp.path}/$name').create();
    final g = PartyGuest(
      engine: engine,
      code: JoinCode(hosts: ['10.255.255.1', '127.0.0.1'], port: host.port, name: 'host'),
      name: name,
      folder: dir,
      latencyUs: () => latencyMs * 1000,
    );
    await g.connect();
    return g;
  }

  test('two guests download the song and play in sync with the host', () async {
    final hostEngine = FakeEngine();
    final host = PartyHost(engine: hostEngine, name: 'host', latencyUs: () => 0);
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
    final host = PartyHost(engine: FakeEngine(), name: 'host', latencyUs: () => 0);
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
    final host = PartyHost(engine: hostEngine, name: 'host', latencyUs: () => 0);
    await host.start(beacon: false);
    for (final n in ['one', 'two']) {
      final f = File('${tmp.path}/$n.mp3')..writeAsBytesSync(List.filled(500, 2));
      await host.addTrack(f.path, n);
    }
    final guestEngine = FakeEngine();
    final g = await join(host, 'g', guestEngine);
    await waitFor(() => host.guests.single.ready.length == 2);
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
    final host = PartyHost(engine: hostEngine, name: 'host', latencyUs: () => 0);
    await host.start(beacon: false);
    final f = File('${tmp.path}/x.mp3')..writeAsBytesSync(List.filled(500, 2));
    await host.addTrack(f.path, 'x');
    await host.play();
    await waitFor(() => hostEngine.playing);
    hostEngine.userPause();
    await waitFor(() => !host.state.playing);
    await host.close();
  });
}
