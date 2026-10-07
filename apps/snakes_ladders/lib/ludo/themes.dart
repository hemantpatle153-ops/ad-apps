import 'package:flutter/material.dart';

const colorNames = ['Red', 'Green', 'Yellow', 'Blue'];

/// Everything that changes when the player switches the board theme.
class LudoTheme {
  const LudoTheme({
    required this.name,
    required this.background,
    required this.colors,
    required this.board,
    required this.track,
    required this.line,
    required this.frame,
    required this.star,
    required this.panel,
    required this.onPanel,
    required this.accent,
  });

  final String name;

  /// Screen background gradient, top to bottom.
  final List<Color> background;

  /// Red, green, yellow, blue for this theme.
  final List<Color> colors;

  /// Plain board surface and track squares.
  final Color board;
  final Color track;
  final Color line;
  final Color frame;
  final Color star;
  final Color panel;
  final Color onPanel;
  final Color accent;

  static const classic = LudoTheme(
    name: 'Classic',
    background: [Color(0xFF1565C0), Color(0xFF0D2B6B)],
    colors: [
      Color(0xFFE53935),
      Color(0xFF43A047),
      Color(0xFFFDD835),
      Color(0xFF1E88E5),
    ],
    board: Color(0xFFFFFFFF),
    track: Color(0xFFFFFFFF),
    line: Color(0xFF9E9E9E),
    frame: Color(0xFF263238),
    star: Color(0xFF616161),
    panel: Color(0xFFFFFFFF),
    onPanel: Color(0xFF1A237E),
    accent: Color(0xFFFFC107),
  );

  static const royal = LudoTheme(
    name: 'Royal',
    background: [Color(0xFF4A148C), Color(0xFF1A0033)],
    colors: [
      Color(0xFFD50000),
      Color(0xFF00C853),
      Color(0xFFFFD600),
      Color(0xFF2962FF),
    ],
    board: Color(0xFFFFF8E1),
    track: Color(0xFFFFFDF5),
    line: Color(0xFFB8860B),
    frame: Color(0xFFB8860B),
    star: Color(0xFFB8860B),
    panel: Color(0xFFFFF8E1),
    onPanel: Color(0xFF4A148C),
    accent: Color(0xFFFFD54F),
  );

  static const wood = LudoTheme(
    name: 'Wood',
    background: [Color(0xFF6D4C41), Color(0xFF3E2723)],
    colors: [
      Color(0xFFC62828),
      Color(0xFF2E7D32),
      Color(0xFFF9A825),
      Color(0xFF1565C0),
    ],
    board: Color(0xFFF3E0C0),
    track: Color(0xFFFBEFD9),
    line: Color(0xFF8D6E63),
    frame: Color(0xFF4E342E),
    star: Color(0xFF6D4C41),
    panel: Color(0xFFFFF3E0),
    onPanel: Color(0xFF3E2723),
    accent: Color(0xFFFFB74D),
  );

  static const candy = LudoTheme(
    name: 'Candy',
    background: [Color(0xFFEC407A), Color(0xFF7B1FA2)],
    colors: [
      Color(0xFFFF5277),
      Color(0xFF26C6A0),
      Color(0xFFFFCA28),
      Color(0xFF42A5F5),
    ],
    board: Color(0xFFFFFFFF),
    track: Color(0xFFFFF5FA),
    line: Color(0xFFF48FB1),
    frame: Color(0xFF880E4F),
    star: Color(0xFFAD1457),
    panel: Color(0xFFFFF0F6),
    onPanel: Color(0xFF4A148C),
    accent: Color(0xFFFF4081),
  );

  static const night = LudoTheme(
    name: 'Night',
    background: [Color(0xFF102027), Color(0xFF000A12)],
    colors: [
      Color(0xFFFF5252),
      Color(0xFF69F0AE),
      Color(0xFFFFFF00),
      Color(0xFF40C4FF),
    ],
    board: Color(0xFF263238),
    track: Color(0xFF37474F),
    line: Color(0xFF546E7A),
    frame: Color(0xFF000000),
    star: Color(0xFFB0BEC5),
    panel: Color(0xFF263238),
    onPanel: Color(0xFFECEFF1),
    accent: Color(0xFF00E5FF),
  );

  static const all = [classic, royal, wood, candy, night];
}
