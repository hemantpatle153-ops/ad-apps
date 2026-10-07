// Play Store screenshots. Run: flutter test screenshots/store_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snakes_ladders/audio/sfx.dart';
import 'package:snakes_ladders/game/board.dart';
import 'package:snakes_ladders/game/engine.dart' as sl;
import 'package:snakes_ladders/game/store.dart';
import 'package:snakes_ladders/ludo/engine.dart';
import 'package:snakes_ladders/ludo/match.dart';
import 'package:snakes_ladders/ludo/online/backend.dart';
import 'package:snakes_ladders/ludo/sfx.dart';
import 'package:snakes_ladders/ludo/store.dart';
import 'package:snakes_ladders/ludo/ui/game_screen.dart';
import 'package:snakes_ladders/ludo/ui/online_screen.dart';
import 'package:snakes_ladders/main.dart';
import 'package:snakes_ladders/ui/game_screen.dart';

import '../../../tool/screenshots/shot.dart';

/// Screens animate forever, so pumpAndSettle would never return.
Future<void> settle(WidgetTester tester, [int ms = 1200]) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

LudoEngine ludoMidGame() => LudoEngine(
      players: const [
        Player(name: 'You', color: 3, kind: PlayerKind.human),
        Player(name: 'Priya', color: 0, kind: PlayerKind.bot),
        Player(name: 'Arjun', color: 1, kind: PlayerKind.bot),
        Player(name: 'Meera', color: 2, kind: PlayerKind.bot),
      ],
      tokens: [
        [12, 30, Track.yard, 53],
        [5, 22, Track.yard, Track.yard],
        [40, 11, Track.home, Track.yard],
        [18, Track.yard, 29, 2],
      ],
      turns: 64,
      captures: [2, 1, 1, 0],
      sixes: [4, 3, 5, 3],
    );

Future<(Store, LudoStore)> openStores() async {
  SharedPreferences.setMockInitialValues({'sound': true, 'vibration': false});
  return (await Store.open(), await LudoStore.open());
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // No audio plugin in tests: answer its channels with nothing.
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final c in [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
    ]) {
      m.setMockMethodCallHandler(MethodChannel(c), (_) async => null);
    }
    await loadRealFonts();
  });

  testWidgets('hub', (tester) async {
    usePhone(tester);
    final (store, ludo) = await openStores();
    await ludo.save('g1', ludoMidGame());
    await tester.pumpWidget(PartyApp(
        store: store, sfx: Sfx(store), ludo: ludo, ludoSfx: LudoSfx(ludo)));
    await settle(tester);
    await shot(tester, '01_home');
  });

  testWidgets('ludo mid-game', (tester) async {
    usePhone(tester);
    final (store, ludo) = await openStores();
    await tester.pumpWidget(PartyApp(
        store: store, sfx: Sfx(store), ludo: ludo, ludoSfx: LudoSfx(ludo)));
    await settle(tester, 300);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute(
      builder: (_) => LudoGameScreen(
        engine: ludoMidGame(),
        store: ludo,
        sfx: LudoSfx(ludo),
        link: LocalLink(),
        me: 0,
      ),
    ));
    await settle(tester, 1500);
    await shot(tester, '02_ludo_game');
    await tester.pumpWidget(const SizedBox());
    await settle(tester, 300);
  });

  testWidgets('snakes and ladders mid-game', (tester) async {
    usePhone(tester);
    final (store, ludo) = await openStores();
    await tester.pumpWidget(PartyApp(
        store: store, sfx: Sfx(store), ludo: ludo, ludoSfx: LudoSfx(ludo)));
    await settle(tester, 300);
    final g = sl.GameEngine(
      board: BoardLayout.classic,
      players: const [
        sl.Player(name: 'You', color: 3, kind: sl.PlayerKind.human),
        sl.Player(name: 'Dadi', color: 0, kind: sl.PlayerKind.bot),
        sl.Player(name: 'Rohan', color: 1, kind: sl.PlayerKind.bot),
        sl.Player(name: 'Kavya', color: 2, kind: sl.PlayerKind.bot),
      ],
      positions: [64, 39, 82, 26],
      turns: 37,
      rolls: [10, 9, 9, 9],
      snakeBites: [1, 2, 0, 1],
      laddersClimbed: [2, 1, 3, 0],
    );
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute(
        builder: (_) => GameScreen(engine: g, store: store, sfx: Sfx(store))));
    await settle(tester, 1500);
    await shot(tester, '03_snakes_ladders_game');
    await tester.pumpWidget(const SizedBox());
    await settle(tester, 300);
  });

  testWidgets('online room lobby', (tester) async {
    usePhone(tester);
    final (store, ludo) = await openStores();
    ludo.playerName = 'Rahul';
    final server = MemoryServer();
    final host = MemoryBackend(server);
    late String code;
    await tester.runAsync(() async {
      await host.connect();
      code = await host.createRoom(
          name: 'Rahul', size: 4, rules: const GameRules());
      for (final name in ['Asha', 'Vikram']) {
        final b = MemoryBackend(server);
        await b.connect();
        await b.joinRoom(code, name);
      }
    });
    await tester.pumpWidget(PartyApp(
        store: store, sfx: Sfx(store), ludo: ludo, ludoSfx: LudoSfx(ludo)));
    await settle(tester, 300);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute(
      builder: (_) => LobbyScreen(
          store: ludo,
          sfx: LudoSfx(ludo),
          backend: host,
          code: code,
          mySeat: 0),
    ));
    await settle(tester, 1200);
    await shot(tester, '04_online_room');
    await tester.pumpWidget(const SizedBox());
    await settle(tester, 300);
  });
}
