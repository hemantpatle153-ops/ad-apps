import 'dart:async';
import 'dart:math';

import '../engine.dart';
import '../match.dart';

/// A seat taken in an online room.
class Seat {
  const Seat({
    required this.uid,
    required this.name,
    required this.color,
    this.online = true,
  });

  final String uid;
  final String name;
  final int color;

  /// False while that phone is disconnected.
  final bool online;

  Map<String, dynamic> toJson() =>
      {'uid': uid, 'name': name, 'color': color, 'online': online};

  factory Seat.fromJson(Map<String, dynamic> j) => Seat(
        uid: j['uid'] as String,
        name: j['name'] as String,
        color: j['color'] as int,
        online: j['online'] as bool? ?? false,
      );
}

/// What everyone in a room sees: the seats, and whether the game started.
class RoomState {
  const RoomState({
    required this.code,
    required this.size,
    required this.rules,
    required this.seats,
    required this.started,
  });

  final String code;

  /// Players the room waits for, 2 to 4.
  final int size;
  final GameRules rules;
  final Map<int, Seat> seats;
  final bool started;

  bool get full => seats.length >= size;

  /// The phone that runs shared chores (playing for someone who dropped
  /// out): the lowest seat that is online.
  int? get host {
    final on = seats.entries.where((e) => e.value.online).map((e) => e.key);
    return on.isEmpty ? null : on.reduce(min);
  }

  /// The engine players, in seat order (which is clockwise colour order).
  List<Player> players() => [
        for (final s in (seats.keys.toList()..sort()))
          Player(
              name: seats[s]!.name,
              color: seats[s]!.color,
              kind: PlayerKind.remote),
      ];

  /// Engine player index for a seat number.
  int playerOf(int seat) => (seats.keys.toList()..sort()).indexOf(seat);
  int seatOf(int player) => (seats.keys.toList()..sort())[player];

  /// Colours seat by seat, so the room is spread around the board: two
  /// players sit opposite each other.
  static List<int> colorsFor(int size) => switch (size) {
        2 => const [3, 1],
        3 => const [3, 0, 1],
        _ => const [3, 0, 1, 2],
      };

  Map<String, dynamic> toJson() => {
        'size': size,
        'rules': rules.toJson(),
        'started': started,
        'seats': {for (final e in seats.entries) '${e.key}': e.value.toJson()},
      };

  factory RoomState.fromJson(String code, Map<String, dynamic> j) {
    final raw = j['seats'];
    final seats = <int, Seat>{};
    // The database returns small integer keys as a list, sometimes sparse.
    if (raw is List) {
      for (var i = 0; i < raw.length; i++) {
        if (raw[i] != null) {
          seats[i] = Seat.fromJson(Map<String, dynamic>.from(raw[i] as Map));
        }
      }
    } else if (raw is Map) {
      raw.forEach((k, v) => seats[int.parse('$k')] =
          Seat.fromJson(Map<String, dynamic>.from(v as Map)));
    }
    return RoomState(
      code: code,
      size: j['size'] as int,
      rules: GameRules.fromJson(Map<String, dynamic>.from(j['rules'] as Map)),
      seats: seats,
      started: j['started'] as bool? ?? false,
    );
  }
}

enum RoomError { notFound, full, started, offline, notConfigured }

class RoomException implements Exception {
  const RoomException(this.error);
  final RoomError error;

  String get message => switch (error) {
        RoomError.notFound => 'No room with that code. Check it and try again.',
        RoomError.full => 'That room is full.',
        RoomError.started => 'That game has already started.',
        RoomError.offline =>
          'Could not reach the game server. Check your internet.',
        RoomError.notConfigured => 'Online play is not available yet.',
      };

  @override
  String toString() => message;
}

/// A voice-call signalling message between two seats.
class Signal {
  const Signal({required this.from, required this.type, required this.data});

  final int from;

  /// offer, answer or ice.
  final String type;
  final Map<String, dynamic> data;
}

/// Where online rooms live. [FirebaseBackend] is the real one; tests use
/// [MemoryBackend].
abstract class RoomBackend {
  /// Signs in (anonymously) and returns this phone's id.
  Future<String> connect();

  Future<String> createRoom(
      {required String name, required int size, required GameRules rules});

  /// Takes a free seat, or this phone's old seat if it is rejoining.
  Future<int> joinRoom(String code, String name);

  Stream<RoomState?> watchRoom(String code);

  Future<void> startGame(String code);

  /// Every action of the game, in order, from the beginning.
  Stream<(int, GameAction)> actions(String code);

  /// Writes action number [index] unless another phone already did.
  Future<bool> sendAction(String code, int index, GameAction action);

  Future<void> sendSignal(String code, int to, Signal signal);

  /// Signals addressed to [seat]; each is delivered once.
  Stream<Signal> signals(String code, int seat);

  Future<void> leave(String code, int seat);
}

/// Letters and digits that can't be confused when read aloud or typed.
const _codeChars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

