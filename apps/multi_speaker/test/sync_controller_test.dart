import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:multi_speaker/src/sync/protocol.dart';
import 'package:multi_speaker/src/sync/sync_controller.dart';

import 'support/gen.dart';

/// A controller on a fake host clock. Each seek moves the clock on by
/// [seekCosts] (the last one repeats), like a real seek taking time.
class Rig {
  Rig({
    Duration? length = const Duration(minutes: 3),
    this.latencyUs = 0,
    Map<String, String?>? paths,
    List<int>? seekCosts,
  })  : paths = paths ?? {'a': '/music/a.mp3', 'b': '/music/b.m4a'},
        seekCosts = seekCosts ?? [249000] {
    engine = ScriptedEngine(length: length)
      ..onSeek = () {
        now += this.seekCosts[min(_seekIndex++, this.seekCosts.length - 1)];
      };
    sync = SyncController(
      engine: engine,
      hostNowUs: () => now,
      latencyUs: () => latencyUs,
      trackPath: (id) => this.paths[id],
      trackTitle: (id) => 'Title $id',
    );
  }

  int now = 5000000000000;
  int latencyUs;
  final Map<String, String?> paths;
  final List<int> seekCosts;
  int _seekIndex = 0;
  late final ScriptedEngine engine;
  late final SyncController sync;

  /// What [SyncController] should seek to for a playing state applied now.
  int? expectedSeek(PlayState s) {
    var startAt = now + 250000;
    final first = s.positionAt(startAt) + latencyUs;
    if (first < 0) startAt -= first;
    final seekTo = s.positionAt(startAt) + latencyUs;
    final len = engine.length;
    if (len != null && seekTo >= len.inMicroseconds) return null;
    return seekTo;
  }
}

