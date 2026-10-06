import 'package:flutter/material.dart';

import 'library/private_vault.dart';
import 'screens/home_screen.dart';
import 'settings.dart';

const packageName = 'in.onlysoftware.video_player';

const privacyPolicyUrl =
    'https://example.com/privacy'; // TODO: your hosted policy

const _accent = Color(0xFFFF7A1A);

ThemeData _theme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: _accent,
    brightness: b,
    primary: _accent,
    onPrimary: Colors.white,
    surface: dark ? const Color(0xFF0F0F15) : const Color(0xFFFAF8F6),
    surfaceContainerHighest: dark ? const Color(0xFF262633) : const Color(0xFFEDE7E2),
    surfaceContainerHigh: dark ? const Color(0xFF1E1E28) : const Color(0xFFF2EDE9),
    surfaceContainer: dark ? const Color(0xFF181821) : const Color(0xFFF5F1EE),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
          fontSize: 22, fontWeight: FontWeight.w700, color: scheme.onSurface),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: _accent.withValues(alpha: 0.18),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? _accent : scheme.onSurfaceVariant)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

class VideoPlayerApp extends StatefulWidget {
  const VideoPlayerApp({super.key, required this.settings});

  final Settings settings;

  @override
  State<VideoPlayerApp> createState() => _VideoPlayerAppState();
}

class _VideoPlayerAppState extends State<VideoPlayerApp> {
  late final vault = PrivateVault(widget.settings);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) => MaterialApp(
        title: 'Video Player',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: widget.settings.themeMode,
        home: HomeScreen(settings: widget.settings, vault: vault),
      ),
    );
  }
}
