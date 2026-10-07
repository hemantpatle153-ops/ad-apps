import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snakes_ladders/game/themes.dart';
import 'package:snakes_ladders/ludo/themes.dart';
import 'package:snakes_ladders/ludo/ui/kit.dart';
import 'package:snakes_ladders/ludo/ui/pieces.dart';
import 'package:snakes_ladders/ui/dice.dart';
import 'package:snakes_ladders/ui/widgets.dart';

Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: SizedBox(width: 320, child: child))));

void main() {
  group('timeAgo', () {
    final now = DateTime(2026, 10, 6, 12);
    final cases = <Duration, String>{
      Duration.zero: 'just now',
      const Duration(seconds: 59): 'just now',
      const Duration(minutes: 1): '1 min ago',
      const Duration(minutes: 59): '59 min ago',
      const Duration(hours: 1): '1 h ago',
      const Duration(hours: 23, minutes: 59): '23 h ago',
      const Duration(hours: 24): 'yesterday',
      const Duration(hours: 47): 'yesterday',
      const Duration(days: 2): '2 days ago',
      const Duration(days: 30): '30 days ago',
      const Duration(days: 400): '400 days ago',
    };
    cases.forEach((ago, label) {
      test('${ago.inMinutes} minutes ago reads "$label"', () {
        expect(timeAgo(now.subtract(ago), now), label);
      });
    });
    test('a time in the future reads as just now', () {
      expect(timeAgo(now.add(const Duration(hours: 2)), now), 'just now');
    });
  });

  testWidgets('BigButton shows its labels and reacts to a tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(wrap(BigButton(
        color: Colors.green,
        icon: Icons.casino,
        label: 'Play vs Computer',
        sub: 'Beat the bot',
        onTap: () => taps++)));
    expect(find.text('Play vs Computer'), findsOneWidget);
    expect(find.text('Beat the bot'), findsOneWidget);
    await tester.tap(find.text('Play vs Computer'));
    expect(taps, 1);
  });

  for (final theme in BoardTheme.all) {
    testWidgets('Panel and SectionTitle render in ${theme.name}',
        (tester) async {
      await tester.pumpWidget(wrap(Column(children: [
        const SectionTitle('Stats'),
        Panel(theme: theme, child: const Text('inside')),
      ])));
      expect(find.text('Stats'), findsOneWidget);
      final style = DefaultTextStyle.of(tester.element(find.text('inside')));
      expect(style.style.color, theme.onPanel);
    });
  }

  testWidgets('ChunkyButton is greyed out and inert without a handler',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(wrap(Column(children: [
      ChunkyButton(
          label: 'Go', icon: Icons.play_arrow, onPressed: () => taps++),
      const ChunkyButton(label: 'Wait', onPressed: null),
    ])));
    await tester.tap(find.text('Go'));
    await tester.tap(find.text('Wait'));
    expect(taps, 1);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('ChoiceTile reports taps and shows its child', (tester) async {
    var picked = -1;
    await tester.pumpWidget(wrap(Row(children: [
      for (var i = 0; i < 3; i++)
        ChoiceTile(
            selected: i == 1,
            color: Colors.red,
            onTap: () => picked = i,
            child: Text('$i')),
    ])));
    await tester.tap(find.text('2'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(picked, 2);
  });

  for (final theme in LudoTheme.all) {
    testWidgets('LudoPanel, heading and piece icons in ${theme.name}',
        (tester) async {
      await tester.pumpWidget(wrap(Column(children: [
        const LudoHeading('Players'),
        LudoPanel(
            theme: theme,
            child: Row(children: [
              for (final c in theme.colors) PieceIcon(color: c, size: 28),
            ])),
      ])));
      expect(find.text('Players'), findsOneWidget);
      expect(find.byType(PieceIcon), findsNWidgets(4));
      expect(tester.getSize(find.byType(PieceIcon).first), const Size(28, 28));
    });
  }

  for (var face = 1; face <= 6; face++) {
    testWidgets('die showing $face can be tapped when enabled', (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(DiceView(
          value: face, color: Colors.red, enabled: true, onTap: () => taps++)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byType(DiceView));
      expect(taps, 1);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
