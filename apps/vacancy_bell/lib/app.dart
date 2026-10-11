import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/json_read.dart';
import 'data/settings.dart';
import 'l10n/strings.dart';
import 'state/app_controller.dart';
import 'ui/detail_screen.dart';
import 'ui/home_screen.dart';
import 'ui/onboarding.dart';
import 'ui/scope.dart';
import 'ui/theme.dart';

class VacancyBellApp extends StatelessWidget {
  const VacancyBellApp({super.key, required this.controller, this.navigatorKey});
  final AppController controller;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: ListenableBuilder(
        listenable: controller.settings,
        builder: (context, _) {
          final settings = controller.settings;
          final lang = settings.lang;
          return MaterialApp(
            navigatorKey: navigatorKey,
            title: stringsFor(lang)[L.appName]!,
            debugShowCheckedModeBanner: false,
            theme: vacancyTheme(Brightness.light),
            darkTheme: vacancyTheme(Brightness.dark),
            themeMode: switch (settings.theme) {
              ThemeChoice.system => ThemeMode.system,
              ThemeChoice.light => ThemeMode.light,
              ThemeChoice.dark => ThemeMode.dark,
            },
            locale: Locale(lang == AppLang.hi ? 'hi' : 'en', 'IN'),
            supportedLocales: const [Locale('en', 'IN'), Locale('hi', 'IN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: settings.onboarded ? const HomeShell() : const OnboardingFlow(),
          );
        },
      ),
    );
  }
}

/// Opens a post from a notification tap.
void openPostFromNotification(GlobalKey<NavigatorState> key, String? postId) {
  if (postId == null || postId.isEmpty) return;
  final nav = key.currentState;
  if (nav == null) return;
  nav.push(MaterialPageRoute(builder: (_) => DetailScreen(postId: postId)));
}
