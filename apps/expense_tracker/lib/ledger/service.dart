import 'dart:async';

import 'backend.dart';
import 'model.dart';
import 'store.dart';

/// Everything the ledger screens do, on top of a [LedgerBackend] (the cloud)
/// and a [LedgerStore] (this phone's list and copies).
class LedgerService {
  LedgerService(this.backend, this.store);

  final LedgerBackend backend;
  final LedgerStore store;

  Future<String> uid() => backend.signIn();

  int nowMs() => backend.nowMs();

  /// Starts a new log between me and [friendName], with a fresh code.
  Future<LocalLog> create(String myName, String friendName) async {
    final me = cleanName(myName), friend = cleanName(friendName);
    if (me.isEmpty || friend.isEmpty) {
      throw const LedgerException('Enter both names.');
    }
    final uid = await backend.signIn();
    final id = backend.newKey();
    final code = await _freeCode();
    await backend.update(LedgerWrites.create(
        id: id, code: code, uid: uid, myName: me, friendName: friend));
    store.myName = me;
    final local = LocalLog(id: id, side: Side.a, nameA: me, nameB: friend);
    await store.put(local);
    return local;
  }

  Future<String> _freeCode() async {
    for (var i = 0; i < 6; i++) {
      final code = newJoinCode();
      if (await backend.get(LedgerWrites.codePath(code)) == null) return code;
    }
    throw LedgerException.offline;
  }

  /// What a typed code points at.
  Future<CodeInfo> lookup(String rawCode) async {
    final code = normalizeJoinCode(rawCode);
    if (code == null) {
      throw const LedgerException(
          'A code has 8 letters and digits, like ABCD-2345.');
    }
    final info =
        CodeInfo.fromJson(await backend.get(LedgerWrites.codePath(code)));
    if (info == null) throw LedgerException.notFound;
    return info;
  }

  /// Joins with a code as one of the two friends. Joining again from the
  /// same phone just switches sides.
  Future<LocalLog> join(String rawCode, CodeInfo info, Side side) async {
    final code = normalizeJoinCode(rawCode)!;
    final uid = await backend.signIn();
    await backend.update(
        LedgerWrites.join(info: info, code: code, uid: uid, side: side));
    store.myName = info.nameOf(side);
    final local =
        LocalLog(id: info.id, side: side, nameA: info.nameA, nameB: info.nameB);
    final old = store.byId(info.id);
    await store.put(old == null
        ? local
        : old.copyWith(
            side: side, nameA: info.nameA, nameB: info.nameB, archived: false));
    return store.byId(info.id)!;
  }

  /// The live log. Each version is also saved on the phone. When the cloud
  /// copy disappears, the phone's last copy is marked archived and this
  /// emits null.
  Stream<LedgerLog?> watch(String id) =>
      backend.watch(LedgerWrites.logPath(id)).asyncMap((raw) async {
        final log = LedgerLog.fromJson(id, raw);
        final local = store.byId(id);
        if (log == null) {
          if (local != null && !local.archived) {
            await store.put(local.copyWith(archived: true));
          }
          return null;
        }
        if (local != null) {
          await store.remember(id, local.side, log);
          if (log.approvedBy(Side.a) &&
              log.approvedBy(Side.b) &&
              !log.isSettled) {
            unawaited(
                backend.update(LedgerWrites.finalize(log)).catchError((_) {}));
          }
        }
        return log;
      });

  LedgerEntry newEntry({
    required int amount,
    required Side by,
    required DateTime date,
    String tag = '',
    String note = '',
  }) =>
      LedgerEntry(
        id: backend.newKey(),
        amount: amount,
        by: by,
        date: date,
        tag: cleanText(tag, maxTagLength),
        note: cleanText(note, maxNoteLength),
      );

