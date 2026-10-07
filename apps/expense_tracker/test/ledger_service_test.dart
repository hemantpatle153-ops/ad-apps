import 'dart:math';

import 'package:expense_tracker/ledger/backend.dart';
import 'package:expense_tracker/ledger/model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ledger_world.dart';

void main() {
  group('create and join', () {
    test('creator is side a, friend joins as side b', () async {
      final w = await World.create();
      final (pa, pb, id, code) = await w.pair();
      final log = await pa.log(id);
      expect(log.nameA, 'Rahul');
      expect(log.nameB, 'Amit');
      expect(log.code, code);
      expect(log.members, {'uid-Rahul': Side.a, 'uid-Amit': Side.b});
      expect(pa.side(id), Side.a);
      expect(pb.side(id), Side.b);
      expect(pb.store.byId(id)!.friendName, 'Rahul');
      expect(pa.store.byId(id)!.friendName, 'Amit');
    });

    test('code is 8 characters from the safe alphabet', () async {
      final w = await World.create();
      final (_, _, _, code) = await w.pair();
      expect(normalizeJoinCode(code), code);
    });

    test('lookup accepts pretty, lower case and spaced codes', () async {
      final w = await World.create();
      final (_, pb, id, code) = await w.pair();
      for (final typed in [
        code,
        prettyCode(code),
        code.toLowerCase(),
        ' ${code.substring(0, 4)} ${code.substring(4)} ',
      ]) {
        expect((await pb.service.lookup(typed)).id, id, reason: typed);
      }
    });

    test('unknown code says not found', () async {
      final w = await World.create();
      final p = await w.phone('x');
      expect(() => p.service.lookup('ABCD2345'),
          throwsA(LedgerException.notFound));
    });

    test('malformed code is rejected before any lookup', () async {
      final w = await World.create();
      final p = await w.phone('x');
      for (final bad in [
        '',
        'ABC',
        'ABCD234',
        'ABCD23456',
        'ABCD-23O5',
        'ABCD1234'
      ]) {
        await expectLater(
            p.service.lookup(bad), throwsA(isA<LedgerException>()),
            reason: bad);
      }
      expect(w.db.writes, 0);
    });

    test('names are required', () async {
      final w = await World.create();
      final p = await w.phone('x');
      await expectLater(
          p.service.create(' ', 'Amit'), throwsA(isA<LedgerException>()));
      await expectLater(
          p.service.create('Rahul', ''), throwsA(isA<LedgerException>()));
    });

    test('names are trimmed and remembered', () async {
      final w = await World.create();
      final p = await w.phone('x');
      final l = await p.service.create('  Rahul   P ', ' Amit ');
      expect(l.nameA, 'Rahul P');
      expect(l.nameB, 'Amit');
      expect(p.store.myName, 'Rahul P');
    });

    test('a non-member cannot read the log', () async {
      final w = await World.create();
      final (_, _, id, _) = await w.pair();
      final stranger = await w.phone('stranger');
      expect(await stranger.read(id), isNull);
    });

    test('codes are unique per log', () async {
      final w = await World.create();
      final codes = <String>{};
      for (var i = 0; i < 20; i++) {
        final (_, _, _, code) = await w.pair(a: 'A$i', b: 'B$i');
        codes.add(code);
      }
      expect(codes.length, 20);
    });

    test('offline create fails with a clear message', () async {
      final w = await World.create();
      final p = await w.phone('x');
      w.db.offline = true;
      await expectLater(
          p.service.create('A', 'B'), throwsA(LedgerException.offline));
      expect(p.store.all(), isEmpty);
    });
  });

  group('both friends see the same ledger', () {
    test('entries from both phones add up the same on both', () async {
      final w = await World.create();
      final (pa, pb, id, _) = await w.pair();
      await add(pa, id, 50000, iGave: true, tag: 'Loan'); // Amit owes 500
      await add(pb, id, 20000, iGave: true, tag: 'Food'); // Rahul owes 200
      await add(pb, id, 5000, iGave: false); // Amit got 50 from Rahul
      final la = await pa.log(id), lb = await pb.log(id);
      final ba = la.balanceFor(Side.a), bb = lb.balanceFor(Side.b);
      expect(ba.theyGiveMe, 55000);
      expect(ba.iGiveThem, 20000);
      expect(ba.net, 35000);
      expect(bb.theyGiveMe, 20000);
      expect(bb.iGiveThem, 55000);
      expect(bb.net, -35000);
      expect(ba.payer, Side.b);
      expect(bb.payer, Side.b);
      expect(ba.amount, bb.amount);
    });

    test('an entry "I gave" on one phone is "gave me" on the other', () async {
      final w = await World.create();
      final (pa, pb, id, _) = await w.pair();
      final e = await add(pb, id, 1234, iGave: true);
      final la = await pa.log(id);
      final got = la.entries.single;
      expect(got.id, e.id);
      expect(got.by, Side.b);
      expect(got.by == Side.a, isFalse); // Rahul did not give it
      expect(got.createdBy, Side.b);
    });

    test('edit records who edited and when', () async {
      final w = await World.create();
      final (pa, pb, id, _) = await w.pair();
      await add(pa, id, 1000, iGave: true, tag: 'Food');
      w.db.advance(const Duration(days: 2));
      final lb = await pb.log(id);
      final e = lb.entries.single;
      await pb.service.saveEntry(lb, Side.b,
          e.copyWith(amount: 1500, tag: 'Trip', date: DateTime(2026, 9, 1)),
          isNew: false);
      final after = (await pa.log(id)).entries.single;
      expect(after.amount, 1500);
      expect(after.tag, 'Trip');
      expect(after.date, DateTime(2026, 9, 1));
      expect(after.createdBy, Side.a);
      expect(after.createdAt, e.createdAt);
      expect(after.editedBy, Side.b);
      expect(after.editedAt, w.db.nowMs);
      expect(after.isEdited, isTrue);
    });

    test('delete removes it for both', () async {
      final w = await World.create();
      final (pa, pb, id, _) = await w.pair();
      final e = await add(pa, id, 1000, iGave: true);
      await pb.service.deleteEntry(await pb.log(id), e.id);
      expect((await pa.log(id)).entries, isEmpty);
    });

    test('live updates reach the other phone', () async {
      final w = await World.create();
      final (pa, pb, id, _) = await w.pair();
      final rec = Recorder(pb.service.watch(id));
      await settle();
      await add(pa, id, 700, iGave: true);
      await settle();
      expect(rec.last!.entries.single.amount, 700);
      expect(pb.store.byId(id)!.log!.entries.single.amount, 700);
      await rec.sub.cancel();
    });

    test('sign of the final amount follows the reader', () async {
      final w = await World.create();
      final (pa, pb, id, _) = await w.pair();
      await add(pa, id, 300, iGave: false);
      expect((await pa.log(id)).balanceFor(Side.a).net, -300);
      expect((await pb.log(id)).balanceFor(Side.b).net, 300);
    });

    test('equal amounts both ways are all clear', () async {
      final w = await World.create();
      final (pa, pb, id, _) = await w.pair();
      await add(pa, id, 999, iGave: true);
      await add(pb, id, 999, iGave: true);
      final b = (await pa.log(id)).balanceFor(Side.a);
      expect(b.isClear, isTrue);
      expect(b.payer, isNull);
    });

    test('too large an amount is refused', () async {
      final w = await World.create();
      final (pa, _, id, _) = await w.pair();
      await expectLater(add(pa, id, maxEntryAmount + 1, iGave: true),
          throwsA(isA<LedgerException>()));
      await add(pa, id, maxEntryAmount, iGave: true);
    });
  });

  group('many phones', () {
    test('a friend can join on a second phone as the same person', () async {
      final w = await World.create();
      final (pa, _, id, code) = await w.pair();
      final pb2 = await w.phone('uid-Amit-tablet');
      final info = await pb2.service.lookup(code);
      await pb2.service.join(code, info, Side.b);
      await add(pb2, id, 400, iGave: true);
      final la = await pa.log(id);
      expect(la.devicesOf(Side.b), 2);
      expect(la.balanceFor(Side.a).iGiveThem, 400);
    });

    test('switching sides changes the view, not the data', () async {
      final w = await World.create();
      final (pa, pb, id, _) = await w.pair();
      await add(pa, id, 100, iGave: true);
      await pb.service.switchSide(pb.store.byId(id)!, Side.a);
      expect(pb.side(id), Side.a);
      expect((await pb.log(id)).members['uid-Amit'], Side.a);
      expect((await pb.log(id)).entries.single.by, Side.a);
    });

    test('leaving removes only this phone', () async {
      final w = await World.create();
      final (pa, pb, id, _) = await w.pair();
      await add(pa, id, 100, iGave: true);
      await pb.service.leave(pb.store.byId(id)!);
      expect(pb.store.byId(id), isNull);
      expect(await pb.read(id), isNull);
      final la = await pa.log(id);
      expect(la.entries, hasLength(1));
      expect(la.members.keys, ['uid-Rahul']);
    });

    test('rejoining after leaving gets the data back', () async {
      final w = await World.create();
      final (pa, pb, id, code) = await w.pair();
      await add(pa, id, 100, iGave: true);
      await pb.service.leave(pb.store.byId(id)!);
      await pb.service.join(code, await pb.service.lookup(code), Side.b);
      expect((await pb.log(id)).entries.single.amount, 100);
    });
  });

  group('reset code', () {
    test('keeps members, entries and confirmations', () async {
      final w = await World.create();
      final (pa, pb, id, code) = await w.pair();
      await add(pa, id, 100, iGave: true);
      await pa.service.approve(await pa.log(id), Side.a);
      final newCode = await pb.service.resetCode(await pb.log(id));
      expect(newCode, isNot(code));
      final log = await pa.log(id);
      expect(log.code, newCode);
      expect(log.members.length, 2);
      expect(log.entries, hasLength(1));
      expect(log.approvedBy(Side.a), isTrue);
      expect(await pb.read(id), isNotNull);
    });

    test('old code stops working, new one works', () async {
      final w = await World.create();
      final (pa, _, id, code) = await w.pair();
      final newCode = await pa.service.resetCode(await pa.log(id));
      final p3 = await w.phone('three');
      await expectLater(
          p3.service.lookup(code), throwsA(LedgerException.notFound));
      final info = await p3.service.lookup(newCode);
      expect(info.id, id);
      expect(info.nameA, 'Rahul');
    });

    test('reset many times leaves exactly one code', () async {
      final w = await World.create();
      final (pa, _, id, _) = await w.pair();
      for (var i = 0; i < 10; i++) {
        await pa.service.resetCode(await pa.log(id));
      }
      final codes = w.db.read('ledgerCodes') as Map;
      expect(codes.length, 1);
      expect((codes.values.single as Map)['id'], id);
    });

    test('rename updates the log and the code card', () async {
      final w = await World.create();
      final (pa, pb, id, code) = await w.pair();
      await pa.service.rename(await pa.log(id), Side.b, 'Amit K');
      expect((await pb.log(id)).nameB, 'Amit K');
      expect((await pb.service.lookup(code)).nameB, 'Amit K');
      expect(pa.store.byId(id)!.friendName, 'Amit K');
    });
  });

  group('clearing the ledger', () {
    test('one confirmation waits for the friend', () async {
      final w = await World.create();
      final (pa, pb, id, _) = await w.pair();
      await add(pa, id, 500, iGave: true);
      await pa.service.approve(await pa.log(id), Side.a);
      expect((await pa.log(id)).stageFor(Side.a), SettleStage.waitingForFriend);
      expect((await pb.log(id)).stageFor(Side.b), SettleStage.friendAsked);
      expect((await pb.log(id)).isSettled, isFalse);
    });

    test('second confirmation clears it, read-only, no code', () async {
      final w = await World.create();
      final (pa, pb, id, code) = await w.pair();
      await add(pa, id, 500, iGave: true);
      await pa.service.approve(await pa.log(id), Side.a);
      await pb.service.approve(await pb.log(id), Side.b);
      final log = await pa.log(id);
      expect(log.isSettled, isTrue);
      expect(log.settledAt, w.db.nowMs);
      expect(log.stageFor(Side.a), SettleStage.settled);
      expect(log.stageFor(Side.b), SettleStage.settled);
      expect(log.code, '');
      expect(w.db.read('ledgerCodes/$code'), isNull);
      expect(w.db.read('ledgerGc/$id'), {'t': w.db.nowMs});
      await expectLater(
          add(pa, id, 1, iGave: true), throwsA(isA<LedgerException>()));
      await expectLater(pb.service.deleteEntry(log, log.entries.single.id),
          throwsA(isA<LedgerException>()));
      await expectLater(
          pb.service.resetCode(log), throwsA(isA<LedgerException>()));
    });

    test('a change after a confirmation needs both to confirm again', () async {
      final w = await World.create();
      final (pa, pb, id, _) = await w.pair();
      await add(pa, id, 500, iGave: true);
      await pa.service.approve(await pa.log(id), Side.a);
      await add(pb, id, 100, iGave: true);
      final log = await pb.log(id);
      expect(log.approvals, isEmpty);
      expect(log.stageFor(Side.b), SettleStage.open);
      await pb.service.approve(log, Side.b);
      expect((await pa.log(id)).isSettled, isFalse);
      expect((await pa.log(id)).stageFor(Side.a), SettleStage.friendAsked);
    });

    test('a confirmation for an older version does not count', () async {
      final w = await World.create();
      final (pa, pb, id, _) = await w.pair();
      await add(pa, id, 500, iGave: true);
      final old = await pa.log(id);
      // Rahul's phone confirms what it saw...
      await pa.service.approve(old, Side.a);
      // ...while Amit's phone changes an entry without clearing confirmations
      // (an older app, or a write that crossed).
      final e = old.entries.single.copyWith(amount: 900);
      w.db.apply({'ledger/$id/entries/${e.id}/amt': 900});
      final now = await pb.log(id);
      expect(now.approvals.containsKey(Side.a), isTrue);
      expect(now.approvedBy(Side.a), isFalse);
      expect(now.staleApprovalBy(Side.a), isTrue);
      expect(now.stageFor(Side.b), SettleStage.open);
      await pb.service.approve(now, Side.b);
      expect((await pa.log(id)).isSettled, isFalse);
    });

    test('both confirming at once is finished by the next phone that looks',
        () async {
      final w = await World.create();
      final (pa, pb, id, _) = await w.pair();
      await add(pa, id, 500, iGave: true);
      final la = await pa.log(id), lb = await pb.log(id);
      await pa.service.approve(la, Side.a);
      await pb.service.approve(lb, Side.b); // built from the old copy
      expect((await pa.log(id)).isSettled, isFalse);
      final rec = Recorder(pa.service.watch(id));
      await settle();
      await settle();
      expect((await pa.log(id)).isSettled, isTrue);
      await rec.sub.cancel();
    });

    test('take back before the friend confirms', () async {
      final w = await World.create();
      final (pa, pb, id, _) = await w.pair();
      await add(pa, id, 500, iGave: true);
      await pa.service.approve(await pa.log(id), Side.a);
      await pa.service.withdraw(await pa.log(id), Side.a);
      expect((await pb.log(id)).stageFor(Side.b), SettleStage.open);
    });

    test('empty log cannot be confirmed', () async {
      final w = await World.create();
      final (pa, _, id, _) = await w.pair();
      await expectLater(pa.service.approve(await pa.log(id), Side.a),
          throwsA(isA<LedgerException>()));
    });

    test('reopen within two weeks, with a new code', () async {
      final w = await World.create();
      final (pa, pb, id, _) = await w.pair();
      await add(pa, id, 500, iGave: true);
      await pa.service.approve(await pa.log(id), Side.a);
      await pb.service.approve(await pb.log(id), Side.b);
      w.db.advance(const Duration(days: 13));
      final code = await pb.service.reopen(await pb.log(id));
      final log = await pa.log(id);
      expect(log.isSettled, isFalse);
      expect(log.approvals, isEmpty);
      expect(log.code, code);
      expect(w.db.read('ledgerGc/$id'), isNull);
      expect((await pa.service.lookup(code)).id, id);
      await add(pa, id, 1, iGave: true);
    });

    test('the cleared copy stays readable for two weeks, then is deleted',
        () async {
      final w = await World.create();
      final (pa, pb, id, _) = await w.pair();
      await add(pa, id, 500, iGave: true, tag: 'Loan');
      await pa.service.approve(await pa.log(id), Side.a);
      await pb.service.approve(await pb.log(id), Side.b);
      // Both phones saw the cleared log.
      for (final p in [pa, pb]) {
        final rec = Recorder(p.service.watch(id));
        await settle();
        await rec.sub.cancel();
      }
      w.db.advance(const Duration(days: 13, hours: 23));
      expect(await pa.service.cleanUp(), 0);
      expect(await pa.read(id), isNotNull);
      w.db.advance(const Duration(hours: 2));
      expect(await pa.service.cleanUp(), 1);
      expect(w.db.read('ledger'), isNull);
      expect(w.db.read('ledgerGc'), isNull);
      expect(w.db.read('ledgerCodes'), isNull);
      // Rahul's phone keeps its copy, marked as phone-only.
      final local = pa.store.byId(id)!;
      expect(local.archived, isTrue);
      expect(local.log!.entries.single.tag, 'Loan');
      expect(local.log!.balanceFor(Side.a).net, 500);
      // Amit's phone learns it was deleted the next time it looks.
      final rec = Recorder(pb.service.watch(id));
      await settle();
      expect(rec.last, isNull);
      expect(pb.store.byId(id)!.archived, isTrue);
      expect(pb.store.byId(id)!.log!.balanceFor(Side.b).net, -500);
      await rec.sub.cancel();
    });

    test('logs nobody opens are deleted by any phone after two weeks',
        () async {
      final w = await World.create();
      final (pa, pb, id, _) = await w.pair();
      await add(pa, id, 500, iGave: true);
      await pa.service.approve(await pa.log(id), Side.a);
      await pb.service.approve(await pb.log(id), Side.b);
      w.db.advance(const Duration(days: 15));
      final stranger = await w.phone('someone-else');
      expect(await stranger.service.cleanUp(), 1);
      expect(w.db.read('ledger'), isNull);
      expect(w.db.read('ledgerGc'), isNull);
    });

    test('cleanup leaves open and recent logs alone', () async {
      final w = await World.create();
      final (pa, pb, id, _) = await w.pair();
      await add(pa, id, 500, iGave: true);
      final (pc, pd, id2, _) = await w.pair(a: 'C', b: 'D');
      await add(pc, id2, 5, iGave: true);
      await pc.service.approve(await pc.log(id2), Side.a);
      await pd.service.approve(await pd.log(id2), Side.b);
      w.db.advance(const Duration(days: 3));
      expect(await pa.service.cleanUp(), 0);
      w.db.advance(const Duration(days: 300));
      expect(await pb.service.cleanUp(), 1);
      expect(await pa.read(id), isNotNull);
      expect(await pc.read(id2), isNull);
    });

    test('cleanup offline does nothing and does not throw', () async {
      final w = await World.create();
      final (pa, _, _, _) = await w.pair();
      w.db.offline = true;
      expect(await pa.service.cleanUp(), 0);
    });

    test('an empty log can be deleted for both', () async {
      final w = await World.create();
      final (pa, _, id, code) = await w.pair();
      await pa.service.deleteEmpty(await pa.log(id));
      expect(w.db.read('ledger/$id'), isNull);
      expect(w.db.read('ledgerCodes/$code'), isNull);
      expect(pa.store.byId(id), isNull);
    });

    test('a log with entries cannot be deleted', () async {
      final w = await World.create();
      final (pa, _, id, _) = await w.pair();
      await add(pa, id, 1, iGave: true);
      await expectLater(pa.service.deleteEmpty(await pa.log(id)),
          throwsA(isA<LedgerException>()));
    });
  });

  group('getting ledgers back on a new phone', () {
    test('reinstall without email: join with the code, same side, same data',
        () async {
      final w = await World.create();
      final (pa, pb, id, code) = await w.pair();
      await add(pa, id, 50000, iGave: true, tag: 'Loan');
      await add(pb, id, 20000, iGave: true);
      // Amit deletes the app: new phone user, empty list.
      final pb2 = await w.phone('uid-Amit-reinstalled');
      expect(pb2.store.all(), isEmpty);
      final info = await pb2.service.lookup(code);
      expect(info.nameB, 'Amit');
      await pb2.service.join(code, info, Side.b);
      final log = await pb2.log(id);
      expect(log.entries, hasLength(2));
      expect(log.balanceFor(Side.b).net, -30000);
      // Still two people, not three: the entries are Amit's side.
      expect(log.members.values.toSet(), {Side.a, Side.b});
      await add(pb2, id, 1000, iGave: true);
      expect((await pa.log(id)).balanceFor(Side.a).net, 29000);
    });

    test('reinstall after a code reset needs the new code', () async {
      final w = await World.create();
      final (pa, _, id, code) = await w.pair();
      final newCode = await pa.service.resetCode(await pa.log(id));
      final pb2 = await w.phone('uid-Amit-2');
      await expectLater(
          pb2.service.lookup(code), throwsA(LedgerException.notFound));
      await pb2.service
          .join(newCode, await pb2.service.lookup(newCode), Side.b);
      expect(await pb2.read(id), isNotNull);
    });

    test('backup keeps the same user, so nothing needs rejoining', () async {
      final w = await World.create();
      final (pa, _, id, _) = await w.pair();
      final before = await pa.service.uid();
      await pa.service.backUp('rahul@example.com', 'secret1');
      expect(pa.service.email, 'rahul@example.com');
      expect(await pa.service.uid(), before);
      expect(await pa.read(id), isNotNull);
      expect(w.db.read('ledgerUsers/$before/ledgers'), {id: 'a'});
    });

    test('sign in on a new phone restores every ledger with its side',
        () async {
      final w = await World.create();
      final (pa, _, id1, _) = await w.pair();
      final (pc, pd, id2, code2) = await w.pair(a: 'Neha', b: 'Rahul2');
      // Rahul is side b in a ledger Neha started.
      await pa.service.join(code2, await pa.service.lookup(code2), Side.b);
      await add(pa, id1, 700, iGave: true, tag: 'Food');
      await pa.service.backUp('rahul@example.com', 'secret1');
      final fresh = await w.phone('uid-new-phone');
      final n =
          await fresh.service.signInEmail(' rahul@example.com ', 'secret1');
      expect(n, 2);
      expect(fresh.side(id1), Side.a);
      expect(fresh.side(id2), Side.b);
      expect(fresh.store.byId(id1)!.log!.entries.single.tag, 'Food');
      expect((await fresh.log(id1)).balanceFor(Side.a).net, 700);
      await add(fresh, id1, 100, iGave: true);
      expect((await pa.log(id1)).balanceFor(Side.a).net, 800);
      expect(pc, isNotNull);
      expect(pd, isNotNull);
    });

    test('ledgers made before signing in join the account', () async {
      final w = await World.create();
      final (pa, _, _, _) = await w.pair();
      await pa.service.backUp('rahul@example.com', 'secret1');
      // A second phone already has a ledger of its own, then signs in.
      final (p2, _, id2, _) = await w.pair(a: 'Rahul', b: 'Neha');
      final n = await p2.service.signInEmail('rahul@example.com', 'secret1');
      expect(n, 2);
      final uid = await p2.service.uid();
      expect((await p2.log(id2)).members[uid], Side.a);
      expect((w.db.read('ledgerUsers/$uid/ledgers') as Map).length, 2);
    });

    test('wrong password and unknown email are refused', () async {
      final w = await World.create();
      final (pa, _, _, _) = await w.pair();
      await pa.service.backUp('rahul@example.com', 'secret1');
      final p = await w.phone('x');
      await expectLater(p.service.signInEmail('rahul@example.com', 'nope'),
          throwsA(LedgerException.wrongLogin));
      await expectLater(p.service.signInEmail('who@example.com', 'secret1'),
          throwsA(LedgerException.wrongLogin));
      expect(p.store.all(), isEmpty);
    });

    test('an email can back up only one account', () async {
      final w = await World.create();
      final (pa, pb, _, _) = await w.pair();
      await pa.service.backUp('same@example.com', 'secret1');
      await expectLater(pb.service.backUp('same@example.com', 'secret2'),
          throwsA(LedgerException.emailInUse));
      expect(pb.service.email, isNull);
    });

    test('short password and bad email are refused', () async {
      final w = await World.create();
      final (pa, _, _, _) = await w.pair();
      await expectLater(pa.service.backUp('rahul@example.com', '123'),
          throwsA(LedgerException.weakPassword));
      await expectLater(pa.service.backUp('not-an-email', 'secret1'),
          throwsA(LedgerException.badEmail));
    });

    test('sign out clears the phone list, sign in brings it back', () async {
      final w = await World.create();
      final (pa, _, id, _) = await w.pair();
      await pa.service.backUp('rahul@example.com', 'secret1');
      await pa.service.signOut();
      expect(pa.store.all(), isEmpty);
      expect(pa.service.email, isNull);
      expect(await pa.read(id), isNull);
      await pa.service.signInEmail('rahul@example.com', 'secret1');
      expect(pa.store.byId(id)!.side, Side.a);
      expect(await pa.read(id), isNotNull);
    });

    test('delete account removes the login and its ledger list', () async {
      final w = await World.create();
      final (pa, pb, id, _) = await w.pair();
      await add(pa, id, 500, iGave: true);
      await pa.service.backUp('rahul@example.com', 'secret1');
      await expectLater(pa.service.deleteAccount('wrong1'),
          throwsA(LedgerException.wrongLogin));
      expect(pa.service.email, 'rahul@example.com');
      await pa.service.deleteAccount('secret1');
      expect(pa.service.email, isNull);
      expect(pa.store.all(), isEmpty);
      expect(w.db.read('ledgerUsers/uid-Rahul'), isNull);
      await expectLater(pa.service.signInEmail('rahul@example.com', 'secret1'),
          throwsA(LedgerException.wrongLogin));
      // The friend still has the shared ledger.
      expect((await pb.log(id)).entries, hasLength(1));
      // The email is free again.
      await pa.service.backUp('rahul@example.com', 'secret2');
    });

    test('deleted ledgers drop out of the account list', () async {
      final w = await World.create();
      final (pa, pb, id, _) = await w.pair();
      await add(pa, id, 500, iGave: true);
      await pa.service.backUp('rahul@example.com', 'secret1');
      await pa.service.approve(await pa.log(id), Side.a);
      await pb.service.approve(await pb.log(id), Side.b);
      w.db.advance(const Duration(days: 15));
      await pb.service.cleanUp(); // Amit's phone never saw it settled
      final fresh = await w.phone('new');
      expect(
          await fresh.service.signInEmail('rahul@example.com', 'secret1'), 0);
      expect(w.db.read('ledgerUsers/uid-Rahul'), isNull);
    });

    test('leaving takes the ledger out of the account list', () async {
      final w = await World.create();
      final (pa, _, id, _) = await w.pair();
      await pa.service.backUp('rahul@example.com', 'secret1');
      await pa.service.leave(pa.store.byId(id)!);
      final fresh = await w.phone('new');
      expect(
          await fresh.service.signInEmail('rahul@example.com', 'secret1'), 0);
    });
  });

  group('random sessions agree on both phones', () {
    for (var seed = 0; seed < 150; seed++) {
      test('session $seed', () async {
        final r = Random(seed);
        final w = await World.create();
        final (pa, pb, id, _) = await w.pair();
        final phones = [pa, pb];
        final ref = <String, (int, Side)>{};
        final steps = 1 + r.nextInt(12);
        for (var i = 0; i < steps; i++) {
          final p = phones[r.nextInt(2)];
          final me = p.side(id);
          final log = await p.log(id);
          final action = log.entries.isEmpty ? 0 : r.nextInt(4);
          if (action <= 1) {
            final amt = 1 + r.nextInt(1000000);
            final gave = r.nextBool();
            final e = await add(p, id, amt, iGave: gave);
            ref[e.id] = (amt, gave ? me : me.other);
          } else if (action == 2) {
            final e = log.entries[r.nextInt(log.entries.length)];
            final amt = 1 + r.nextInt(1000000);
            final by = r.nextBool() ? Side.a : Side.b;
            await p.service.saveEntry(log, me, e.copyWith(amount: amt, by: by),
                isNew: false);
            ref[e.id] = (amt, by);
          } else {
            final e = log.entries[r.nextInt(log.entries.length)];
            await p.service.deleteEntry(log, e.id);
            ref.remove(e.id);
          }
        }
        final la = await pa.log(id), lb = await pb.log(id);
        final expected = refNetForA(ref.values.toList());
        expect(la.balanceFor(Side.a).net, expected);
        expect(lb.balanceFor(Side.b).net, -expected);
        expect(la.sig, lb.sig);
        expect(la.entries.length, ref.length);
        // Who pays whom reads the same on both phones.
        expect(la.balanceFor(Side.a).payer, lb.balanceFor(Side.b).payer);
        expect(la.balanceFor(Side.a).amount, expected.abs());
      });
    }
  });
}
