import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_app/src/party/party.dart';
import 'package:video_player_app/src/party/party_widgets.dart';
import 'package:video_player_app/src/party/protocol.dart';
import 'package:video_player_app/src/player/play_item.dart';
import 'package:video_player_app/src/player/tool_sheets.dart';
import 'package:video_player_app/src/settings.dart';

/// Opens [sheet] from a button so Navigator.pop has somewhere to go.
Future<void> openSheet(WidgetTester tester, Widget sheet) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showModalBottomSheet<void>(
              context: context, isScrollControlled: true, builder: (_) => sheet),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('SheetTitle', () {
    testWidgets('shows text and optional trailing', (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: SheetTitle('Equalizer', trailing: Text('Reset')))));
      expect(find.text('Equalizer'), findsOneWidget);
      expect(find.text('Reset'), findsOneWidget);
    });
  });

  group('SleepTimerSheet', () {
    const labels = [
      'Off', 'End of this video', '10 minutes', '15 minutes', '30 minutes', '45 minutes',
      '60 minutes', '90 minutes', '120 minutes',
    ];
    final values = <Duration?>[
      null, Duration.zero,
      for (final m in [10, 15, 30, 45, 60, 90, 120]) Duration(minutes: m),
    ];

    testWidgets('lists every choice and marks Off when inactive', (tester) async {
      await openSheet(tester, SleepTimerSheet(active: null, onPick: (_) {}));
      for (final l in labels) {
        expect(find.text(l), findsOneWidget);
      }
      expect(find.byIcon(Icons.radio_button_checked_rounded), findsOneWidget);
      final checked = find.ancestor(
          of: find.byIcon(Icons.radio_button_checked_rounded), matching: find.byType(ListTile));
      expect(find.descendant(of: checked, matching: find.text('Off')), findsOneWidget);
    });

    for (var i = 0; i < labels.length; i++) {
      testWidgets('tapping "${labels[i]}" picks ${values[i]} and closes', (tester) async {
        Object? picked = 'nothing';
        await openSheet(tester, SleepTimerSheet(active: null, onPick: (d) => picked = d));
        await tester.tap(find.text(labels[i]));
        await tester.pumpAndSettle();
        expect(picked, values[i]);
        expect(find.text('Sleep timer'), findsNothing);
      });
    }

    testWidgets('marks the active 30 minutes choice only', (tester) async {
      await openSheet(
          tester, SleepTimerSheet(active: const Duration(minutes: 30), onPick: (_) {}));
      final checked = find.ancestor(
          of: find.byIcon(Icons.radio_button_checked_rounded), matching: find.byType(ListTile));
      expect(checked, findsOneWidget);
      expect(find.descendant(of: checked, matching: find.text('30 minutes')), findsOneWidget);
    });
  });

  group('BookmarksSheet', () {
    final item = PlayItem.fromUrl('https://x.com/movie.mp4');

    testWidgets('empty, add, jump and remove', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final s = await Settings.open();
      Duration? jumped;
      await openSheet(
          tester,
          BookmarksSheet(
              settings: s,
              item: item,
              position: const Duration(minutes: 1, seconds: 5),
              onJump: (d) => jumped = d));
      expect(find.text('No bookmarks yet'), findsOneWidget);
      expect(find.text('Add 1:05'), findsOneWidget);

      await tester.tap(find.text('Add 1:05'));
      await tester.pump();
      expect(find.text('No bookmarks yet'), findsNothing);
      expect(find.text('1:05'), findsOneWidget);
      expect(s.bookmarksFor(item.key), [const Duration(seconds: 65)]);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      expect(s.bookmarksFor(item.key), isEmpty);
      expect(find.text('No bookmarks yet'), findsOneWidget);

      s.addBookmark(item.key, const Duration(hours: 1, minutes: 2, seconds: 3));
      await tester.tap(find.text('Add 1:05'));
      await tester.pump();
      expect(find.text('1:02:03'), findsOneWidget);
      await tester.tap(find.text('1:02:03'));
      await tester.pumpAndSettle();
      expect(jumped, const Duration(hours: 1, minutes: 2, seconds: 3));
      expect(find.text('Bookmarks'), findsNothing);
    });

    testWidgets('lists saved marks in time order', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final s = await Settings.open();
      for (final sec in [300, 10, 75]) {
        s.addBookmark(item.key, Duration(seconds: sec));
      }
      await openSheet(tester,
          BookmarksSheet(settings: s, item: item, position: Duration.zero, onJump: (_) {}));
      final texts = tester
          .widgetList<Text>(find.descendant(
              of: find.byType(ListTile), matching: find.byType(Text)))
          .map((t) => t.data)
          .toList();
      expect(texts, ['0:10', '1:15', '5:00']);
    });
  });

  group('DelayRow', () {
    final cases = <(double, String, double, double)>[
      // value, label, after minus, after plus
      (0, '+0.0 s', -0.1, 0.1),
      (0.5, '+0.5 s', 0.4, 0.6),
      (-0.3, '-0.3 s', -0.4, -0.2),
      (2.0, '+2.0 s', 1.9, 2.1),
      (-0.1, '-0.1 s', -0.2, 0.0),
      (0.1, '+0.1 s', 0.0, 0.2),
    ];
    for (final (v, label, minus, plus) in cases) {
      testWidgets('value $v shows "$label", steps to $minus / $plus', (tester) async {
        final got = <double>[];
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: DelayRow(label: 'Audio delay', value: v, onChanged: got.add))));
        expect(find.text('Audio delay'), findsOneWidget);
        expect(find.text(label), findsOneWidget);
        await tester.tap(find.byIcon(Icons.remove_rounded));
        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.tap(find.text(label));
        expect(got, [minus, plus, 0]);
      });
    }
  });

  group('PartyOverlay', () {
    testWidgets('shows chat lines and floating reactions, then clears', (tester) async {
      final party = PartyGuest('Me', const JoinCode(hosts: ['10.0.0.1'], port: 1, name: 'x'));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: PartyOverlay(party: party, bottom: 80))));
      party.sendChat('hello');
      party.sendReaction('🎉');
      await tester.pump();
      expect(find.text('🎉'), findsOneWidget);
      expect(find.textContaining('hello', findRichText: true), findsOneWidget);
      expect(find.textContaining('Me', findRichText: true), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('🎉'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      expect(find.textContaining('hello', findRichText: true), findsNothing);
      party.dispose();
    });

    testWidgets('keeps only the three newest chat lines', (tester) async {
      final party = PartyGuest('Me', const JoinCode(hosts: ['10.0.0.1'], port: 1, name: 'x'));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: PartyOverlay(party: party, bottom: 80))));
      for (final t in ['one', 'two', 'three', 'four']) {
        party.sendChat(t);
      }
      await tester.pump();
      expect(find.textContaining('one', findRichText: true), findsNothing);
      for (final t in ['two', 'three', 'four']) {
        expect(find.textContaining(t, findRichText: true), findsOneWidget);
      }
      await tester.pump(const Duration(seconds: 7));
      party.dispose();
    });
  });
}
