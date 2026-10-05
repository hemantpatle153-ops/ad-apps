import 'package:flutter/material.dart';

/// Token colours, the same four as a Ludo board.
const tokenColors = [
  Color(0xFFE53935), // red
  Color(0xFF43A047), // green
  Color(0xFFFDD835), // yellow
  Color(0xFF1E88E5), // blue
];

const tokenColorNames = ['Red', 'Green', 'Yellow', 'Blue'];

/// Everything that changes when the player switches the board theme.
class BoardTheme {
  const BoardTheme({
    required this.name,
    required this.background,
    required this.cells,
    required this.frame,
    required this.number,
    required this.ladderRail,
    required this.ladderRung,
    required this.snakes,
    required this.panel,
    required this.onPanel,
    required this.accent,
    this.dark = false,
  });

  final String name;

  /// Screen background gradient, top to bottom.
  final List<Color> background;

  /// Cell colours, used in a repeating diagonal pattern.
  final List<Color> cells;
  final Color frame;
  final Color number;
  final Color ladderRail;
  final Color ladderRung;

  /// Body colour pairs (main, stripe) for the snakes.
  final List<(Color, Color)> snakes;
  final Color panel;
  final Color onPanel;
  final Color accent;
  final bool dark;

  static const classic = BoardTheme(
    name: 'Classic',
    background: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
    cells: [
      Color(0xFFFFF3C4),
      Color(0xFFFFCC80),
      Color(0xFFC5E1A5),
      Color(0xFFFFAB91),
      Color(0xFF90CAF9),
    ],
    frame: Color(0xFF5D4037),
    number: Color(0xFF4E342E),
    ladderRail: Color(0xFF8D5524),
    ladderRung: Color(0xFFC68642),
    snakes: [
      (Color(0xFF2E7D32), Color(0xFFCDDC39)),
      (Color(0xFFC62828), Color(0xFFFFB300)),
      (Color(0xFF6A1B9A), Color(0xFFF48FB1)),
      (Color(0xFF00838F), Color(0xFFFFF176)),
    ],
    panel: Color(0xFFFFF8E1),
    onPanel: Color(0xFF3E2723),
    accent: Color(0xFFFFB300),
  );

  static const jungle = BoardTheme(
    name: 'Jungle',
    background: [Color(0xFF004D40), Color(0xFF00251A)],
    cells: [
      Color(0xFFA5D6A7),
      Color(0xFF81C784),
      Color(0xFFDCEDC8),
      Color(0xFFAED581),
    ],
    frame: Color(0xFF3E2723),
    number: Color(0xFF1B5E20),
    ladderRail: Color(0xFF6D4C41),
    ladderRung: Color(0xFFBCAAA4),
    snakes: [
      (Color(0xFFFF6F00), Color(0xFF212121)),
      (Color(0xFF5E35B1), Color(0xFFFFEB3B)),
      (Color(0xFFD84315), Color(0xFFFFCCBC)),
    ],
    panel: Color(0xFFE8F5E9),
    onPanel: Color(0xFF1B5E20),
    accent: Color(0xFFFFCA28),
  );

  static const night = BoardTheme(
    name: 'Neon Night',
    background: [Color(0xFF1A1A40), Color(0xFF0B0B1E)],
    cells: [
      Color(0xFF232356),
      Color(0xFF2C2C6C),
      Color(0xFF1F3A60),
      Color(0xFF34295E),
    ],
    frame: Color(0xFF00E5FF),
    number: Color(0xFFB3E5FC),
    ladderRail: Color(0xFFFFEA00),
    ladderRung: Color(0xFFFFF59D),
    snakes: [
      (Color(0xFFFF4081), Color(0xFF7C4DFF)),
      (Color(0xFF00E676), Color(0xFF00B0FF)),
      (Color(0xFFFF9100), Color(0xFFFF1744)),
    ],
    panel: Color(0xFF282860),
    onPanel: Color(0xFFE3F2FD),
    accent: Color(0xFF00E5FF),
    dark: true,
  );

  static const candy = BoardTheme(
    name: 'Candy',
    background: [Color(0xFFAD1457), Color(0xFF6A1B9A)],
    cells: [
      Color(0xFFFCE4EC),
      Color(0xFFF8BBD0),
      Color(0xFFE1BEE7),
      Color(0xFFFFF9C4),
      Color(0xFFB2EBF2),
    ],
    frame: Color(0xFF880E4F),
    number: Color(0xFF6A1B9A),
    ladderRail: Color(0xFFEC407A),
    ladderRung: Color(0xFFFFFFFF),
    snakes: [
      (Color(0xFF7B1FA2), Color(0xFF80DEEA)),
      (Color(0xFF26A69A), Color(0xFFFFF59D)),
      (Color(0xFFF4511E), Color(0xFFFFE0B2)),
    ],
    panel: Color(0xFFFFF0F6),
    onPanel: Color(0xFF4A148C),
    accent: Color(0xFFFF4081),
  );

  static const all = [classic, jungle, night, candy];
}
