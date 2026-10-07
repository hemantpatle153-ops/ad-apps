import 'dart:async';

import 'package:flutter/foundation.dart';

import 'backend.dart';
import 'voice.dart';

/// A started online game on this phone: the room, our seat and the call.
class OnlineSession {
  OnlineSession({
    required this.backend,
    required this.room,
    required this.mySeat,
  }) : voice = VoiceChat(backend, room.code, mySeat) {
    seats.value = room.seats;
    _sub = backend.watchRoom(room.code).listen((r) {
      if (r != null) seats.value = r.seats;
    });
  }

  final RoomBackend backend;

  /// The room as it was when the game started.
  final RoomState room;
  final int mySeat;
  final VoiceChat voice;

  /// Live seats, for who is online right now.
  final seats = ValueNotifier<Map<int, Seat>>({});
  StreamSubscription<RoomState?>? _sub;

  String get code => room.code;

  /// The phone that plays for anyone who dropped out: lowest online seat.
  bool get isHost {
    final on = seats.value.entries.where((e) => e.value.online);
    if (on.isEmpty) return true;
    return on.map((e) => e.key).reduce((a, b) => a < b ? a : b) == mySeat;
  }

  bool isOnline(int seat) => seats.value[seat]?.online ?? false;

  Future<void> close() async {
    await _sub?.cancel();
    await voice.close();
    await backend.leave(code, mySeat).catchError((_) {});
  }
}
