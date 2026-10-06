import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audio/sfx.dart';
import 'game/store.dart';
import 'hub_screen.dart';
import 'ludo/sfx.dart';
import 'ludo/store.dart';
import 'ui/home_screen.dart';

/// The app's name everywhere it shows in the UI. The launcher label lives in
/// android/app/src/main/AndroidManifest.xml.
const appName = 'Ludo Party';

const packageName = 'in.onlysoftware.ludo_party';

const privacyPolicyUrl =
    'https://example.com/privacy'; // TODO: your hosted policy

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final store = await Store.open();
  final ludo = await LudoStore.open();
  runApp(PartyApp(
    store: store,
    sfx: Sfx(store),
    ludo: ludo,
    ludoSfx: LudoSfx(ludo),
  ));
  // Consent and ads start after the first frame so the app opens instantly.
  AdService.instance.init(AdConfig.fromEnvironment());
}

class PartyApp extends StatelessWidget {
  const PartyApp({
    super.key,
    required this.store,
    required this.sfx,
    required this.ludo,
    required this.ludoSfx,
  });

  /// Snakes & Ladders.
  final Store store;
  final Sfx sfx;
  final LudoStore ludo;
  final LudoSfx ludoSfx;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1565C0);
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(seed, Brightness.light),
      darkTheme: buildTheme(seed, Brightness.dark),
      builder: _capTextScale,
      home: HubScreen(store: store, sfx: sfx, ludo: ludo, ludoSfx: ludoSfx),
    );
  }
}

/// Game layouts are sized to the screen; cap very large system font sizes
/// so names and panels never overflow.
Widget _capTextScale(BuildContext context, Widget? child) {
  final mq = MediaQuery.of(context);
  return MediaQuery(
    data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: 1.2)),
    child: child!,
  );
}

/// Snakes & Ladders on its own, without the game picker (used by tests).
class SnakesApp extends StatelessWidget {
  const SnakesApp({super.key, required this.store, required this.sfx});

  final Store store;
  final Sfx sfx;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2E7D32);
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(seed, Brightness.light),
      darkTheme: buildTheme(seed, Brightness.dark),
      builder: _capTextScale,
      home: HomeScreen(store: store, sfx: sfx),
    );
  }
}
