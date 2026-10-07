import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

/// Brand: deep indigo with a saffron accent for "new" and the bell.
const brandIndigo = Color(0xFF283593);
const brandSaffron = Color(0xFFF59E0B);

/// Colours outside the Material scheme, tuned per brightness.
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.urgent,
    required this.onUrgent,
    required this.success,
    required this.onSuccess,
    required this.accent,
    required this.onAccent,
  });

  final Color urgent;
  final Color onUrgent;
  final Color success;
  final Color onSuccess;
  final Color accent;
  final Color onAccent;

  static const light = StatusColors(
    urgent: Color(0xFFFDE2E1),
    onUrgent: Color(0xFFB3261E),
    success: Color(0xFFDDF4E4),
    onSuccess: Color(0xFF1B6B3A),
    accent: Color(0xFFFFEDC7),
    onAccent: Color(0xFF7A4A00),
  );

  static const dark = StatusColors(
    urgent: Color(0xFF5C1D1A),
    onUrgent: Color(0xFFFFB4AB),
    success: Color(0xFF173D26),
    onSuccess: Color(0xFF9EDBB0),
    accent: Color(0xFF4A3410),
    onAccent: Color(0xFFFFD58A),
  );

  static StatusColors of(BuildContext context) =>
      Theme.of(context).extension<StatusColors>() ?? light;

  @override
  StatusColors copyWith() => this;

  @override
  StatusColors lerp(StatusColors? other, double t) => t < 0.5 ? this : (other ?? this);
}

ThemeData vacancyTheme(Brightness brightness) {
  final base = buildTheme(brandIndigo, brightness);
  final scheme = base.colorScheme;
  final dark = brightness == Brightness.dark;
  return base.copyWith(
    scaffoldBackgroundColor: dark ? scheme.surface : const Color(0xFFF7F7FB),
    extensions: [dark ? StatusColors.dark : StatusColors.light],
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: dark ? scheme.surface : const Color(0xFFF7F7FB),
      surfaceTintColor: Colors.transparent,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: dark ? scheme.surfaceContainerHigh : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: dark ? 0.4 : 0.6)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 12),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
    tabBarTheme: base.tabBarTheme.copyWith(
      tabAlignment: TabAlignment.start,
      dividerColor: Colors.transparent,
    ),
  );
}
