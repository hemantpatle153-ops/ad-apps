import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:snakes_ladders/ludo/engine.dart';
import 'package:snakes_ladders/ludo/match.dart';
import 'package:snakes_ladders/ludo/online/backend.dart';

const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

Map<String, dynamic> roundTrip(Map<String, dynamic> j) =>
    jsonDecode(jsonEncode(j)) as Map<String, dynamic>;

RoomState room(int size, Map<int, Seat> seats, {bool started = false}) =>
    RoomState(
        code: 'ABC234',
        size: size,
        rules: const GameRules(tokens: 2),
        seats: seats,
        started: started);

void main() {
  group('room codes', () {
    for (var seed = 0; seed < 120; seed++) {
      test('seed $seed gives a readable 6 character code', () {
        final code = newRoomCode(Random(seed));
        expect(code.length, 6);
        for (final ch in code.split('')) {
          expect(alphabet.contains(ch), isTrue, reason: ch);
        }
        // No look-alike characters, and typing it back changes nothing.
        expect(code, isNot(matches(RegExp('[01IOL]'))));
        expect(cleanCode(code), code);
        expect(cleanCode(code.toLowerCase()), code);
        expect(cleanCode('${code.substring(0, 3)}-${code.substring(3)}'), code);
        expect(newRoomCode(Random(seed)), code);
      });
    }

    test('codes are spread out', () {
      final r = Random(1);
      final codes = {for (var i = 0; i < 500; i++) newRoomCode(r)};
      expect(codes.length, 500);
    });

    test('secure default codes are valid too', () {
      for (var i = 0; i < 20; i++) {
        expect(newRoomCode(), matches(RegExp(r'^[A-HJKMNP-Z2-9]{6}$')));
      }
    });

    final typed = <String, String>{
      'abc234': 'ABC234',
      ' ABC 234 ': 'ABC234',
      'abc-234': 'ABC234',
      'a.b.c.2.3.4': 'ABC234',
      '': '',
      '   ': '',
      'ab_c2#34!': 'ABC234',
      'xyz\n789': 'XYZ789',
      'ÄBC234': 'BC234',
      'abc2345678': 'ABC2345678',
      '+91 98': '9198',
    };
    typed.forEach((raw, clean) {
      test('typing ${jsonEncode(raw)} reads as "$clean"', () {
        expect(cleanCode(raw), clean);
        expect(cleanCode(cleanCode(raw)), clean);
      });
    });
  });

  group('room state', () {
    for (var size = 2; size <= 4; size++) {
      test('colours for $size players are distinct and blue first', () {
        final c = RoomState.colorsFor(size);
        expect(c.length, size);
        expect(c.toSet().length, size);
        expect(c.first, 3);
        expect(c.every((x) => x >= 0 && x < 4), isTrue);
      });

      for (var filled = 1; filled <= size; filled++) {
        for (final started in [false, true]) {
          test('size $size, $filled seated, started=$started round trips', () {
            final colors = RoomState.colorsFor(size);
            final r = room(
                size,
                {
                  for (var s = 0; s < filled; s++)
                    s: Seat(
                        uid: 'u$s',
                        name: 'N$s',
                        color: colors[s],
                        online: s.isEven),
                },
                started: started);
            final back = RoomState.fromJson(r.code, roundTrip(r.toJson()));
            expect(back.code, r.code);
            expect(back.size, size);
            expect(back.started, started);
            expect(back.full, filled == size);
            expect(back.rules.tokens, 2);
            expect(back.seats.keys.toSet(), r.seats.keys.toSet());
            for (final s in r.seats.keys) {
              expect(back.seats[s]!.uid, r.seats[s]!.uid);
              expect(back.seats[s]!.name, r.seats[s]!.name);
              expect(back.seats[s]!.color, r.seats[s]!.color);
              expect(back.seats[s]!.online, r.seats[s]!.online);
            }
            expect(back.host, 0); // seat 0 is always online here
            final players = back.players();
            expect(players.length, filled);
            expect(players.map((p) => p.kind), everyElement(PlayerKind.remote));
            for (var p = 0; p < filled; p++) {
              expect(back.playerOf(back.seatOf(p)), p);
              expect(players[p].color, colors[p]);
            }
          });
        }
      }
    }

    test('the database may return seats as a sparse list', () {
      final r = RoomState.fromJson('ZZZ999', {
        'size': 4,
        'rules': {'tokens': 4},
        'seats': [
          {'uid': 'a', 'name': 'A', 'color': 3, 'online': true},
          null,
          {'uid': 'c', 'name': 'C', 'color': 1},
        ],
      });
      expect(r.seats.keys.toList()..sort(), [0, 2]);
      expect(r.seats[2]!.online, isFalse); // missing means offline
      expect(r.started, isFalse);
      expect(r.playerOf(2), 1);
      expect(r.seatOf(1), 2);
      expect(r.full, isFalse);
    });

    test('a room with no seats has no host', () {
      final r = RoomState.fromJson('ZZZ999', {
        'size': 2,
        'rules': <String, dynamic>{},
      });
      expect(r.seats, isEmpty);
      expect(r.host, isNull);
    });

    final hostCases = <String, (List<bool>, int?)>{
      'everyone online': ([true, true, true], 0),
      'seat 0 offline': ([false, true, true], 1),
      'only the last online': ([false, false, true], 2),
      'nobody online': ([false, false, false], null),
    };
    hostCases.forEach((name, c) {
      test('host when $name', () {
        final r = room(3, {
          for (var s = 0; s < 3; s++)
            s: Seat(uid: '$s', name: '$s', color: s, online: c.$1[s]),
        });
        expect(r.host, c.$2);
      });
    });

    for (final e in RoomError.values) {
      test('error $e has a friendly message', () {
        final ex = RoomException(e);
        expect(ex.message, isNotEmpty);
        expect(ex.toString(), ex.message);
        expect(ex.message.endsWith('.'), isTrue);
      });
    }
    test('every error message is different', () {
      expect(
          {for (final e in RoomError.values) RoomException(e).message}.length,
          RoomError.values.length);
    });
  });

  group('action messages', () {
    for (var p = 0; p < 4; p++) {
      for (var v = 1; v <= 6; v++) {
        test('roll by $p of $v encodes and decodes', () {
          final a = RollAction(p, v);
          final j = roundTrip(a.toJson());
          expect(j, {'t': 'roll', 'p': p, 'v': v});
          final b = GameAction.fromJson(j);
          expect(b, isA<RollAction>());
          expect(b.player, p);
          expect((b as RollAction).value, v);
        });
      }
      for (var k = 0; k < 4; k++) {
        test('move by $p of token $k encodes and decodes', () {
          final j = roundTrip(MoveAction(p, k).toJson());
          expect(j, {'t': 'move', 'p': p, 'k': k});
          final b = GameAction.fromJson(j) as MoveAction;
          expect(b.player, p);
          expect(b.token, k);
        });
      }
    }
    for (final bad in ['chat', 'ROLL', '', 'undo']) {
      test('unknown action type "$bad" is refused', () {
        expect(() => GameAction.fromJson({'t': bad, 'p': 0}),
            throwsFormatException);
      });
    }
  });

  group('memory server', () {
    Future<MemoryBackend> phone(MemoryServer s) async {
      final b = MemoryBackend(s);
      await b.connect();
      return b;
    }

    test('phones get distinct ids', () async {
      final s = MemoryServer();
      final ids = {for (var i = 0; i < 5; i++) (await phone(s)).uid};
      expect(ids.length, 5);
    });

    for (var size = 2; size <= 4; size++) {
      test('a $size seat room fills in order then refuses', () async {
        final s = MemoryServer();
        final host = await phone(s);
        final code = await host.createRoom(
            name: 'H', size: size, rules: const GameRules());
        expect(s.rooms[code]!.seats[0]!.color, RoomState.colorsFor(size)[0]);
        for (var seat = 1; seat < size; seat++) {
          final p = await phone(s);
          expect(await p.joinRoom(code, 'P$seat'), seat);
          expect(s.rooms[code]!.seats[seat]!.color,
              RoomState.colorsFor(size)[seat]);
        }
        expect(s.rooms[code]!.full, isTrue);
        final late = await phone(s);
        await expectLater(
            late.joinRoom(code, 'Late'),
            throwsA(isA<RoomException>()
                .having((e) => e.error, 'error', RoomError.full)));
      });
    }

    test('unknown room code', () async {
      final p = await phone(MemoryServer());
      await expectLater(
          p.joinRoom('NOPE22', 'x'),
          throwsA(isA<RoomException>()
              .having((e) => e.error, 'error', RoomError.notFound)));
    });

    test('joining a started room is refused, rejoining is not', () async {
      final s = MemoryServer();
      final host = await phone(s), guest = await phone(s);
      final code =
          await host.createRoom(name: 'H', size: 3, rules: const GameRules());
      await guest.joinRoom(code, 'G');
      await host.startGame(code);
      final late = await phone(s);
      await expectLater(
          late.joinRoom(code, 'L'),
          throwsA(isA<RoomException>()
              .having((e) => e.error, 'error', RoomError.started)));
      expect(await guest.joinRoom(code, 'G'), 1);
    });

    test('leaving before the start frees the seat', () async {
      final s = MemoryServer();
      final host = await phone(s), guest = await phone(s);
      final code =
          await host.createRoom(name: 'H', size: 2, rules: const GameRules());
      await guest.joinRoom(code, 'G');
      await guest.leave(code, 1);
      expect(s.rooms[code]!.seats.keys, [0]);
      final other = await phone(s);
      expect(await other.joinRoom(code, 'O'), 1);
    });

    test('leaving after the start marks the seat offline', () async {
      final s = MemoryServer();
      final host = await phone(s), guest = await phone(s);
      final code =
          await host.createRoom(name: 'H', size: 2, rules: const GameRules());
      await guest.joinRoom(code, 'G');
      await host.startGame(code);
      await host.leave(code, 0);
      final r = s.rooms[code]!;
      expect(r.seats.length, 2);
      expect(r.seats[0]!.online, isFalse);
      expect(r.host, 1);
      await host.leave('NOPE22', 0); // unknown rooms are ignored
    });

    test('each action slot is taken once', () async {
      final s = MemoryServer();
      final a = await phone(s), b = await phone(s);
      final code =
          await a.createRoom(name: 'A', size: 2, rules: const GameRules());
      await b.joinRoom(code, 'B');
      expect(await a.sendAction(code, 0, const RollAction(0, 6)), isTrue);
      expect(await b.sendAction(code, 0, const RollAction(0, 2)), isFalse);
      expect(await b.sendAction(code, 1, const MoveAction(0, 1)), isTrue);
      final got = await a.actions(code).take(2).toList();
      expect(got.map((e) => e.$1), [0, 1]);
      expect((got[0].$2 as RollAction).value, 6);
      expect((got[1].$2 as MoveAction).token, 1);
    });

    test('watching a room sees the guest arrive', () async {
      final s = MemoryServer();
      final a = await phone(s), b = await phone(s);
      final code =
          await a.createRoom(name: 'A', size: 2, rules: const GameRules());
      final seen = a.watchRoom(code).take(2).toList();
      await pumpEventQueue(); // let the watcher subscribe
      await b.joinRoom(code, 'B');
      final states = await seen;
      expect(states.first!.seats.length, 1);
      expect(states.last!.seats.length, 2);
    });

    test('signals reach only the addressed seat', () async {
      final s = MemoryServer();
      final a = await phone(s);
      final code =
          await a.createRoom(name: 'A', size: 2, rules: const GameRules());
      final toOne = a.signals(code, 1).first;
      await a.sendSignal(
          code, 0, const Signal(from: 1, type: 'ice', data: {'x': 0}));
      await a.sendSignal(
          code, 1, const Signal(from: 0, type: 'offer', data: {'sdp': 'v'}));
      final sig = await toOne;
      expect(sig.from, 0);
      expect(sig.type, 'offer');
      expect(sig.data, {'sdp': 'v'});
    });

    test('online link controls only its own seat', () async {
      final r = room(3, {
        0: const Seat(uid: 'a', name: 'A', color: 3),
        2: const Seat(uid: 'c', name: 'C', color: 1),
      });
      final link = OnlineLink(MemoryBackend(MemoryServer()), r.code, r, 2);
      final g = LudoEngine(players: r.players());
      expect(link.online, isTrue);
      expect(link.controls(g, 0), isFalse);
      expect(link.controls(g, 1), isTrue);
      final local = LocalLink();
      expect(local.online, isFalse);
      expect(local.controls(g, 0), isTrue);
      final got = local.actions.toList();
      await local.send(0, const RollAction(0, 5));
      await local.close();
      final list = await got;
      expect(list.single.$1, 0);
      expect((list.single.$2 as RollAction).value, 5);
    });
  });
}
