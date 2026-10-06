import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:snakes_ladders/ludo/bot.dart';
import 'package:snakes_ladders/ludo/engine.dart';
import 'package:snakes_ladders/ludo/match.dart';
import 'package:snakes_ladders/ludo/online/backend.dart';

void main() {
  test('room codes are 6 easy characters and typing is forgiving', () {
    final c = newRoomCode();
    expect(c.length, 6);
    expect(RegExp(r'^[A-HJKMNP-Z2-9]{6}$').hasMatch(c), isTrue);
    expect(cleanCode(' ab-c 12 3'), 'ABC123');
  });

  test('two phones join a room and stay in sync', () async {
    final server = MemoryServer();
    final host = MemoryBackend(server), guest = MemoryBackend(server);
    await host.connect();
    await guest.connect();
    final code = await host.createRoom(
        name: 'Rahul', size: 2, rules: const GameRules(tokens: 2));
    expect(await guest.joinRoom(code, 'Asha'), 1);
    // Rejoining gives the same seat back.
    expect(await guest.joinRoom(code, 'Asha'), 1);
    final third = MemoryBackend(server);
    await third.connect();
    expect(() => third.joinRoom(code, 'X'), throwsA(isA<RoomException>()));

    await host.startGame(code);
    final room = server.rooms[code]!;
    expect(room.started, isTrue);
    expect([for (final p in room.players()) p.color], [3, 1]);

    final links = [
      OnlineLink(host, code, room, 0),
      OnlineLink(guest, code, room, 1),
    ];
    final games = [
      LudoEngine(players: room.players(), rules: room.rules),
      LudoEngine(players: room.players(), rules: room.rules),
    ];
    final applied = [0, 0];
    final subs = <StreamSubscription<(int, GameAction)>>[];
    for (var k = 0; k < 2; k++) {
      subs.add(links[k].actions.listen((e) {
        final (i, a) = e;
        expect(i, applied[k]);
        applied[k]++;
        final g = games[k];
        if (!a.validFor(g)) return;
        switch (a) {
          case RollAction(:final value):
            g.roll(value);
          case MoveAction(:final token):
            g.move(token);
        }
      }));
    }

    var index = 0;
    var guard = 0;
    while (!games[0].isOver && guard++ < 5000) {
      final g = games[0];
      final p = g.current;
      final phone = [0, 1].firstWhere((k) => links[k].controls(g, p));
      final GameAction a = g.phase == Phase.roll
          ? RollAction(p, g.rollDie())
          : MoveAction(p, chooseMove(g, g.movableFor(p, g.lastRoll)));
      await links[phone].send(index, a);
      // A late duplicate from the other phone is refused.
      expect(await (phone == 0 ? guest : host).sendAction(code, index, a),
          isFalse);
      index++;
      await pumpEventQueue();
    }
    expect(games[0].isOver, isTrue);
    expect(games[1].toJson(), games[0].toJson());
    for (final s in subs) {
      unawaited(s.cancel());
    }
  });
}
