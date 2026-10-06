import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audio/sfx.dart';
import 'game/store.dart';
import 'ui/home_screen.dart';

const packageName = 'in.onlysoftware.snakes_ladders';

const privacyPolicyUrl =
    'https://example.com/privacy'; // TODO: your hosted policy

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final store = await Store.open();
  runApp(SnakesApp(store: store, sfx: Sfx(store)));
  // Consent and ads start after the first frame so the app opens instantly.
  AdService.instance.init(AdConfig.fromEnvironment());
}

class SnakesApp extends StatelessWidget {
  const SnakesApp({super.key, required this.store, required this.sfx});

  final Store store;
  final Sfx sfx;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2E7D32);
    return MaterialApp(
      title: 'Snakes & Ladders',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(seed, Brightness.light),
      darkTheme: buildTheme(seed, Brightness.dark),
      // Game layouts are sized to the screen; cap very large system font
      // sizes so names and panels never overflow.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data:
              mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: 1.2)),
          child: child!,
        );
      },
      home: HomeScreen(store: store, sfx: sfx),
    );
  }
}
