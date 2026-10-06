import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import 'settings.dart';
import 'ui/home_screen.dart';

const packageName = 'in.onlysoftware.multi_speaker';

const privacyPolicyUrl =
    'https://example.com/privacy'; // TODO: your hosted policy

class MultiSpeakerApp extends StatelessWidget {
  const MultiSpeakerApp({super.key, required this.settings});

  final Settings settings;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF6A1B9A);
    return MaterialApp(
      title: 'Multi Speaker',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(seed, Brightness.light),
      darkTheme: buildTheme(seed, Brightness.dark),
      home: HomeScreen(settings: settings),
    );
  }
}
