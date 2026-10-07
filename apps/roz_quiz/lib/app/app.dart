import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/bi.dart';
import '../data/user_store.dart';
import '../ui/home_shell.dart';
import '../ui/onboarding_screen.dart';
import '../ui/scope.dart';
import '../ui/theme.dart';
import 'controller.dart';

/// Largest text scale the layouts are built for.
const kMaxTextScale = 1.3;

class RozQuizApp extends StatelessWidget {
  const RozQuizApp({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final st = controller.settings;
          return MaterialApp(
            title: 'Roz Quiz',
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(Brightness.light),
            darkTheme: buildAppTheme(Brightness.dark),
            themeMode: switch (st.theme) {
              AppTheme.system => ThemeMode.system,
              AppTheme.light => ThemeMode.light,
              AppTheme.dark => ThemeMode.dark,
            },
            locale: Locale(st.lang == Lang.hi ? 'hi' : 'en', 'IN'),
            supportedLocales: const [Locale('en', 'IN'), Locale('hi', 'IN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              return MediaQuery(
                data: mq.copyWith(
                    textScaler: mq.textScaler.clamp(maxScaleFactor: kMaxTextScale)),
                child: child!,
              );
            },
            home: st.onboarded ? const HomeShell() : const OnboardingScreen(),
          );
        },
      ),
    );
  }
}
