import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:media_kit/media_kit.dart';

import 'clock.dart';
import 'follower.dart';
import 'party.dart';
import 'protocol.dart';

/// Firebase project settings (the `dice-dhamaal` project, shared with the
/// Ludo game; this app is registered there as in.onlysoftware.video_player). These client settings ship inside every APK anyway; the
/// database rules protect the data. A build can point elsewhere with
/// --dart-define=FIREBASE_API_KEY=... and the other names below.
abstract final class FirebaseSetup {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY',
      defaultValue: 'AIzaSyCRyrPruZ67YefPw1brA4cv0G6AeT9A7gk');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID',
      defaultValue: '1:448997235311:android:1b54beb30bb19ea96e8b9a');
  static const projectId =
      String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: 'dice-dhamaal');
  static const senderId =
      String.fromEnvironment('FIREBASE_SENDER_ID', defaultValue: '448997235311');
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

enum OnlineError { offline, notFound }

class OnlineException implements Exception {
  const OnlineException(this.error);
  final OnlineError error;

  String get message => switch (error) {
        OnlineError.offline =>
          "Couldn't reach the internet. Check your connection and try again.",
        OnlineError.notFound => 'No watch party with that code. Check the code '
            'and that your friend still has the video open.',
      };
}

/// Letters and digits that can't be mixed up when read out (no 0/O, 1/I/L).
const roomCodeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

String newRoomCode([Random? rng]) {
  final r = rng ?? Random.secure();
  return List.generate(6, (_) => roomCodeAlphabet[r.nextInt(roomCodeAlphabet.length)])
      .join();
}

/// Cleans up a typed code: upper case, no spaces or dashes. Null if it
/// can't be a room code.
String? normalizeRoomCode(String raw) {
  final code = raw.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  if (code.length != 6) return null;
  for (final c in code.split('')) {
    if (!roomCodeAlphabet.contains(c)) return null;
  }
  return code;
}

/// The video an online room watches. Only its name and length travel; a
/// file stays on each phone, a link is opened by each phone.
class OnlineVideo {
  const OnlineVideo({required this.title, this.url, this.durationMs = 0});

  final String title;
  final String? url;
  final int durationMs;

  bool get isLink => url != null;

  Map<String, Object?> toJson() => {'title': title, 'url': url, 'dur': durationMs};

  factory OnlineVideo.fromJson(Map<Object?, Object?> j) => OnlineVideo(
        title: '${j['title'] ?? 'Video'}',
        url: j['url'] as String?,
        durationMs: (j['dur'] as num?)?.toInt() ?? 0,
      );
}

/// A watch party over the internet, through Firebase Realtime Database.
///
/// Firebase carries only small messages (play, pause, seek, chat, emoji);
/// every phone plays its own copy of the video, or opens the same link.
/// Everyone, the starter included, follows the shared timeline.
///
/// watch/{code}: host (uid), created, video {title, url, dur},
///   state {playing, pos, at, rate, by}  (pos in µs; at in server µs)
///   members/{uid}: {name}
///   chat/{pushId}: {uid, from, text, e, at}
class OnlineParty extends WatchParty {
  OnlineParty._(super.myName, this.code, this.video, this._db, this._uid,
      {required this.owner});

  static FirebaseApp? _app;

  final String code;
  final OnlineVideo video;
  final FirebaseDatabase _db;
  final String _uid;

  /// True on the phone that started the room; leaving ends it for everyone.
  final bool owner;

  @override
  bool get isHost => false;

  PartyState state = PartyState.start;
  int _serverOffsetUs = 0;
  late final _follower =
      TimelineFollower(nowUs: serverNowUs, nudgeAboveUs: 250000);
  final _subs = <StreamSubscription<Object?>>[];
  Timer? _sync;
  int _joinedAtMs = 0;
  bool _closed = false;

  DatabaseReference get _room => _db.ref('watch/$code');

  int serverNowUs() => Clock.nowUs() + _serverOffsetUs;

  /// Text friends can paste or forward to join.
  String get inviteText => 'Watch "${video.title}" with me in Video Player: '
      'open Watch together and enter code $code';