String newRoomCode([Random? random]) {
  final r = random ?? Random.secure();
  return List.generate(6, (_) => _codeChars[r.nextInt(_codeChars.length)])
      .join();
}

/// Normalises what a player typed: upper case, no spaces or dashes.
String cleanCode(String raw) =>
    raw.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

/// Plays the game for an online room through [backend].
class OnlineLink implements MatchLink {
  OnlineLink(this.backend, this.code, this.room, this.mySeat);

  final RoomBackend backend;
  final String code;

  /// Room as it was when the game started; seats don't change afterwards.
  final RoomState room;
  final int mySeat;

  @override
  Stream<(int, GameAction)> get actions => backend.actions(code);

  @override
  Future<void> send(int index, GameAction action) =>
      backend.sendAction(code, index, action);

  @override
  bool controls(LudoEngine g, int player) => room.seatOf(player) == mySeat;

  @override
  bool get online => true;

  @override
  Future<void> close() async {}
}

/// An in-memory server shared by several [MemoryBackend] clients, for tests.
class MemoryServer {
  final rooms = <String, RoomState>{};
  final actions = <String, List<GameAction?>>{};
  final _roomCtl = StreamController<String>.broadcast();
  final _actionCtl = StreamController<String>.broadcast();
  final _signalCtl = StreamController<(String, int, Signal)>.broadcast();
  var _uid = 0;

  void _changed(String code) => _roomCtl.add(code);
}

class MemoryBackend implements RoomBackend {
  MemoryBackend(this.server);

  final MemoryServer server;
  late final String uid;

  @override
  Future<String> connect() async => uid = 'u${server._uid++}';

  @override
  Future<String> createRoom(
      {required String name,
      required int size,
      required GameRules rules}) async {
    final code = newRoomCode();
    server.rooms[code] = RoomState(
      code: code,
      size: size,
      rules: rules,
      seats: {
        0: Seat(uid: uid, name: name, color: RoomState.colorsFor(size)[0])
      },
      started: false,
    );
    server.actions[code] = [];
    server._changed(code);
    return code;
  }

  @override
  Future<int> joinRoom(String code, String name) async {
    final r = server.rooms[code];
    if (r == null) throw const RoomException(RoomError.notFound);
    for (final e in r.seats.entries) {
      if (e.value.uid == uid) return e.key;
    }
    if (r.started) throw const RoomException(RoomError.started);
    if (r.full) throw const RoomException(RoomError.full);
    var seat = 0;
    while (r.seats.containsKey(seat)) {
      seat++;
    }
    server.rooms[code] = RoomState(
      code: code,
      size: r.size,
      rules: r.rules,
      seats: {
        ...r.seats,
        seat: Seat(uid: uid, name: name, color: RoomState.colorsFor(r.size)[seat]),
      },
      started: false,
    );
    server._changed(code);
    return seat;
  }

  @override
  Stream<RoomState?> watchRoom(String code) async* {
    yield server.rooms[code];
    yield* server._roomCtl.stream
        .where((c) => c == code)
        .map((_) => server.rooms[code]);
  }

  @override
  Future<void> startGame(String code) async {
    final r = server.rooms[code]!;
    server.rooms[code] = RoomState(
        code: code, size: r.size, rules: r.rules, seats: r.seats, started: true);
    server._changed(code);
  }

  @override
  Stream<(int, GameAction)> actions(String code) async* {
    var next = 0;
    final list = server.actions[code]!;
    while (next < list.length && list[next] != null) {
      yield (next, list[next]!);
      next++;
    }
    await for (final _ in server._actionCtl.stream.where((c) => c == code)) {
      while (next < list.length && list[next] != null) {
        yield (next, list[next]!);
        next++;
      }
    }
  }

  @override
  Future<bool> sendAction(String code, int index, GameAction action) async {
    final list = server.actions[code]!;
    while (list.length <= index) {
      list.add(null);
    }
    if (list[index] != null) return false;
    list[index] = GameAction.fromJson(action.toJson());
    server._actionCtl.add(code);
    return true;
  }

  @override
  Future<void> sendSignal(String code, int to, Signal signal) async =>
      server._signalCtl.add((code, to, signal));

  @override
  Stream<Signal> signals(String code, int seat) => server._signalCtl.stream
      .where((e) => e.$1 == code && e.$2 == seat)
      .map((e) => e.$3);

  @override
  Future<void> leave(String code, int seat) async {
    final r = server.rooms[code];
    if (r == null) return;
    final seats = Map.of(r.seats);
    if (r.started) {
      final s = seats[seat]!;
      seats[seat] =
          Seat(uid: s.uid, name: s.name, color: s.color, online: false);
    } else {
      seats.remove(seat);
    }
    server.rooms[code] = RoomState(
        code: code,
        size: r.size,
        rules: r.rules,
        seats: seats,
        started: r.started);
    server._changed(code);
  }
}