Future<void> _ms(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

PlayState _paused(String? id, int pos) =>
    PlayState(trackId: id, playing: false, positionUs: pos, anchorUs: 0);

void main() {
  final rigs = <Rig>[];
  Rig rig({
    Duration? length = const Duration(minutes: 3),
    int latencyUs = 0,
    Map<String, String?>? paths,
    List<int>? seekCosts,
  }) {
    final r = Rig(
        length: length, latencyUs: latencyUs, paths: paths, seekCosts: seekCosts);
    rigs.add(r);
    return r;
  }

  tearDown(() async {
    for (final r in rigs) {
      await r.sync.dispose();
    }
    rigs.clear();
  });

  group('idle', () {
    test('starts idle with nothing loaded', () {
      final r = rig();
      expect(r.sync.phase.value, SyncPhase.idle);
      expect(r.sync.state.trackId, isNull);
      expect(r.sync.errorMs.value, isNull);
      expect(r.sync.duration, isNull);
    });
    test('applying the idle state loads nothing', () async {
      final r = rig();
      await r.sync.apply(PlayState.idle);
      expect(r.sync.phase.value, SyncPhase.idle);
      expect(r.engine.loads, isEmpty);
      expect(r.engine.seeks, isEmpty);
    });
  });

  group('paused state', () {
    final positions = [
      -5000000, -1, 0, 1, 999, 250000, 1000000, 30000000, 179999999, 400000000,
    ];
    for (final id in ['a', 'b']) {
      for (final pos in positions) {
        test('track $id paused at $pos us seeks to ${max(0, pos)}', () async {
          final r = rig();
          await r.sync.apply(_paused(id, pos));
          expect(r.sync.phase.value, SyncPhase.paused);
          expect(r.engine.loads, ['${r.paths[id]}|$id|Title $id']);
          expect(r.engine.seeks, [max(0, pos)]);
          expect(r.engine.plays, 0);
          expect(r.sync.duration, const Duration(minutes: 3));
          expect(r.sync.state.positionUs, pos);
        });
      }
    }
    test('the same song is loaded only once', () async {
      final r = rig();
      for (var i = 0; i < 5; i++) {
        await r.sync.apply(_paused('a', i * 1000000));
      }
      expect(r.engine.loads, hasLength(1));
      expect(r.engine.seeks, [0, 1000000, 2000000, 3000000, 4000000]);
    });
    test('switching songs loads the new one', () async {
      final r = rig();
      await r.sync.apply(_paused('a', 0));
      await r.sync.apply(_paused('b', 0));
      await r.sync.apply(_paused('a', 0));
      expect(r.engine.loads.map((l) => l.split('|')[1]), ['a', 'b', 'a']);
    });
    test('an unknown length is kept as null', () async {
      final r = rig(length: null);
      await r.sync.apply(_paused('a', 0));
      expect(r.sync.duration, isNull);
      expect(r.sync.phase.value, SyncPhase.paused);
    });
  });

  group('waiting for the song', () {
    for (final playing in [false, true]) {
      test('a ${playing ? 'playing' : 'paused'} state for a missing file waits', () async {
        final r = rig(paths: {'a': null});
        await r.sync.apply(PlayState(
            trackId: 'a', playing: playing, positionUs: 0, anchorUs: r.now));
        expect(r.sync.phase.value, SyncPhase.waitingForSong);
        expect(r.engine.loads, isEmpty);
      });
      test('${playing ? 'playing' : 'paused'}: the download finishing applies the state', () async {
        final r = rig(paths: {'a': null});
        await r.sync.apply(PlayState(
            trackId: 'a', playing: playing, positionUs: 0, anchorUs: r.now));
        r.paths['a'] = '/dl/a.mp3';
        r.sync.trackAvailable('a');
        await _ms(5);
        expect(r.engine.loads, ['/dl/a.mp3|a|Title a']);
        expect(r.sync.phase.value,
            playing ? isIn([SyncPhase.starting, SyncPhase.playing]) : SyncPhase.paused);
      });
    }
    test('another song finishing does nothing', () async {
      final r = rig(paths: {'a': null, 'b': '/b.mp3'});
      await r.sync.apply(_paused('a', 0));
      r.sync.trackAvailable('b');
      await _ms(5);
      expect(r.engine.loads, isEmpty);
      expect(r.sync.phase.value, SyncPhase.waitingForSong);
    });
    test('an already loaded song is not reloaded', () async {
      final r = rig();
      await r.sync.apply(_paused('a', 0));
      r.sync.trackAvailable('a');
      await _ms(5);
      expect(r.engine.loads, hasLength(1));
    });
  });

  group('scheduled start seeks to the right place', () {
    final rnd = Random(9);
    for (var i = 0; i < 60; i++) {
      final pos = rnd.nextInt(200000000);
      final anchorDelta = rnd.nextInt(6000000) - 3000000; // anchor vs now
      final latency = [0, 50000, 200000, 300000][i % 4];
      test('#$i pos $pos, anchor now${anchorDelta >= 0 ? '+' : ''}$anchorDelta, latency $latency', () async {
        final r = rig(latencyUs: latency);
        final s = PlayState(
            trackId: 'a', playing: true, positionUs: pos, anchorUs: r.now + anchorDelta);
        // Load first so loading doesn't change the clock.
        await r.sync.apply(_paused('a', 0));
        r.engine.seeks.clear();
        final expected = r.expectedSeek(s);
        await r.sync.apply(s);
        if (expected == null) {
          expect(r.engine.seeks, isEmpty);
          expect(r.sync.phase.value, SyncPhase.paused);
        } else {
          expect(r.engine.seeks, [expected]);
          expect(r.sync.phase.value, SyncPhase.starting);
        }
      });
    }
    for (final lead in [300000, 1000000, 2500000]) {
      for (final latency in [0, 200000]) {
        test('a start $lead us in the future with latency $latency seeks to 0', () async {
          final r = rig(latencyUs: latency);
          await r.sync.apply(_paused('a', 0));
          r.engine.seeks.clear();
          await r.sync.apply(PlayState(
              trackId: 'a', playing: true, positionUs: 0, anchorUs: r.now + lead));
          expect(r.engine.seeks, [max(0, 250000 - lead + latency)]);
        });
      }
    }
    for (final over in [0, 1, 1000000]) {
      test('a timeline $over us past the end of the song pauses', () async {
        final r = rig(length: const Duration(seconds: 10));
        await r.sync.apply(_paused('a', 0));
        r.engine.seeks.clear();
        await r.sync.apply(PlayState(
            trackId: 'a',
            playing: true,
            positionUs: 10000000 - 250000 + over,
            anchorUs: r.now));
        expect(r.engine.seeks, isEmpty);
        expect(r.sync.phase.value, SyncPhase.paused);
      });
    }
    test('just before the end it still starts', () async {
      final r = rig(length: const Duration(seconds: 10));
      await r.sync.apply(_paused('a', 0));
      await r.sync.apply(PlayState(
          trackId: 'a', playing: true, positionUs: 10000000 - 250001, anchorUs: r.now));
      expect(r.sync.phase.value, SyncPhase.starting);
    });
  });

  group('slow seeks are planned again', () {
    final plans = <List<int>, int>{
      [300000]: 4,
      [300000, 1000]: 2,
      [300000, 300000, 1000]: 3,
      [300000, 300000, 300000, 1000]: 4,
      [250001]: 4,
      [250000]: 1,
    };
    plans.forEach((costs, seeks) {
      test('seek costs $costs give $seeks seek(s)', () async {
        final r = rig(seekCosts: costs);
        final t0 = r.now;
        await r.sync.apply(
            PlayState(trackId: 'a', playing: true, positionUs: 0, anchorUs: t0 - 60000000));
        expect(r.engine.seeks, hasLength(seeks));
      });
    });
    test('giving up after three re-plans leaves it starting, not playing', () async {
      final r = rig(seekCosts: [400000]);
      await r.sync.apply(
          PlayState(trackId: 'a', playing: true, positionUs: 0, anchorUs: r.now - 1000000));
      await _ms(20);
      expect(r.engine.plays, 0);
      expect(r.sync.phase.value, SyncPhase.starting);
    });
  });

  group('starts playing on time', () {
    for (final latency in [0, 100000, 200000, 600000]) {
      for (final pos in [0, 42000000]) {
        test('latency $latency, pos $pos: plays once and is in sync', () async {
          final r = rig(latencyUs: latency);
          await r.sync.apply(PlayState(
              trackId: 'a', playing: true, positionUs: pos, anchorUs: r.now - 1000000));
          await _ms(30);
          expect(r.engine.plays, 1);
          expect(r.engine.playing, isTrue);
          expect(r.sync.phase.value, SyncPhase.playing);
          expect(r.engine.speeds, isEmpty, reason: 'speed was already 1');
        });
      }
    }
    test('pauses a running player before seeking for a new start', () async {
      final r = rig();
      r.engine.externalStart();
      await r.sync.apply(
          PlayState(trackId: 'a', playing: true, positionUs: 0, anchorUs: r.now));
      expect(r.engine.pauses, greaterThanOrEqualTo(1));
    });
    test('a newer state cancels a pending start', () async {
      final r = rig(seekCosts: [200000]); // 50 ms until the start
      await r.sync.apply(
          PlayState(trackId: 'a', playing: true, positionUs: 0, anchorUs: r.now));
      await r.sync.apply(_paused('a', 7000000));
      await _ms(80);
      expect(r.engine.plays, 0);
      expect(r.sync.phase.value, SyncPhase.paused);
    });
    test('pausing after playing pauses the player and seeks to the spot', () async {
      final r = rig();
      await r.sync.apply(
          PlayState(trackId: 'a', playing: true, positionUs: 0, anchorUs: r.now));
      await _ms(30);
      await r.sync.apply(_paused('a', 12345678));
      expect(r.engine.playing, isFalse);
      expect(r.engine.seeks.last, 12345678);
      expect(r.sync.phase.value, SyncPhase.paused);
    });
    test('going idle stops the player', () async {
      final r = rig();
      await r.sync.apply(
          PlayState(trackId: 'a', playing: true, positionUs: 0, anchorUs: r.now));
      await _ms(30);
      await r.sync.apply(PlayState.idle);
      expect(r.engine.playing, isFalse);
      expect(r.sync.phase.value, SyncPhase.idle);
    });
  });

  group('paused from outside', () {
    test('a pause from the notification is reported once', () async {
      final r = rig();
      var called = 0;
      r.sync.onPausedHere = () => called++;
      await r.sync.apply(
          PlayState(trackId: 'a', playing: true, positionUs: 0, anchorUs: r.now));
      await _ms(30);
      r.engine.externalStop();
      await _ms(5);
      expect(r.sync.phase.value, SyncPhase.pausedHere);
      expect(called, 1);
      expect(r.sync.errorMs.value, isNull);
      r.engine.externalStop();
      await _ms(5);
      expect(called, 1);
    });
    test('a stop while paused on purpose is not reported', () async {
      final r = rig();
      var called = 0;
      r.sync.onPausedHere = () => called++;
      await r.sync.apply(_paused('a', 0));
      r.engine.externalStop();
      await _ms(5);
      expect(called, 0);
      expect(r.sync.phase.value, SyncPhase.paused);
    });
    test('rejoin starts again on the shared timeline', () async {
      final r = rig();
      await r.sync.apply(
          PlayState(trackId: 'a', playing: true, positionUs: 0, anchorUs: r.now));
      await _ms(30);
      r.engine.externalStop();
      await _ms(5);
      await r.sync.rejoin();
      await _ms(30);
      expect(r.sync.phase.value, SyncPhase.playing);
      expect(r.engine.plays, 2);
    });
  });

  group('stop and dispose', () {
    test('stop forgets the song and goes idle', () async {
      final r = rig();
      await r.sync.apply(_paused('a', 5));
      await r.sync.stop();
      expect(r.sync.phase.value, SyncPhase.idle);
      expect(r.sync.state.trackId, isNull);
      await r.sync.apply(_paused('a', 5));
      expect(r.engine.loads, hasLength(2), reason: 'reloaded after stop');
    });
    test('stop cancels a pending start', () async {
      final r = rig(seekCosts: [200000]);
      await r.sync.apply(
          PlayState(trackId: 'a', playing: true, positionUs: 0, anchorUs: r.now));
      await r.sync.stop();
      await _ms(80);
      expect(r.engine.plays, 0);
    });
    test('nothing happens after dispose', () async {
      final r = rig();
      await r.sync.dispose();
      await r.sync.apply(_paused('a', 0));
      expect(r.engine.loads, isEmpty);
      expect(r.sync.phase.value, SyncPhase.idle);
    });
  });

  group('drift correction while playing', () {
    Future<Rig> playingRig(int latency) async {
      final r = rig(latencyUs: latency);
      await r.sync.apply(
          PlayState(trackId: 'a', playing: true, positionUs: 0, anchorUs: r.now - 10000000));
      await _ms(10);
      expect(r.sync.phase.value, SyncPhase.playing);
      r.now += 800000; // Past the warm-up.
      return r;
    }

    void driftBy(Rig r, int Function() errUs) {
      r.engine.positionOverride = () => Duration(
          microseconds: r.sync.state.positionAt(r.now) + r.latencyUs + errUs());
    }

    final cases = <int, double?>{
      0: null,
      10000: null,
      -10000: null,
      24000: null,
      30000: 0.97,
      -30000: 1.03,
      100000: 0.97,
      -140000: 1.03,
    };
    cases.forEach((err, speed) {
      test('$err us off ${speed == null ? 'is left alone' : 'plays at $speed'}', () async {
        final r = await playingRig(err.isEven && err > 0 ? 200000 : 0);
        driftBy(r, () => err);
        await _ms(320);
        expect(r.sync.errorMs.value, (err / 1000).round());
        expect(r.engine.speeds, speed == null ? isEmpty : [speed]);
        expect(r.engine.seeks, hasLength(1), reason: 'no resync');
      });
    });
    for (final err in [200000, -200000, 1000000]) {
      test('$err us off seeks and starts again', () async {
        final r = await playingRig(0);
        driftBy(r, () => err);
        await _ms(320);
        expect(r.engine.seeks.length, greaterThan(1));
      });
    }
    test('stops nudging once it overshoots', () async {
      final r = await playingRig(0);
      var err = 30000;
      driftBy(r, () => err);
      await _ms(320);
      expect(r.engine.speeds, [0.97]);
      err = -100000; // smoothed: 0.6 * 30 + 0.4 * -100 = -22 ms
      await _ms(260);
      expect(r.engine.speeds, [0.97, 1.0]);
      expect(r.sync.errorMs.value, -22);
    });
    test('right after the start positions are not trusted', () async {
      final r = rig();
      await r.sync.apply(
          PlayState(trackId: 'a', playing: true, positionUs: 0, anchorUs: r.now));
      await _ms(10);
      driftBy(r, () => 100000);
      await _ms(320);
      expect(r.sync.errorMs.value, isNull);
      expect(r.engine.speeds, isEmpty);
    });
  });
}