  Future<void> saveEntry(LedgerLog log, Side me, LedgerEntry e,
      {required bool isNew}) async {
    _checkOpen(log);
    if (e.amount <= 0 || e.amount > maxEntryAmount) {
      throw const LedgerException('Enter an amount up to ₹1,000 crore.');
    }
    await backend.update(LedgerWrites.saveEntry(log, e, me, isNew: isNew));
  }

  Future<void> deleteEntry(LedgerLog log, String entryId) async {
    _checkOpen(log);
    await backend.update(LedgerWrites.deleteEntry(log, entryId));
  }

  void _checkOpen(LedgerLog log) {
    if (!log.editable) {
      throw const LedgerException(
          'This ledger is settled. Reopen it to change entries.');
    }
  }

  /// "The ledger is right." Clears it when my friend already agreed.
  Future<void> approve(LedgerLog log, Side me) async {
    _checkOpen(log);
    if (log.entries.isEmpty) {
      throw const LedgerException('Add an entry first.');
    }
    await backend.update(LedgerWrites.approve(log, me));
  }

  Future<void> withdraw(LedgerLog log, Side me) =>
      backend.update(LedgerWrites.withdraw(log, me));

  Future<String> reopen(LedgerLog log) async {
    if (!log.isSettled) return log.code;
    final code = await _freeCode();
    await backend.update(LedgerWrites.reopen(log, code));
    return code;
  }

  /// A new join code for the same log; nobody is removed.
  Future<String> resetCode(LedgerLog log) async {
    if (log.isSettled) {
      throw const LedgerException(
          'A settled ledger has no code. Reopen it to get a new one.');
    }
    final code = await _freeCode();
    await backend.update(LedgerWrites.resetCode(log, code));
    return code;
  }

  Future<void> rename(LedgerLog log, Side side, String name) async {
    final n = cleanName(name);
    if (n.isEmpty) throw const LedgerException('Enter a name.');
    await backend.update(LedgerWrites.rename(log, side, n));
    final local = store.byId(log.id);
    if (local != null) {
      await store.put(
          side == Side.a ? local.copyWith(nameA: n) : local.copyWith(nameB: n));
    }
  }

  /// Says this phone belongs to the other friend (a shared phone, or a
  /// wrong pick when joining).
  Future<void> switchSide(LocalLog local, Side side) async {
    final uid = await backend.signIn();
    await backend.update(LedgerWrites.switchSide(local.id, uid, side));
    await store.put(local.copyWith(side: side));
  }

  /// Removes this phone from the log. The log and the friend's phones are
  /// not touched; the code joins again later.
  Future<void> leave(LocalLog local) async {
    if (!local.archived) {
      final uid = await backend.signIn();
      await backend.update(LedgerWrites.leave(local.id, uid));
    }
    await store.remove(local.id);
  }

  /// Deletes a log with no entries from the cloud, for both friends.
  Future<void> deleteEmpty(LedgerLog log) async {
    if (log.entries.isNotEmpty) {
      throw const LedgerException(
          'Only an empty ledger can be deleted. Settle up with your friend '
          'instead; it is removed $settledKeepDays days later.');
    }
    await backend.update(LedgerWrites.delete(log.id, log.code));
    await store.remove(log.id);
  }

  /// Keeps the cloud clean: deletes cleared logs whose keep time is over,
  /// both this phone's and anyone else's left behind. Best effort; runs
  /// again next time.
  Future<int> cleanUp() async {
    var deleted = 0;
    try {
      final now = backend.nowMs();
      for (final local in store.all()) {
        final log = local.log;
        if (local.archived || log == null || !log.isExpired(now)) continue;
        await backend.update(LedgerWrites.delete(log.id, log.code));
        await store.put(local.copyWith(archived: true));
        deleted++;
      }
      // A minute of slack so the server's clock agrees it is old enough.
      final old =
          await backend.expired(now - settledKeep.inMilliseconds - 60000);
      for (final id in old) {
        await backend.update(LedgerWrites.delete(id, ''));
        deleted++;
      }
    } catch (_) {
      // Offline or a rule said no: try again next time.
    }
    return deleted;
  }
}