  static Future<(FirebaseDatabase, String)> _connect() async {
    try {
      _app ??= Firebase.apps.isEmpty
          ? await Firebase.initializeApp(options: FirebaseSetup.options)
          : Firebase.app();
      final auth = FirebaseAuth.instanceFor(app: _app!);
      final user = auth.currentUser ?? (await auth.signInAnonymously()).user!;
      final db = FirebaseDatabase.instanceFor(app: _app!, databaseURL: FirebaseSetup.dbUrl);
      return (db, user.uid);
    } catch (_) {
      throw const OnlineException(OnlineError.offline);
    }
  }

  /// Starts a room for [video] with the player's current [start] state.
  static Future<OnlineParty> create(
      String name, OnlineVideo video, PartyState start) async {
    final (db, uid) = await _connect().timeout(const Duration(seconds: 15),
        onTimeout: () => throw const OnlineException(OnlineError.offline));
    try {
      for (var attempt = 0; attempt < 5; attempt++) {
        final code = newRoomCode();
        final ref = db.ref('watch/$code');
        if ((await ref.child('host').get()).exists) continue;
        final party = OnlineParty._(name, code, video, db, uid, owner: true);
        await party._startClock();
        final s = PartyState(
          playing: start.playing,
          positionUs: start.positionUs,
          anchorUs: party.serverNowUs(),
          rate: start.rate,
        );
        // One multi-path update, so each child's security rule applies.
        await ref.update({
          'host': uid,
          'created': ServerValue.timestamp,
          'video': video.toJson(),
          'state': {...s.toJson(), 'by': uid},
          'members/$uid': {'name': name},
        });
        await party._listen();
        unawaited(sweepOldRooms(db, party.serverNowUs() ~/ 1000));
        return party;
      }
    } on OnlineException {
      rethrow;
    } catch (_) {
      throw const OnlineException(OnlineError.offline);
    }
    throw const OnlineException(OnlineError.offline);
  }

  /// Rooms are deleted when their starter leaves. One left behind (app
  /// killed, phone off) is deleted by the next phone that starts a room once
  /// it is [roomLifetime] old, so the database stays tiny and free.
  static const roomLifetime = Duration(hours: 12);

  static Future<void> sweepOldRooms(FirebaseDatabase db, int serverNowMs) async {
    try {
      final old = await db
          .ref('watch')
          .orderByChild('created')
          .endAt(serverNowMs - roomLifetime.inMilliseconds)
          // The database rules only allow this exact query, so phones can't
          // list other people's rooms.
          .limitToFirst(20)
          .get();
      for (final room in old.children) {
        await room.ref.remove();
      }
    } catch (_) {
      // Next time.
    }
  }

  /// Looks up a room by its code. The caller opens the video, then the
  /// party follows the room once [attach] is called.
  static Future<OnlineParty> join(String name, String code) async {
    final (db, uid) = await _connect().timeout(const Duration(seconds: 15),
        onTimeout: () => throw const OnlineException(OnlineError.offline));
    final ref = db.ref('watch/$code');
    DataSnapshot snap;
    try {
      snap = await ref.get().timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const OnlineException(OnlineError.offline);
    }
    final room = snap.value;
    if (room is! Map || room['host'] == null || room['video'] is! Map) {
      throw const OnlineException(OnlineError.notFound);
    }
    final party = OnlineParty._(
        name, code, OnlineVideo.fromJson(room['video'] as Map), db, uid,
        owner: room['host'] == uid);
    try {
      await party._startClock();
      await ref.child('members/$uid').set({'name': name});
      await party._listen();
    } catch (_) {
      throw const OnlineException(OnlineError.offline);
    }
    return party;
  }

  /// Firebase reports how far its clock is from this phone's.
  Future<void> _startClock() async {
    final ref = _db.ref('.info/serverTimeOffset');
    final first = await ref.get();
    _serverOffsetUs = (((first.value as num?) ?? 0) * 1000).round();
    _subs.add(ref.onValue.listen((e) {
      _serverOffsetUs = (((e.snapshot.value as num?) ?? 0) * 1000).round();
    }));
  }

