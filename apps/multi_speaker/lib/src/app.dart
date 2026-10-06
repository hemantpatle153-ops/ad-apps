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
      theme: _theme(buildTheme(seed, Brightness.light)),
      darkTheme: _theme(buildTheme(seed, Brightness.dark)),
      home: HomeScreen(settings: settings),
    );
  }
}

/// Rounder cards and buttons, and a calmer app bar, on top of the shared theme.
ThemeData _theme(ThemeData base) {
  final scheme = base.colorScheme;
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    ),
    sliderTheme: const SliderThemeData(trackHeight: 6),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.primaryContainer,
    ),
  );
}
