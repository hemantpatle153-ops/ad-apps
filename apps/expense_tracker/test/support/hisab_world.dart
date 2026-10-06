import 'dart:async';
import 'dart:math';

import 'package:expense_tracker/hisab/memory_backend.dart';
import 'package:expense_tracker/hisab/model.dart';
import 'package:expense_tracker/hisab/service.dart';
import 'package:expense_tracker/hisab/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One phone: its own user id, its own saved list, the shared database.
class Phone {
  Phone(this.service, this.uid);
  final HisabService service;
  final String uid;

  HisabStore get store => service.store;

  /// The log as this phone reads it from the cloud right now.
  Future<HisabLog?> read(String id) async =>
      HisabLog.fromJson(id, await service.backend.get(HisabWrites.logPath(id)));

  Future<HisabLog> log(String id) async => (await read(id))!;

  Side side(String id) => store.byId(id)!.side;
}

/// Several phones sharing one in-memory database.
class World {
  World._(this.db);
  final MemoryDatabase db;

  static Future<World> create() async {
    SharedPreferences.setMockInitialValues({});
    return World._(MemoryDatabase());
  }

  /// Each phone gets its own preferences, like separate devices.
  Future<Phone> phone(String uid) async {
    final prefs = _FakePrefs();
    return Phone(
        HisabService(MemoryHisabBackend(db, uid), HisabStore(prefs)), uid);
  }

  /// Rahul starts a hisab with Amit; Amit joins on his phone.
  Future<(Phone, Phone, String, String)> pair(
      {String a = 'Rahul', String b = 'Amit'}) async {
    final pa = await phone('uid-$a');
    final pb = await phone('uid-$b');
    final local = await pa.service.create(a, b);
    final log = await pa.log(local.id);
    final info = await pb.service.lookup(log.code);
    await pb.service.join(log.code, info, Side.b);
    return (pa, pb, local.id, log.code);
  }
}

/// Adds an entry from [phone] and returns it.
Future<HisabEntry> add(Phone phone, String id, int amount,
    {required bool iGave,
    String tag = '',
    String note = '',
    DateTime? date}) async {
  final log = await phone.log(id);
  final me = phone.side(id);
  final e = phone.service.newEntry(
      amount: amount,
      by: iGave ? me : me.other,
      date: date ?? DateTime(2026, 10, 6),
      tag: tag,
      note: note);
  await phone.service.saveEntry(log, me, e, isNew: true);
  return e;
}

/// Reference math, written separately from [Balance].
int refNetForA(List<(int, Side)> entries) {
  var n = 0;
  for (final (amt, by) in entries) {
    n += by == Side.a ? amt : -amt;
  }
  return n;
}

HisabEntry randomEntry(Random r, int i) {
  const amounts = [1, 99, 100, 5000, 12345, 99999, 100000, 2500000];
  return HisabEntry(
    id: 'e${i.toString().padLeft(4, '0')}',
    amount: r.nextBool()
        ? amounts[r.nextInt(amounts.length)]
        : 1 + r.nextInt(10000000),
    by: r.nextBool() ? Side.a : Side.b,
    date: DateTime(2020 + r.nextInt(7), 1 + r.nextInt(12), 1 + r.nextInt(28)),
    tag: purposeTags[r.nextInt(purposeTags.length)],
    note: r.nextBool() ? '' : 'note $i',
    createdAt: 1700000000000 + r.nextInt(1000000),
  );
}

/// Minimal in-memory SharedPreferences, one per phone.
class _FakePrefs implements SharedPreferences {
  final _m = <String, Object>{};

  @override
  String? getString(String key) => _m[key] as String?;

  @override
  Future<bool> setString(String key, String value) async {
    _m[key] = value;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Lets queued stream events run.
Future<void> settle() => Future<void>.delayed(Duration.zero);

/// Collects every value a stream emits.
class Recorder<T> {
  Recorder(Stream<T> s) {
    sub = s.listen(values.add);
  }
  final values = <T>[];
  late final StreamSubscription<T> sub;
  T get last => values.last;
}
