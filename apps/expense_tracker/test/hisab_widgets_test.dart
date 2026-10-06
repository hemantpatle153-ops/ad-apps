import 'package:expense_tracker/data.dart';
import 'package:expense_tracker/hisab/hisab_home.dart';
import 'package:expense_tracker/hisab/hisab_screen.dart';
import 'package:expense_tracker/hisab/model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/hisab_world.dart';

Future<Settings> rupees() async {
  SharedPreferences.setMockInitialValues({'currency': '₹'});
  return Settings(await SharedPreferences.getInstance());
}

void bigScreen(WidgetTester t) {
  t.view.physicalSize = const Size(900, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> pumpScreen(WidgetTester t, Phone p, String id, Settings s) async {
  bigScreen(t);
  await t.pumpWidget(
      MaterialApp(home: HisabScreen(service: p.service, settings: s, id: id)));
  await t.pumpAndSettle();
}

Future<void> pumpHome(WidgetTester t, Phone p, Settings s) async {
  bigScreen(t);
  await t.pumpWidget(MaterialApp(
      home: Scaffold(body: HisabHome(service: p.service, settings: s))));
  await t.pumpAndSettle();
}

String resultText(WidgetTester t) =>
    t.widget<Text>(find.byKey(const Key('result-line'))).data!;

void main() {
  testWidgets('empty tab explains and offers start and join', (t) async {
    final s = await rupees();
    final w = await World.create();
    final p = await w.phone('me');
    await pumpHome(t, p, s);
    expect(find.text('Hisab with friends'), findsOneWidget);
    expect(find.byKey(const Key('start-hisab')), findsOneWidget);
    expect(find.byKey(const Key('join-hisab')), findsOneWidget);
  });

  testWidgets('start a hisab, then the code is shown to share', (t) async {
    final s = await rupees();
    final w = await World.create();
    final p = await w.phone('me');
    await pumpHome(t, p, s);
    await t.tap(find.byKey(const Key('start-hisab')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('create-me')), 'Rahul');
    await t.enterText(find.byKey(const Key('create-friend')), 'Amit');
    await t.tap(find.text('Create hisab'));
    await t.pumpAndSettle();
    final local = p.store.all().single;
    final code = (await p.log(local.id)).code;
    expect(find.text('Hisab code'), findsOneWidget);
    expect(find.text(prettyCode(code)), findsOneWidget);
    expect(find.text('Rahul: 1 phone'), findsOneWidget);
    expect(find.text('Amit: 0 phones'), findsOneWidget);
  });

  testWidgets('create needs both names', (t) async {
    final s = await rupees();
    final w = await World.create();
    final p = await w.phone('me');
    await pumpHome(t, p, s);
    await t.tap(find.byKey(const Key('start-hisab')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('create-me')), 'Rahul');
    await t.tap(find.text('Create hisab'));
    await t.pumpAndSettle();
    expect(find.text('Enter both names'), findsOneWidget);
    expect(p.store.all(), isEmpty);
  });

  testWidgets('join with a code and pick who you are', (t) async {
    final s = await rupees();
    final w = await World.create();
    final pa = await w.phone('uid-Rahul');
    final local = await pa.service.create('Rahul', 'Amit');
    final code = (await pa.log(local.id)).code;
    final pb = await w.phone('uid-Amit');
    await pumpHome(t, pb, s);
    await t.tap(find.byKey(const Key('join-hisab')));
    await t.pumpAndSettle();
    await t.enterText(
        find.byKey(const Key('join-code')), prettyCode(code).toLowerCase());
    await t.tap(find.text('Find hisab'));
    await t.pumpAndSettle();
    expect(find.text('Hisab between Rahul and Amit'), findsOneWidget);
    expect(find.text('Join as Amit'), findsOneWidget);
    await t.tap(find.text('Join as Amit'));
    await t.pumpAndSettle();
    expect(pb.side(local.id), Side.b);
    // Opened the log from Amit's side.
    expect(find.text('Rahul'), findsWidgets);
    expect(resultText(t), 'All clear');
  });

  testWidgets('wrong code shows a message', (t) async {
    final s = await rupees();
    final w = await World.create();
    final p = await w.phone('me');
    await pumpHome(t, p, s);
    await t.tap(find.byKey(const Key('join-hisab')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('join-code')), 'ABCD2345');
    await t.tap(find.text('Find hisab'));
    await t.pumpAndSettle();
    expect(find.textContaining('No hisab with that code'), findsOneWidget);
  });

  testWidgets('both phones show the result from their own side', (t) async {
    final s = await rupees();
    final w = await World.create();
    final (pa, pb, id, _) = await w.pair();
    await add(pa, id, 50000, iGave: true, tag: 'Loan');
    await add(pb, id, 20000, iGave: true, tag: 'Food');
    await pumpScreen(t, pa, id, s);
    expect(resultText(t), 'Amit will give you ₹300');
    expect(find.text('Amit will give me'), findsOneWidget);
    expect(find.text('₹500'), findsOneWidget);
    expect(find.text('− ₹200'), findsOneWidget);
    expect(find.text('Amit gives Rahul'), findsOneWidget);
    await pumpScreen(t, pb, id, s);
    expect(resultText(t), 'You will give Rahul ₹300');
    expect(find.text('Amit gives Rahul'), findsOneWidget);
  });

  testWidgets('add an entry with the I gave button', (t) async {
    final s = await rupees();
    final w = await World.create();
    final (pa, pb, id, _) = await w.pair();
    await pumpScreen(t, pa, id, s);
    await t.tap(find.byKey(const Key('add-i-gave')));
    await t.pumpAndSettle();
    expect(find.text('Amit will give this back to you'), findsOneWidget);
    await t.enterText(find.byKey(const Key('entry-amount')), '250');
    await t.tap(find.widgetWithText(ChoiceChip, 'Food'));
    await t.enterText(find.byKey(const Key('entry-note')), 'Biryani');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(resultText(t), 'Amit will give you ₹250');
    expect(find.text('Biryani'), findsOneWidget);
    final e = (await pb.log(id)).entries.single;
    expect(e.amount, 25000);
    expect(e.tag, 'Food');
    expect(e.by, Side.a);
  });

  testWidgets('add with the friend gave me button', (t) async {
    final s = await rupees();
    final w = await World.create();
    final (pa, _, id, _) = await w.pair();
    await pumpScreen(t, pa, id, s);
    await t.tap(find.byKey(const Key('add-they-gave')));
    await t.pumpAndSettle();
    expect(find.text('You will give this back to Amit'), findsOneWidget);
    await t.enterText(find.byKey(const Key('entry-amount')), '99.50');
    await t.enterText(find.byKey(const Key('entry-tag')), 'Cricket kit');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(resultText(t), 'You will give Amit ₹99.50');
    expect((await pa.log(id)).entries.single.tag, 'Cricket kit');
  });

  testWidgets('bad amount is not saved', (t) async {
    final s = await rupees();
    final w = await World.create();
    final (pa, _, id, _) = await w.pair();
    await pumpScreen(t, pa, id, s);
    await t.tap(find.byKey(const Key('add-i-gave')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('entry-amount')), 'abc');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(find.textContaining('Enter an amount'), findsOneWidget);
    expect((await pa.log(id)).entries, isEmpty);
  });

  testWidgets('edited entries show who edited', (t) async {
    final s = await rupees();
    final w = await World.create();
    final (pa, pb, id, _) = await w.pair();
    await add(pa, id, 1000, iGave: true, tag: 'Trip');
    final lb = await pb.log(id);
    await pb.service.saveEntry(
        lb, Side.b, lb.entries.single.copyWith(amount: 1500),
        isNew: false);
    await pumpScreen(t, pa, id, s);
    expect(find.textContaining('by Amit'), findsOneWidget);
    expect(find.textContaining('Edited'), findsOneWidget);
    expect(find.text('+₹15'), findsOneWidget);
  });

  testWidgets('the two lists filter entries', (t) async {
    final s = await rupees();
    final w = await World.create();
    final (pa, _, id, _) = await w.pair();
    await add(pa, id, 1000, iGave: true, note: 'Lent cash');
    await add(pa, id, 300, iGave: false, note: 'Paid my tea');
    await pumpScreen(t, pa, id, s);
    expect(find.text('Lent cash'), findsOneWidget);
    expect(find.text('Paid my tea'), findsOneWidget);
    await t.tap(find.text('Amit gives (1)'));
    await t.pumpAndSettle();
    expect(find.text('Lent cash'), findsOneWidget);
    expect(find.text('Paid my tea'), findsNothing);
    expect(find.text('Amit will give you ₹10 in total'), findsOneWidget);
    await t.tap(find.text('I give (1)'));
    await t.pumpAndSettle();
    expect(find.text('Lent cash'), findsNothing);
    expect(find.text('Paid my tea'), findsOneWidget);
    expect(find.text('You will give Amit ₹3 in total'), findsOneWidget);
  });

  testWidgets('clearing needs both: ask, confirm, then read-only', (t) async {
    final s = await rupees();
    final w = await World.create();
    final (pa, pb, id, _) = await w.pair();
    await add(pa, id, 50000, iGave: true);
    await pumpScreen(t, pa, id, s);
    await t.tap(find.byKey(const Key('ask-settle')));
    await t.pumpAndSettle();
    expect(find.textContaining('Waiting for Amit to confirm'), findsOneWidget);

    await pumpScreen(t, pb, id, s);
    expect(find.textContaining('Rahul confirmed the hisab'), findsOneWidget);
    await t.tap(find.byKey(const Key('confirm-settle')));
    await t.pumpAndSettle();
    expect(find.textContaining('Hisab cleared on'), findsOneWidget);
    expect(find.textContaining('in 14 days'), findsOneWidget);
    expect(find.byKey(const Key('add-i-gave')), findsNothing);
    expect(find.text('Reopen'), findsOneWidget);
    expect((await pa.log(id)).isSettled, isTrue);
  });

  testWidgets('reopen a cleared hisab', (t) async {
    final s = await rupees();
    final w = await World.create();
    final (pa, pb, id, _) = await w.pair();
    await add(pa, id, 500, iGave: true);
    await pa.service.approve(await pa.log(id), Side.a);
    await pb.service.approve(await pb.log(id), Side.b);
    await pumpScreen(t, pa, id, s);
    await t.tap(find.text('Reopen'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('add-i-gave')), findsOneWidget);
    expect((await pb.log(id)).isSettled, isFalse);
  });

  testWidgets('deleted from the cloud: phone copy stays readable', (t) async {
    final s = await rupees();
    final w = await World.create();
    final (pa, pb, id, _) = await w.pair();
    await add(pa, id, 500, iGave: true, note: 'Movie');
    await pa.service.approve(await pa.log(id), Side.a);
    await pb.service.approve(await pb.log(id), Side.b);
    await pumpScreen(t, pa, id, s); // saves the cleared copy
    w.db.advance(const Duration(days: 15));
    await pb.service.cleanUp();
    await t.pumpAndSettle();
    expect(find.textContaining('Saved on this phone only'), findsOneWidget);
    expect(find.text('Movie'), findsOneWidget);
    expect(resultText(t), 'Amit will give you ₹5');
  });

  testWidgets('home lists hisabs with totals and status', (t) async {
    final s = await rupees();
    final w = await World.create();
    final pa = await w.phone('uid-Rahul');
    final pb = await w.phone('uid-Amit');
    final pc = await w.phone('uid-Neha');
    final l1 = await pa.service.create('Rahul', 'Amit');
    final l2 = await pa.service.create('Rahul', 'Neha');
    for (final (p, l) in [(pb, l1), (pc, l2)]) {
      final code = (await pa.log(l.id)).code;
      await p.service.join(code, await p.service.lookup(code), Side.b);
    }
    await add(pa, l1.id, 70000, iGave: true);
    await add(pc, l2.id, 20000, iGave: true);
    await pc.service.approve(await pc.log(l2.id), Side.b);
    // The home list reads the phone's saved copies.
    for (final l in [l1, l2]) {
      await pa.store.remember(l.id, Side.a, await pa.log(l.id));
    }
    await pumpHome(t, pa, s);
    expect(find.text('Amit will give you ₹700'), findsOneWidget);
    expect(find.text('You will give Neha ₹200'), findsOneWidget);
    expect(find.text('Neha asks you to confirm'), findsOneWidget);
    expect(find.text('₹700'), findsOneWidget); // friends will give you
    expect(find.text('₹200'), findsOneWidget); // you will give friends
  });

  testWidgets('result card for every sign', (t) async {
    final s = await rupees();
    for (final (entries, a, b) in [
      (<HisabEntry>[], 'All clear', 'All clear'),
      (
        [HisabEntry(id: '1', amount: 100, by: Side.a, date: DateTime(2026))],
        'Amit will give you ₹1',
        'You will give Rahul ₹1'
      ),
      (
        [HisabEntry(id: '1', amount: 100, by: Side.b, date: DateTime(2026))],
        'You will give Amit ₹1',
        'Rahul will give you ₹1'
      ),
    ]) {
      final log = HisabLog(
          id: 'x', nameA: 'Rahul', nameB: 'Amit', code: '', entries: entries);
      for (final (side, want) in [(Side.a, a), (Side.b, b)]) {
        await t.pumpWidget(MaterialApp(
            home: Scaffold(body: ResultCard(log: log, me: side, settings: s))));
        expect(resultText(t), want);
      }
    }
  });
}
