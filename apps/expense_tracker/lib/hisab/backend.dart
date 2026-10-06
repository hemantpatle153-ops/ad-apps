import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import 'model.dart';

/// The few database operations the hisab needs. [FirebaseHisabBackend] is
/// the real one; tests use an in-memory one.
abstract class HisabBackend {
  /// Signs in (anonymously) and returns this phone's user id.
  Future<String> signIn();

  /// One multi-path update. Values may contain [serverTime].
  Future<void> update(Map<String, Object?> writes);

  Future<Object?> get(String path);

  /// The value at [path] now and after every change. Emits null when it is
  /// gone or this phone may no longer read it.
  Stream<Object?> watch(String path);

  /// A new unique, time-ordered key.
  String newKey();

  /// Server time estimate, ms.
  int nowMs();

  /// Ids of cleared logs whose keep time ended before [beforeMs].
  Future<List<String>> expired(int beforeMs);
}

class HisabException implements Exception {
  const HisabException(this.message);
  final String message;
  @override
  String toString() => message;

  static const offline = HisabException(
      "Couldn't reach the internet. Check your connection and try again.");
  static const notFound = HisabException(
      'No hisab with that code. Ask your friend for the latest code; '
      'it changes when they reset it.');
  static const denied = HisabException(
      "That change isn't allowed. The code may have been reset, or the "
      'hisab is already cleared.');
}

/// Firebase settings (the `dice-dhamaal` project, shared with Dice Dhamaal
/// and Video Player). These client settings ship inside every APK anyway;
/// the database rules protect the data. A build can point elsewhere with
/// --dart-define=FIREBASE_API_KEY=... and the other names below.
abstract final class FirebaseSetup {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY',
      defaultValue: 'AIzaSyCRyrPruZ67YefPw1brA4cv0G6AeT9A7gk');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID',
      defaultValue: '1:448997235311:android:1b54beb30bb19ea96e8b9a');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID',
      defaultValue: 'dice-dhamaal');
  static const senderId = String.fromEnvironment('FIREBASE_SENDER_ID',
      defaultValue: '448997235311');
  static const dbUrl = String.fromEnvironment('FIREBASE_DB_URL',
      defaultValue: 'https://dice-dhamaal-default-rtdb.firebaseio.com');

  static FirebaseOptions get options => const FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: senderId,
        projectId: projectId,
        databaseURL: dbUrl,
      );
}

class FirebaseHisabBackend implements HisabBackend {
  FirebaseApp? _app;
  FirebaseDatabase? _db;
  String? _uid;
  int _offsetMs = 0;
  Future<String>? _signing;

  static const _timeout = Duration(seconds: 20);

  @override
  Future<String> signIn() =>
      _signing ??= _signIn().then((v) => v, onError: (Object e) {
        _signing = null;
        throw e is HisabException ? e : HisabException.offline;
      });

  Future<String> _signIn() async {
    _app ??= Firebase.apps.isEmpty
        ? await Firebase.initializeApp(options: FirebaseSetup.options)
        : Firebase.app();
    final db = _db ??= FirebaseDatabase.instanceFor(
        app: _app!, databaseURL: FirebaseSetup.dbUrl)
      // Logs open offline from the phone's cache, and changes made offline
      // are sent when the internet is back.
      ..setPersistenceEnabled(true);
    final auth = FirebaseAuth.instanceFor(app: _app!);
    final user = auth.currentUser ??
        (await auth.signInAnonymously().timeout(_timeout)).user!;
    db.ref('.info/serverTimeOffset').onValue.listen((e) {
      _offsetMs = ((e.snapshot.value as num?) ?? 0).round();
    });
    return _uid = user.uid;
  }

  FirebaseDatabase get _database {
    final db = _db;
    if (db == null) throw HisabException.offline;
    return db;
  }

  static Object? _server(Object? v) => switch (v) {
        ServerTime() => ServerValue.timestamp,
        Map() => {for (final e in v.entries) '${e.key}': _server(e.value)},
        _ => v,
      };

  static HisabException _map(Object e) {
    if (e is HisabException) return e;
    if (e is FirebaseException &&
        (e.code.contains('permission') || e.code.contains('denied'))) {
      return HisabException.denied;
    }
    return HisabException.offline;
  }

  @override
  Future<void> update(Map<String, Object?> writes) async {
    await signIn();
    try {
      final w = {for (final e in writes.entries) e.key: _server(e.value)};
      // Offline the write is queued and lands later; don't wait forever.
      await _database.ref().update(w).timeout(_timeout, onTimeout: () {});
    } catch (e) {
      throw _map(e);
    }
  }

  @override
  Future<Object?> get(String path) async {
    await signIn();
    try {
      return (await _database.ref(path).get().timeout(_timeout)).value;
    } catch (e) {
      throw _map(e);
    }
  }

  @override
  Stream<Object?> watch(String path) => Stream.fromFuture(signIn()).asyncExpand(
      (_) => (_database.ref(path)..keepSynced(true))
          .onValue
          .map<Object?>((e) => e.snapshot.value)
          // Access was removed (this phone left, or the log was deleted).
          .transform(StreamTransformer.fromHandlers(
              handleError: (_, __, sink) => sink.add(null))));

  @override
  String newKey() => _database.ref('hisab').push().key!;

  @override
  int nowMs() => DateTime.now().millisecondsSinceEpoch + _offsetMs;

  @override
  Future<List<String>> expired(int beforeMs) async {
    await signIn();
    final snap = await _database
        .ref('hisabGc')
        .orderByChild('t')
        .endAt(beforeMs)
        // The database rules allow only this exact query.
        .limitToFirst(20)
        .get()
        .timeout(_timeout);
    return [
      for (final c in snap.children)
        if (c.key != null) c.key!
    ];
  }

  String? get uid => _uid;
}
