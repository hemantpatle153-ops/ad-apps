import 'dart:math';

import 'package:expense_tracker/ledger/model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ledger_world.dart';

LedgerLog logOf(List<LedgerEntry> entries,
        {Map<Side, Approval> approvals = const {}, int? settledAt}) =>
    LedgerLog(
      id: 'L',
      nameA: 'Rahul',
      nameB: 'Amit',
      code: 'ABCD2345',
      entries: [...entries]..sort(compareEntries),
      approvals: approvals,
      settledAt: settledAt,
    );

LedgerEntry e(String id, int amt, Side by, {DateTime? date}) => LedgerEntry(
    id: id, amount: amt, by: by, date: date ?? DateTime(2026, 10, 6));

void main() {
  group('Side', () {
    test('other flips', () {
      expect(Side.a.other, Side.b);
      expect(Side.b.other, Side.a);
      expect(Side.a.other.other, Side.a);
    });
    for (final (raw, want) in [
      ('a', Side.a),
      ('b', Side.b),
      ('c', null),
      ('', null),
      ('A', null),
      (null, null),
      (1, null),
    ]) {
      test('parse $raw', () => expect(Side.parse(raw), want));
    }
  });

  group('Balance worked examples', () {
    test('nothing is all clear', () {
      final b = Balance.of([], Side.a);
      expect(b.net, 0);
      expect(b.isClear, isTrue);
      expect(b.payer, isNull);
      expect(b.receiver, isNull);
    });

    test('I lent 500: friend gives me 500', () {
      final b = Balance.of([e('1', 50000, Side.a)], Side.a);
      expect(b.theyGiveMe, 50000);
      expect(b.iGiveThem, 0);
      expect(b.net, 50000);
      expect(b.payer, Side.b);
      expect(b.receiver, Side.a);
    });

    test('friend lent me 500: I give 500', () {
      final b = Balance.of([e('1', 50000, Side.b)], Side.a);
      expect(b.net, -50000);
      expect(b.payer, Side.a);
      expect(b.amount, 50000);
    });

    test('500 out, 200 in: friend gives 300', () {
      final b =
          Balance.of([e('1', 50000, Side.a), e('2', 20000, Side.b)], Side.a);
      expect(b.theyGiveMe, 50000);
      expect(b.iGiveThem, 20000);
      expect(b.net, 30000);
      expect(b.amount, 30000);
      expect(b.theyGiveMeCount, 1);
      expect(b.iGiveThemCount, 1);
    });

    test('same numbers from the friend side', () {
      final b =
          Balance.of([e('1', 50000, Side.a), e('2', 20000, Side.b)], Side.b);
      expect(b.theyGiveMe, 20000);
      expect(b.iGiveThem, 50000);
      expect(b.net, -30000);
      expect(b.payer, Side.b);
    });

    test('paise are exact', () {
      final b = Balance.of([
        for (var i = 0; i < 10; i++) e('$i', 10, Side.a),
        e('x', 1, Side.b),
      ], Side.a);
      expect(b.net, 99);
    });

    test('largest entries keep exact totals', () {
      final b = Balance.of([
        for (var i = 0; i < 50; i++) e('$i', maxEntryAmount, Side.a),
      ], Side.a);
      expect(b.net, 50 * maxEntryAmount);
    });
  });

  group('Balance matches the reference on random logs', () {
    for (var seed = 0; seed < 250; seed++) {
      test('log $seed', () {
        final r = Random(seed * 7 + 1);
        final entries = [
          for (var i = 0; i < r.nextInt(40); i++) randomEntry(r, i)
        ];
        final want = refNetForA([for (final x in entries) (x.amount, x.by)]);
        final a = Balance.of(entries, Side.a);
        final b = Balance.of(entries, Side.b);
        expect(a.net, want);
        expect(b.net, -want);
        expect(a.theyGiveMe, b.iGiveThem);
        expect(a.iGiveThem, b.theyGiveMe);
        expect(a.payer, b.payer);
        expect(a.receiver, b.receiver);
        expect(a.amount, b.amount);
        expect(a.theyGiveMeCount + a.iGiveThemCount, entries.length);
        expect(netForA(entries), want);
        if (want != 0) {
          expect(a.payer, want > 0 ? Side.b : Side.a);
        }
      });
    }
  });

  group('LedgerEntry json', () {
    for (var seed = 0; seed < 150; seed++) {
      test('round trip $seed', () {
        final r = Random(seed + 1000);
        var x = randomEntry(r, seed);
        if (r.nextBool()) {
          x = LedgerEntry(
            id: x.id,
            amount: x.amount,
            by: x.by,
            date: x.date,
            tag: x.tag,
            note: x.note,
            createdAt: x.createdAt,
            createdBy: r.nextBool() ? Side.a : Side.b,
            editedAt: x.createdAt + 5000,
            editedBy: r.nextBool() ? Side.a : Side.b,
          );
        }
        final y = LedgerEntry.fromJson(x.id, x.toJson())!;
        expect(y.amount, x.amount);
        expect(y.by, x.by);
        expect(y.date, x.date);
        expect(y.tag, x.tag);
        expect(y.note, x.note);
        expect(y.createdAt, x.createdAt);
        expect(y.createdBy, x.createdBy);
        expect(y.editedAt, x.editedAt);
        expect(y.editedBy, x.editedBy);
        expect(y.isEdited, x.editedAt != null);
        expect(y.owedBy, x.by.other);
      });
    }

    for (final (name, raw) in <(String, Object?)>[
      ('null', null),
      ('string', 'x'),
      ('list', [1, 2]),
      ('no amount', {'by': 'a', 'date': 1}),
      ('zero amount', {'amt': 0, 'by': 'a', 'date': 1}),
      ('negative', {'amt': -1, 'by': 'a', 'date': 1}),
      ('too large', {'amt': maxEntryAmount + 1, 'by': 'a', 'date': 1}),
      ('bad side', {'amt': 1, 'by': 'x', 'date': 1}),
      ('no date', {'amt': 1, 'by': 'a'}),
      ('text amount', {'amt': '5', 'by': 'a', 'date': 1}),
    ]) {
      test('rejects $name',
          () => expect(LedgerEntry.fromJson('id', raw), isNull));
    }

    test('double amounts from the database read as ints', () {
      final x =
          LedgerEntry.fromJson('i', {'amt': 500.0, 'by': 'b', 'date': 1.0});
      expect(x!.amount, 500);
      expect(x.date.millisecondsSinceEpoch, 1);
    });

    test('missing optional fields get defaults', () {
      final x = LedgerEntry.fromJson('i', {'amt': 5, 'by': 'a', 'date': 0})!;
      expect(x.tag, '');
      expect(x.note, '');
      expect(x.createdAt, 0);
      expect(x.createdBy, isNull);
      expect(x.editedAt, isNull);
    });
  });

  group('sort order', () {
    test('newest day first, then newest added, then id', () {
      final list = [
        LedgerEntry(
            id: 'b',
            amount: 1,
            by: Side.a,
            date: DateTime(2026, 1, 1),
            createdAt: 5),
        LedgerEntry(
            id: 'a',
            amount: 1,
            by: Side.a,
            date: DateTime(2026, 1, 1),
            createdAt: 5),
        LedgerEntry(
            id: 'c',
            amount: 1,
            by: Side.a,
            date: DateTime(2026, 1, 2),
            createdAt: 1),
        LedgerEntry(
            id: 'd',
            amount: 1,
            by: Side.a,
            date: DateTime(2026, 1, 1),
            createdAt: 9),
      ]..sort(compareEntries);
      expect([for (final x in list) x.id], ['c', 'd', 'b', 'a']);
    });

    for (var seed = 0; seed < 30; seed++) {
      test('same order on any phone $seed', () {
        final r = Random(seed);
        final entries = [for (var i = 0; i < 25; i++) randomEntry(r, i)];
        final x = [...entries]..sort(compareEntries);
        final y = [...entries.reversed]..sort(compareEntries);
        expect([for (final e in x) e.id], [for (final e in y) e.id]);
      });
    }
  });

  group('fingerprint', () {
    for (var seed = 0; seed < 80; seed++) {
      test('ignores order, notices changes $seed', () {
        final r = Random(seed + 500);
        final entries = [
          for (var i = 0; i < 1 + r.nextInt(15); i++) randomEntry(r, i)
        ];
        final sig = fingerprint(entries);
        expect(fingerprint(entries.reversed), sig);
        expect(fingerprint([...entries]..shuffle(r)), sig);
        final i = r.nextInt(entries.length);
        final changed = [...entries];
        changed[i] = entries[i].copyWith(amount: entries[i].amount + 1);
        expect(fingerprint(changed), isNot(sig));
        final flipped = [...entries];
        flipped[i] = entries[i].copyWith(by: entries[i].by.other);
        expect(fingerprint(flipped), isNot(sig));
        final moved = [...entries];
        moved[i] = entries[i]
            .copyWith(date: entries[i].date.add(const Duration(days: 1)));
        expect(fingerprint(moved), isNot(sig));
        expect(fingerprint(entries.skip(1)), isNot(sig));
        // A note or tag change does not change what is owed.
        final noted = [...entries];
        noted[i] = entries[i].copyWith(note: 'changed', tag: 'Other');
        expect(fingerprint(noted), sig);
        expect(sig.length, lessThanOrEqualTo(64));
      });
    }

    test('empty log', () => expect(fingerprint([]), startsWith('0.0.')));
  });

  group('settle stages', () {
    final entries = [e('1', 500, Side.a), e('2', 200, Side.b)];
    final sig = fingerprint(entries);
    Approval ok([String? s]) => Approval(sig: s ?? sig, net: 300);

    for (final (name, approvals, a, b) in [
      ('nobody', <Side, Approval>{}, SettleStage.open, SettleStage.open),
      (
        'a only',
        {Side.a: ok()},
        SettleStage.waitingForFriend,
        SettleStage.friendAsked
      ),
      (
        'b only',
        {Side.b: ok()},
        SettleStage.friendAsked,
        SettleStage.waitingForFriend
      ),
      (
        'both',
        {Side.a: ok(), Side.b: ok()},
        SettleStage.settled,
        SettleStage.settled
      ),
      ('a stale', {Side.a: ok('old')}, SettleStage.open, SettleStage.open),
      (
        'b stale, a fresh',
        {Side.a: ok(), Side.b: ok('old')},
        SettleStage.waitingForFriend,
        SettleStage.friendAsked
      ),
      (
        'both stale',
        {Side.a: ok('x'), Side.b: ok('y')},
        SettleStage.open,
        SettleStage.open
      ),
    ]) {
      test(name, () {
        final log = logOf(entries, approvals: approvals);
        expect(log.stageFor(Side.a), a);
        expect(log.stageFor(Side.b), b);
        expect(log.isSettled, isFalse);
      });
    }

    test('stale approvals are reported', () {
      final log = logOf(entries, approvals: {Side.b: ok('old')});
      expect(log.staleApprovalBy(Side.b), isTrue);
      expect(log.staleApprovalBy(Side.a), isFalse);
      expect(log.approvedBy(Side.b), isFalse);
    });

    test('settled wins over anything', () {
      final log = logOf(entries, settledAt: 1000);
      expect(log.stageFor(Side.a), SettleStage.settled);
      expect(log.editable, isFalse);
    });
  });

  group('two week keep', () {
    const day = Duration.millisecondsPerDay;
    const t0 = 1700000000000;
    final log = logOf([e('1', 1, Side.a)], settledAt: t0);

    test('open logs never expire', () {
      final open = logOf([e('1', 1, Side.a)]);
      expect(open.deleteAt, isNull);
      expect(open.isExpired(t0 * 2), isFalse);
      expect(open.daysLeft(t0), settledKeepDays);
    });

    test('delete time is 14 days after clearing', () {
      expect(log.deleteAt, t0 + 14 * day);
    });

    for (var h = 0; h <= 15 * 24; h += 6) {
      test('after $h hours', () {
        final now = t0 + h * Duration.millisecondsPerHour;
        final expired = h >= 14 * 24;
        expect(log.isExpired(now), expired);
        final left = log.daysLeft(now);
        expect(left, expired ? 0 : ((14 * 24 - h) / 24).ceil());
        expect(left, inInclusiveRange(0, 14));
      });
    }
  });

  group('codes', () {
    for (var seed = 0; seed < 120; seed++) {
      test('new code $seed is valid and survives pretty printing', () {
        final c = newJoinCode(Random(seed));
        expect(c.length, codeLength);
        expect(normalizeJoinCode(c), c);
        expect(normalizeJoinCode(prettyCode(c)), c);
        expect(normalizeJoinCode(prettyCode(c).toLowerCase()), c);
        expect(
            normalizeJoinCode(' ${c.substring(0, 4)} ${c.substring(4)} '), c);
        expect(prettyCode(c)[4], '-');
        for (final ch in c.split('')) {
          expect('0O1IL'.contains(ch), isFalse);
        }
        expect(
            findJoinCode('Rahul invited you. Enter ${prettyCode(c)} to join'),
            c);
        expect(findJoinCode('code: $c.'), c);
      });
    }

    for (final bad in [
      '',
      'ABC',
      'ABCDEFG',
      'ABCDEFGHJ',
      'ABCD-EFG0',
      'ABCD-EFGO',
      'ABCD-EFG1',
      'ABCD-EFGI',
      'ABCD-EFGL',
      'ABCD EF!H',
      'ÄBCD2345',
    ]) {
      test('rejects "$bad"', () => expect(normalizeJoinCode(bad), isNull));
    }

    test('no code in plain text', () {
      expect(findJoinCode('hello there my friend'), isNull);
      expect(findJoinCode(''), isNull);
    });

    test('pretty code leaves odd lengths alone', () {
      expect(prettyCode('ABC'), 'ABC');
      expect(prettyCode(''), '');
    });
  });

  group('names and text', () {
    for (final (raw, want) in [
      ('Rahul', 'Rahul'),
      ('  Rahul  ', 'Rahul'),
      ('Rahul   Kumar', 'Rahul Kumar'),
      ('', ''),
      ('   ', ''),
      ('x' * 40, 'x' * maxNameLength),
    ]) {
      test('cleanName "$raw"', () => expect(cleanName(raw), want));
    }
    test('cleanText cuts long notes', () {
      expect(cleanText('a' * 300, maxNoteLength).length, maxNoteLength);
      expect(cleanText('  hi  ', 10), 'hi');
    });
  });

  group('LedgerLog json', () {
    for (var seed = 0; seed < 60; seed++) {
      test('round trip $seed', () {
        final r = Random(seed + 77);
        final entries = [
          for (var i = 0; i < r.nextInt(20); i++) randomEntry(r, i)
        ];
        final log = LedgerLog(
          id: 'L$seed',
          nameA: 'A$seed',
          nameB: 'B$seed',
          code: newJoinCode(r),
          created: 123,
          members: {'u1': Side.a, 'u2': Side.b, if (r.nextBool()) 'u3': Side.b},
          entries: entries..sort(compareEntries),
          approvals: {
            if (r.nextBool())
              Side.a: Approval(sig: fingerprint(entries), net: 5, at: 9),
          },
          settledAt: r.nextBool() ? 999 : null,
        );
        final back = LedgerLog.fromJson(log.id, log.toJson())!;
        expect(back.nameA, log.nameA);
        expect(back.nameB, log.nameB);
        expect(back.code, log.code);
        expect(back.created, 123);
        expect(back.members, log.members);
        expect([for (final x in back.entries) x.id],
            [for (final x in log.entries) x.id]);
        expect(back.sig, log.sig);
        expect(back.settledAt, log.settledAt);
        expect(back.approvedBy(Side.a), log.approvedBy(Side.a));
        expect(back.balanceFor(Side.a).net, log.balanceFor(Side.a).net);
      });
    }

    test('missing meta is not a log', () {
      expect(LedgerLog.fromJson('x', null), isNull);
      expect(LedgerLog.fromJson('x', {'entries': {}}), isNull);
    });

    test('bad entries and members are skipped', () {
      final log = LedgerLog.fromJson('x', {
        'meta': {'a': 'A', 'b': 'B'},
        'members': {
          'u1': {'s': 'a'},
          'u2': {'s': 'z'},
          'u3': 'b'
        },
        'entries': {
          'e1': {'amt': 100, 'by': 'a', 'date': 1},
          'e2': {'amt': 'x'},
          'e3': 5,
        },
        'ok': {
          'a': {'sig': 's'},
          'c': {'sig': 's'},
          'b': 'bad'
        },
      })!;
      expect(log.members, {'u1': Side.a, 'u3': Side.b});
      expect(log.entries.single.id, 'e1');
      expect(log.approvals.keys, [Side.a]);
      expect(log.code, '');
    });

    test('nameOf and devicesOf', () {
      final log = LedgerLog(
          id: 'x',
          nameA: 'A',
          nameB: 'B',
          code: '',
          members: const {'1': Side.a, '2': Side.b, '3': Side.b});
      expect(log.nameOf(Side.a), 'A');
      expect(log.nameOf(Side.b), 'B');
      expect(log.devicesOf(Side.a), 1);
      expect(log.devicesOf(Side.b), 2);
    });
  });

  group('planned writes', () {
    final log = logOf([e('1', 500, Side.a)]);

    test('create writes the log, the member and the code together', () {
      final w = LedgerWrites.create(
          id: 'L', code: 'ABCD2345', uid: 'u', myName: 'R', friendName: 'A');
      expect(w.keys, [
        'ledger/L/meta',
        'ledger/L/members/u',
        'ledgerCodes/ABCD2345',
        'ledgerUsers/u/ledgers/L'
      ]);
      expect(w['ledgerUsers/u/ledgers/L'], 'a');
      expect((w['ledger/L/meta'] as Map)['created'], serverTime);
    });

    test('join carries the code for the rules to check', () {
      final w = LedgerWrites.join(
          info: const CodeInfo(id: 'L', nameA: 'R', nameB: 'A'),
          code: 'ABCD2345',
          uid: 'u2',
          side: Side.b);
      expect(w, {
        'ledger/L/members/u2': {'s': 'b', 'c': 'ABCD2345'},
        'ledgerUsers/u2/ledgers/L': 'b',
      });
    });

    test('new entry stamps server time and creator', () {
      final w =
          LedgerWrites.saveEntry(log, e('2', 7, Side.b), Side.b, isNew: true);
      final v = w['ledger/L/entries/2'] as Map;
      expect(v['at'], serverTime);
      expect(v['cs'], 'b');
      expect(v.containsKey('ea'), isFalse);
      expect(w.containsKey('ledger/L/ok'), isFalse);
    });

    test('edit stamps edit time and editor, keeps creator', () {
      final old = LedgerEntry(
          id: '1',
          amount: 5,
          by: Side.a,
          date: DateTime(2026),
          createdAt: 42,
          createdBy: Side.a);
      final w = LedgerWrites.saveEntry(log, old, Side.b, isNew: false);
      final v = w['ledger/L/entries/1'] as Map;
      expect(v['at'], 42);
      expect(v['cs'], 'a');
      expect(v['ea'], serverTime);
      expect(v['es'], 'b');
    });

    test('changes clear confirmations', () {
      final asked = logOf([
        e('1', 500, Side.a)
      ], approvals: {
        Side.a: Approval(sig: fingerprint([e('1', 500, Side.a)]), net: 500)
      });
      expect(
          LedgerWrites.saveEntry(asked, e('2', 1, Side.a), Side.a, isNew: true),
          containsPair('ledger/L/ok', null));
      expect(LedgerWrites.deleteEntry(asked, '1'),
          containsPair('ledger/L/ok', null));
    });

    test('first confirmation does not clear', () {
      final w = LedgerWrites.approve(log, Side.a);
      expect(w.keys, ['ledger/L/ok/a']);
      expect((w['ledger/L/ok/a'] as Map)['sig'], log.sig);
      expect((w['ledger/L/ok/a'] as Map)['net'], 500);
    });

    test('second confirmation clears, drops the code, lists for cleanup', () {
      final asked = logOf([e('1', 500, Side.a)],
          approvals: {Side.a: Approval(sig: log.sig, net: 500)});
      final w = LedgerWrites.approve(asked, Side.b);
      expect(w['ledger/L/done'], serverTime);
      expect(w['ledgerGc/L'], {'t': serverTime});
      expect(w.containsKey('ledgerCodes/ABCD2345'), isTrue);
      expect(w['ledgerCodes/ABCD2345'], isNull);
      expect(w['ledger/L/meta/code'], isNull);
    });

    test('reopen makes a new code and leaves the cleanup list', () {
      final w = LedgerWrites.reopen(logOf([], settledAt: 1), 'WXYZ6789');
      expect(w['ledger/L/done'], isNull);
      expect(w['ledgerGc/L'], isNull);
      expect(w['ledger/L/meta/code'], 'WXYZ6789');
      expect((w['ledgerCodes/WXYZ6789'] as Map)['id'], 'L');
    });

    test('reset swaps the code only', () {
      final w = LedgerWrites.resetCode(log, 'WXYZ6789');
      expect(w.keys.toSet(), {
        'ledgerCodes/ABCD2345',
        'ledgerCodes/WXYZ6789',
        'ledger/L/meta/code'
      });
    });

    test('delete removes log, cleanup entry and code', () {
      expect(LedgerWrites.delete('L', 'ABCD2345'),
          {'ledger/L': null, 'ledgerGc/L': null, 'ledgerCodes/ABCD2345': null});
      expect(
          LedgerWrites.delete('L', ''), {'ledger/L': null, 'ledgerGc/L': null});
    });

    test('leave and switch touch only this phone', () {
      expect(LedgerWrites.leave('L', 'u'),
          {'ledger/L/members/u': null, 'ledgerUsers/u/ledgers/L': null});
      expect(LedgerWrites.switchSide('L', 'u', Side.a),
          {'ledger/L/members/u/s': 'a', 'ledgerUsers/u/ledgers/L': 'a'});
    });
  });
}
