import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_app/src/party/party.dart';
import 'package:video_player_app/src/party/party_widgets.dart';
import 'package:video_player_app/src/party/protocol.dart';
import 'package:video_player_app/src/settings.dart';

/// A guest that never connects; [hear] plays a message from someone else.
class _Party extends PartyGuest {
  _Party() : super('Me', const JoinCode(hosts: ['10.0.0.1'], port: 1, name: 'x'));

  void hear(String from, String text, {bool emoji = false}) =>
      received(PartyMessage(from: from, text: text, emoji: emoji));
}

void main() {
  group('mute', () {
    test('hides what a muted person says, past and future', () async {
      final p = _Party();
      final seen = <String>[];
      final sub = p.incoming.listen((m) => seen.add(m.text));
      p.hear('Troll', 'first');
      p.hear('Friend', 'hi');
      p.mute('Troll');
      expect(p.messages.map((m) => m.text), ['hi']);
      p.hear('Troll', 'again');
      p.hear('Troll', '🔥', emoji: true);
      p.hear('Friend', 'still here');
      await Future<void>.delayed(Duration.zero);
      expect(p.messages.map((m) => m.text), ['hi', 'still here']);
      expect(seen, ['first', 'hi', 'still here']);
      p.unmute('Troll');
      p.hear('Troll', 'sorry');
      expect(p.messages.last.text, 'sorry');
      await sub.cancel();
      p.dispose();
    });

    test("can't mute yourself, and a Wi-Fi party has nowhere to report", () {
      final p = _Party();
      p.mute('Me');
      expect(p.isMuted('Me'), isFalse);
      expect(p.canReport, isFalse);
      p.dispose();
    });
  });

  group('PartySheet', () {
    testWidgets('long-press a message to mute its sender', (tester) async {
      final p = _Party();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PartySheet(party: p))));
      p.hear('Troll', 'rude words');
      await tester.pump();
      expect(find.textContaining('rude words', findRichText: true), findsOneWidget);
      expect(find.textContaining('Be kind'), findsOneWidget);
      await tester.longPress(find.textContaining('rude words', findRichText: true));
      await tester.pumpAndSettle();
      expect(find.text('Report'), findsNothing); // Wi-Fi party
      await tester.tap(find.text('Mute this person'));
      await tester.pumpAndSettle();
      expect(find.textContaining('rude words', findRichText: true), findsNothing);
      expect(p.isMuted('Troll'), isTrue);
      p.dispose();
    });
  });

  group('online room name', () {
    Future<Settings> settings([Map<String, Object> v = const {}]) async {
      SharedPreferences.setMockInitialValues(v);
      return Settings.open();
    }

    Future<String?> ask(WidgetTester tester, Settings s, {String? type, bool cancel = false}) async {
      String? got = 'not asked';
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => got = await askOnlinePartyName(context, s),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      if (type != null) await tester.enterText(find.byType(TextField), type);
      if (find.byType(AlertDialog).evaluate().isNotEmpty) {
        await tester.tap(find.text(cancel ? 'Cancel' : 'OK'));
        await tester.pumpAndSettle();
      }
      return got;
    }

    testWidgets('asks once, never using the phone name, and remembers', (tester) async {
      final s = await settings();
      expect(await ask(tester, s, type: '  Rahul '), 'Rahul');
      expect(s.partyName, 'Rahul');
      expect(await ask(tester, s), 'Rahul'); // no dialog the second time
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('cancel or a blank name stops joining', (tester) async {
      final s = await settings();
      expect(await ask(tester, s, cancel: true), isNull);
      expect(await ask(tester, s, type: '   '), isNull);
      expect(s.partyName, '');
    });
  });
}
