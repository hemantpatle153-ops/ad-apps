import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../engine.dart';
import '../match.dart';
import 'backend.dart';

/// Firebase project settings (project `dice-dhamaal`). These are client
/// settings that ship inside every APK anyway, not secrets; the database
/// rules are what protect the data. A build can point at another project
/// with --dart-define=FIREBASE_API_KEY=... and the other names below.
abstract final class FirebaseSetup {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY',
      defaultValue: 'AIzaSyCRyrPruZ67YefPw1brA4cv0G6AeT9A7gk');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID',
      defaultValue: '1:448997235311:android:08295ed6078d5fcc6e8b9a');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID',
      defaultValue: 'dice-dhamaal');
  static const senderId = String.fromEnvironment('FIREBASE_SENDER_ID',
      defaultValue: '448997235311');
  static const dbUrl = String.fromEnvironment('FIREBASE_DB_URL',
      defaultValue:
          'https://dice-dhamaal-default-rtdb.asia-southeast1.firebasedatabase.app');

  /// False in builds made without the settings; online play then explains
  /// that it isn't available instead of failing.
  static bool get configured =>
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      projectId.isNotEmpty &&
      dbUrl.isNotEmpty;

  static FirebaseOptions get options => const FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: senderId,
        projectId: projectId,
        databaseURL: dbUrl,
      );
}

/// Rooms in Firebase Realtime Database, players signed in anonymously.
///
/// rooms/{code}: size, rules, started, created,
///   seats/{n}: uid, name, color, online
///   members/{uid}: seat number (lets the security rules check membership)
///   actions/{000042}: one game action
///   signal/{seat}/{id}: voice-call messages for that seat
class FirebaseBackend implements RoomBackend {
  FirebaseApp? _app;
  late FirebaseDatabase _db;
  late String _uid;

  DatabaseReference _room(String code) => _db.ref('rooms/$code');

  @override
  Future<String> connect() async {
    if (!FirebaseSetup.configured) {
      throw const RoomException(RoomError.notConfigured);
    }
    try {
      _app ??= Firebase.apps.isEmpty
          ? await Firebase.initializeApp(options: FirebaseSetup.options)
          : Firebase.app();
      final auth = FirebaseAuth.instanceFor(app: _app!);
      final user = auth.currentUser ?? (await auth.signInAnonymously()).user!;
      _uid = user.uid;
      _db = FirebaseDatabase.instanceFor(
          app: _app!, databaseURL: FirebaseSetup.dbUrl);
      return _uid;
    } on RoomException {
      rethrow;
    } catch (_) {
      throw const RoomException(RoomError.offline);
    }
  }