  Future<void> _listen() async {
    _joinedAtMs = serverNowUs() ~/ 1000;
    final me = _room.child('members/$_uid');
    await me.onDisconnect().remove();
    _subs
      ..add(_room.child('state').onValue.listen((e) {
        final v = e.snapshot.value;
        if (v is! Map) return;
        state = PartyState.fromJson(v.cast<String, Object?>());
        _follower.reset();
        _syncNow();
      }))
      ..add(_room.child('members').onValue.listen((e) {
        final v = e.snapshot.value;
        final names = <String>[];
        if (v is Map) {
          for (final m in v.values) {
            if (m is Map) names.add('${m['name'] ?? 'Friend'}');
          }
        }
        members = names;
        notifyListeners();
      }))
      ..add(_room.child('host').onValue.listen((e) {
        if (e.snapshot.value == null && !_closed) {
          _end('Your friend ended the watch party');
        }
      }))
      ..add(_room.child('chat').limitToLast(30).onChildAdded.listen((e) {
        final v = e.snapshot.value;
        if (v is! Map) return;
        final m = PartyMessage(
            from: '${v['from'] ?? 'Friend'}',
            text: '${v['text'] ?? ''}',
            emoji: v['e'] == true);
        final at = (v['at'] as num?)?.toInt() ?? 0;
        if (at != 0 && at < _joinedAtMs - 2000) {
          // Said before this phone joined: list it, don't pop it on screen.
          messages.add(m);
          notifyListeners();
        } else {
          received(m);
        }
      }));
  }

  @override
  void attach(Player p) {
    super.attach(p);
    _sync = Timer.periodic(const Duration(milliseconds: 500), (_) => _syncNow());
    _syncNow();
  }

  void _syncNow() {
    final p = player;
    if (p == null || _closed || endedReason != null) return;
    _follower.follow(p, state);
  }

  void _end(String reason) {
    if (endedReason != null) return;
    endedReason = reason;
    _sync?.cancel();
    player?.pause();
    notifyListeners();
  }

  Future<void> _write(PartyState s) async {
    state = s;
    _follower.reset();
    _syncNow();
    try {
      await _room.child('state').set({...s.toJson(), 'by': _uid});
    } catch (_) {
      // Offline for a moment; Firebase sends it when the connection returns.
    }
  }

  Duration get _here => player?.state.position ?? Duration.zero;

  @override
  Future<void> requestPlay() => _write(PartyState(
      playing: true,
      positionUs: _here.inMicroseconds,
      anchorUs: serverNowUs(),
      rate: state.rate));

  @override
  Future<void> requestPause() => _write(PartyState(
      playing: false,
      positionUs: state.positionAt(serverNowUs()),
      anchorUs: serverNowUs(),
      rate: state.rate));

  @override
  Future<void> requestSeek(Duration to) => _write(PartyState(
      playing: state.playing,
      positionUs: to.inMicroseconds,
      anchorUs: serverNowUs(),
      rate: state.rate));

  @override
  Future<void> requestRate(double rate) => _write(PartyState(
      playing: state.playing,
      positionUs: state.positionAt(serverNowUs()),
      anchorUs: serverNowUs(),
      rate: rate));

  void _post(String text, {bool emoji = false}) {
    _room.child('chat').push().set({
      'uid': _uid,
      'from': myName,
      'text': text,
      'e': emoji,
      'at': ServerValue.timestamp,
    }).catchError((_) {});
  }

  @override
  void sendChat(String text) {
    text = text.trim();
    if (text.isEmpty) return;
    _post(text.length > 300 ? text.substring(0, 300) : text);
  }

  @override
  void sendReaction(String emoji) => _post(emoji, emoji: true);

  @override
  Future<void> close() async {
    _closed = true;
    _sync?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    try {
      if (owner) {
        await _room.remove();
      } else {
        await _room.child('members/$_uid').onDisconnect().cancel();
        await _room.child('members/$_uid').remove();
      }
    } catch (_) {
      // Offline; the member entry goes when Firebase notices.
    }
  }
}
