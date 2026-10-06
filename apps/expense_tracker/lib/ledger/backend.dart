import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import 'model.dart';

/// The few database operations the ledger needs. [FirebaseLedgerBackend] is
/// the real one; tests use an in-memory one.
abstract class LedgerBackend {
  /// Makes sure someone is signed in (anonymously unless an email account
  /// is) and returns the user id.
  Future<String> signIn();

  /// The email of the signed-in account, or null when anonymous.
  String? get email;

  /// Turns the current anonymous user into an email account. The user id,
  /// and so every ledger membership, stays the same.
  Future<void> linkEmail(String email, String password);

  /// Signs in to an existing email account; returns its user id.
  Future<String> signInEmail(String email, String password);

  Future<void> sendPasswordReset(String email);

  /// Signs out and starts a fresh anonymous user; returns its id.
  Future<String> signOut();

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

class LedgerException implements Exception {
  const LedgerException(this.message);
  final String message;
  @override
  String toString() => message;

  static const offline = LedgerException(
      "Couldn't reach the internet. Check your connection and try again.");
  static const notFound = LedgerException(
      'No ledger with that code. Ask your friend for the latest code; '
      'it changes when they reset it.');
  static const emailInUse = LedgerException(
      'That email already has an account. Sign in to it instead.');
  static const wrongLogin = LedgerException('Email or password is incorrect.');
  static const weakPassword =
      LedgerException('Use a password of at least 6 characters.');
  static const badEmail = LedgerException('Enter a valid email address.');
  static const emailOff = LedgerException(
      "Email sign-in isn't available yet. Please try again later.");
  static const tooMany =
      LedgerException('Too many attempts. Wait a few minutes and try again.');
  static const denied = LedgerException(
      "That change isn't allowed. The code may have been reset, or the "
      'ledger is already settled.');
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

class FirebaseLedgerBackend implements LedgerBackend {
  FirebaseApp? _app;
  FirebaseDatabase? _db;
  int _offsetMs = 0;
  Future<void>? _starting;

  static const _timeout = Duration(seconds: 20);

  FirebaseAuth get _auth => FirebaseAuth.instanceFor(app: _app!);

  Future<void> _start() =>
      _starting ??= _init().then((_) {}, onError: (Object e) {
        _starting = null;
        throw e is LedgerException ? e : LedgerException.offline;
      });

  Future<void> _init() async {
    _app ??= Firebase.apps.isEmpty
        ? await Firebase.initializeApp(options: FirebaseSetup.options)
        : Firebase.app();
    final db = _db ??= FirebaseDatabase.instanceFor(
        app: _app!, databaseURL: FirebaseSetup.dbUrl)
      // Ledgers open offline from the phone's cache, and changes made
      // offline are sent when the internet is back.
      ..setPersistenceEnabled(true);
    db.ref('.info/serverTimeOffset').onValue.listen((e) {
      _offsetMs = ((e.snapshot.value as num?) ?? 0).round();
    });
  }

  @override
  Future<String> signIn() async {
    await _start();
    final user = _auth.currentUser;
    if (user != null) return user.uid;
    try {
      return (await _auth.signInAnonymously().timeout(_timeout)).user!.uid;
    } catch (e) {
      throw _authError(e);
    }
  }

  @override
  String? get email => _app == null ? null : _auth.currentUser?.email;

  static LedgerException _authError(Object e) {
    if (e is LedgerException) return e;
    if (e is FirebaseAuthException) {
      return switch (e.code) {
        'email-already-in-use' ||
        'credential-already-in-use' ||
        'provider-already-linked' =>
          LedgerException.emailInUse,
        'wrong-password' ||
        'user-not-found' ||
        'invalid-credential' ||
        'invalid-login-credentials' =>
          LedgerException.wrongLogin,
        'weak-password' => LedgerException.weakPassword,
        'invalid-email' || 'missing-email' => LedgerException.badEmail,
        'operation-not-allowed' ||
        'admin-restricted-operation' =>
          LedgerException.emailOff,
        'too-many-requests' => LedgerException.tooMany,
        _ => LedgerException.offline,
      };
    }
    return LedgerException.offline;
  }

  @override
  Future<void> linkEmail(String email, String password) async {
    await signIn();
    try {
      await _auth.currentUser!
          .linkWithCredential(
              EmailAuthProvider.credential(email: email, password: password))
          .timeout(_timeout);
    } catch (e) {
      throw _authError(e);
    }
  }

  @override
  Future<String> signInEmail(String email, String password) async {
    await _start();
    try {
      final c = await _auth
          .signInWithEmailAndPassword(email: email, password: password)
          .timeout(_timeout);
      return c.user!.uid;
    } catch (e) {
      throw _authError(e);
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    await _start();
    try {
      await _auth.sendPasswordResetEmail(email: email).timeout(_timeout);
    } catch (e) {
      throw _authError(e);
    }
  }

  @override
  Future<String> signOut() async {
    await _start();
    await _auth.signOut();
    return signIn();
  }

  FirebaseDatabase get _database {
    final db = _db;
    if (db == null) throw LedgerException.offline;
    return db;
  }

  static Object? _server(Object? v) => switch (v) {
        ServerTime() => ServerValue.timestamp,
        Map() => {for (final e in v.entries) '${e.key}': _server(e.value)},
        _ => v,
      };

  static LedgerException _map(Object e) {
    if (e is LedgerException) return e;
    if (e is FirebaseException &&
        (e.code.contains('permission') || e.code.contains('denied'))) {
      return LedgerException.denied;
    }
    return LedgerException.offline;
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
  String newKey() => _database.ref('ledger').push().key!;

  @override
  int nowMs() => DateTime.now().millisecondsSinceEpoch + _offsetMs;

  @override
  Future<List<String>> expired(int beforeMs) async {
    await signIn();
    final snap = await _database
        .ref('ledgerGc')
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
}