  @override
  Future<String> createRoom(
      {required String name,
      required int size,
      required GameRules rules}) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = newRoomCode();
      final ref = _room(code);
      final taken = await ref.child('size').get();
      if (taken.exists) continue;
      final seat =
          Seat(uid: _uid, name: name, color: RoomState.colorsFor(size)[0]);
      await ref.set({
        'size': size,
        'rules': rules.toJson(),
        'started': false,
        'created': ServerValue.timestamp,
        'seats': {'0': seat.toJson()},
        'members': {_uid: 0},
      });
      await _goOnline(code, 0);
      return code;
    }
    throw const RoomException(RoomError.offline);
  }

  @override
  Future<int> joinRoom(String code, String name) async {
    final ref = _room(code);
    final snap = await ref.get();
    if (!snap.exists || snap.value is! Map) {
      throw const RoomException(RoomError.notFound);
    }
    final room =
        RoomState.fromJson(code, Map<String, dynamic>.from(snap.value! as Map));
    for (final e in room.seats.entries) {
      if (e.value.uid == _uid) {
        await _goOnline(code, e.key);
        return e.key;
      }
    }
    if (room.started) throw const RoomException(RoomError.started);
    final colors = RoomState.colorsFor(room.size);
    for (var seat = 0; seat < room.size; seat++) {
      if (room.seats.containsKey(seat)) continue;
      // Claim the seat only if it is still free; two people joining at the
      // same moment can't land in the same chair.
      final result = await ref.child('seats/$seat').runTransaction((v) {
        if (v != null) return Transaction.abort();
        return Transaction.success(
            Seat(uid: _uid, name: name, color: colors[seat]).toJson());
      });
      if (result.committed) {
        await ref.child('members/$_uid').set(seat);
        await _goOnline(code, seat);
        return seat;
      }
    }
    throw const RoomException(RoomError.full);
  }

  /// Marks the seat online now and offline when the connection drops.
  Future<void> _goOnline(String code, int seat) async {
    final online = _room(code).child('seats/$seat/online');
    await online.onDisconnect().set(false);
    await online.set(true);
  }

  @override
  Stream<RoomState?> watchRoom(String code) {
    // Only the lobby fields, so long games don't resend every action.
    final ctl = StreamController<RoomState?>();
    Map<String, dynamic>? head;
    Object? seats;
    void emit() {
      if (head == null) return;
      if (head!['size'] == null) {
        ctl.add(null);
        return;
      }
      ctl.add(RoomState.fromJson(code, {...head!, 'seats': seats}));
    }

    final subs = <StreamSubscription<DatabaseEvent>>[];
    ctl.onListen = () {
      final ref = _room(code);
      final fields = <String, Object?>{};
      for (final k in const ['size', 'rules', 'started']) {
        subs.add(ref.child(k).onValue.listen((e) {
          fields[k] = e.snapshot.value;
          if (fields.length == 3) {
            head = Map<String, dynamic>.from(fields);
            emit();
          }
        }, onError: ctl.addError));
      }
      subs.add(ref.child('seats').onValue.listen((e) {
        seats = e.snapshot.value;
        emit();
      }, onError: ctl.addError));
    };
    ctl.onCancel = () async {
      for (final s in subs) {
        await s.cancel();
      }
    };
    return ctl.stream;
  }

  @override
  Future<void> startGame(String code) => _room(code).child('started').set(true);

  static String _key(int index) => index.toString().padLeft(6, '0');

  @override
  Stream<(int, GameAction)> actions(String code) =>
      _room(code).child('actions').orderByKey().onChildAdded.map((e) => (
            int.parse(e.snapshot.key!),
            GameAction.fromJson(
                Map<String, dynamic>.from(e.snapshot.value! as Map)),
          ));

  @override
  Future<bool> sendAction(String code, int index, GameAction action) async {
    final result = await _room(code)
        .child('actions/${_key(index)}')
        .runTransaction((v) => v != null
            ? Transaction.abort()
            : Transaction.success(action.toJson()));
    return result.committed;
  }

  @override
  Future<void> sendSignal(String code, int to, Signal signal) =>
      _room(code).child('signal/$to').push().set({
        'from': signal.from,
        'type': signal.type,
        'data': signal.data,
      });

  @override
  Stream<Signal> signals(String code, int seat) {
    final ref = _room(code).child('signal/$seat');
    return ref.onChildAdded.map((e) {
      final v = Map<String, dynamic>.from(e.snapshot.value! as Map);
      // Each message is read once, then removed.
      e.snapshot.ref.remove().ignore();
      return Signal(
        from: v['from'] as int,
        type: v['type'] as String,
        data: Map<String, dynamic>.from(v['data'] as Map),
      );
    });
  }

  @override
  Future<void> leave(String code, int seat) async {
    final ref = _room(code);
    final started = (await ref.child('started').get()).value == true;
    final online = ref.child('seats/$seat/online');
    await online.onDisconnect().cancel();
    if (started) {
      await online.set(false);
    } else {
      await ref.child('seats/$seat').remove();
      await ref.child('members/$_uid').remove();
    }
  }
}
