import 'package:flutter/material.dart';

/// Brand: emerald with a warm amber accent.
const kBrand = Color(0xFF0E9F7E);
const kAccent = Color(0xFFFFB547);

/// Colours with a fixed meaning (right, wrong, streak) in both themes.
@immutable
class QuizColors extends ThemeExtension<QuizColors> {
  const QuizColors({
    required this.correct,
    required this.onCorrect,
    required this.correctSoft,
    required this.wrong,
    required this.onWrong,
    required this.wrongSoft,
    required this.streak,
    required this.marked,
    required this.heat,
  });

  final Color correct;
  final Color onCorrect;
  final Color correctSoft;
  final Color wrong;
  final Color onWrong;
  final Color wrongSoft;
  final Color streak;
  final Color marked;

  /// Heatmap levels 0 (none) to 4.
  final List<Color> heat;

  static const light = QuizColors(
    correct: Color(0xFF15965A),
    onCorrect: Colors.white,
    correctSoft: Color(0xFFDDF5E8),
    wrong: Color(0xFFD93A3F),
    onWrong: Colors.white,
    wrongSoft: Color(0xFFFCE3E3),
    streak: Color(0xFFFF7A1A),
    marked: Color(0xFF7C4DFF),
    heat: [
      Color(0xFFE6EBE9),
      Color(0xFFB4E8D6),
      Color(0xFF6FD0AE),
      Color(0xFF26B087),
      Color(0xFF0B7A5C),
    ],
  );

  static const dark = QuizColors(
    correct: Color(0xFF3CCB86),
    onCorrect: Color(0xFF00210F),
    correctSoft: Color(0xFF173A2A),
    wrong: Color(0xFFFF6B6E),
    onWrong: Color(0xFF3B0003),
    wrongSoft: Color(0xFF45201F),
    streak: Color(0xFFFF9A4D),
    marked: Color(0xFFB39DFF),
    heat: [
      Color(0xFF2A302E),
      Color(0xFF1E5243),
      Color(0xFF237A60),
      Color(0xFF2FA47F),
      Color(0xFF5FE0B4),
    ],
  );

  @override
  QuizColors copyWith() => this;

  @override
  QuizColors lerp(ThemeExtension<QuizColors>? other, double t) =>
      t < 0.5 ? this : (other as QuizColors? ?? this);
}

extension QuizTheme on BuildContext {
  QuizColors get quiz =>
      Theme.of(this).extension<QuizColors>() ?? QuizColors.light;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}

ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: kBrand,
    brightness: brightness,
  ).copyWith(
    tertiary: kAccent,
    onTertiary: const Color(0xFF3D2600),
    tertiaryContainer: dark ? const Color(0xFF5A3D00) : const Color(0xFFFFE3B5),
    onTertiaryContainer: dark ? const Color(0xFFFFDDA6) : const Color(0xFF2B1A00),
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    extensions: [dark ? QuizColors.dark : QuizColors.light],
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: shape,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: shape,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}

/// Icon for each subject.
IconData subjectIcon(String subject) => switch (subject) {
      'gk' => Icons.public,
      'history' => Icons.account_balance,
      'polity' => Icons.gavel,
      'geography' => Icons.terrain,
      'economy' => Icons.currency_rupee,
      'science' => Icons.science,
      'current_affairs' => Icons.newspaper,
      'maths' => Icons.calculate,
      'reasoning' => Icons.psychology,
      'english' => Icons.translate,
      'computer' => Icons.computer,
      _ => Icons.quiz,
    };

/// Accent colour for each subject tile.
Color subjectColor(String subject) => switch (subject) {
      'gk' => const Color(0xFF0E9F7E),
      'history' => const Color(0xFFB7791F),
      'polity' => const Color(0xFF5B5BD6),
      'geography' => const Color(0xFF2F9E44),
      'economy' => const Color(0xFFE8590C),
      'science' => const Color(0xFF1C7ED6),
      'current_affairs' => const Color(0xFFD6336C),
      'maths' => const Color(0xFF7048E8),
      'reasoning' => const Color(0xFF0C8599),
      'english' => const Color(0xFFC2255C),
      'computer' => const Color(0xFF495057),
      _ => kBrand,
    };

/// Icon for each exam.
IconData examIcon(String exam) => switch (exam) {
      'ssc' => Icons.badge,
      'railway' => Icons.train,
      'banking' => Icons.account_balance_wallet,
      'upsc' => Icons.workspace_premium,
      'state_psc' => Icons.location_city,
      'defence' => Icons.shield,
      'teaching' => Icons.school,
      _ => Icons.assignment,
    };
