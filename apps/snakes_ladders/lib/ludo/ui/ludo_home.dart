import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import '../../ui/widgets.dart' show BigButton, gameRoute, timeAgo;
import '../engine.dart';
import '../match.dart';
import '../sfx.dart';
import '../store.dart';
import '../themes.dart';
import 'board_painter.dart';
import 'game_screen.dart';
import 'geometry.dart';
import 'kit.dart';
import 'online_screen.dart';
import 'pieces.dart';
import 'settings_screen.dart';
import 'setup_screen.dart';

/// Ludo's own menu: modes, unfinished games and stats.
class LudoHome extends StatelessWidget {
  const LudoHome({super.key, required this.store, required this.sfx});

  final LudoStore store;
  final LudoSfx sfx;

  Future<void> _go(BuildContext context, Widget screen) {
    sfx.play(LudoSound.tap);
    return Navigator.of(context).push(gameRoute<void>(screen));
  }

  Future<void> _delete(BuildContext context, SavedGame s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this saved game?'),
        content: Text(s.engine.players.map((p) => p.name).join(', ')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await store.deleteSaved(s.id);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final theme = store.theme;
        final saved = store.savedGames;
        return Scaffold(
          bottomNavigationBar: const BannerAdSlot(),
          body: LudoBackground(
            theme: theme,
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                children: [
                  Row(
                    children: [
                      const BackButton(color: Colors.white),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Themes & settings',
                        icon: const Icon(Icons.settings_rounded,
                            color: Colors.white),
                        onPressed: () => _go(context,
                            LudoSettingsScreen(store: store, sfx: sfx)),
                      ),
                    ],
                  ),
                  const Center(child: LudoLogo(size: 40)),
                  const SizedBox(height: 14),
                  Center(child: LudoPreview(theme: theme, size: 190)),
                  const SizedBox(height: 22),
                  BigButton(
                    color: theme.colors[0],
                    icon: Icons.smart_toy_rounded,
                    label: 'vs Computer',
                    sub: 'Play offline against 1 to 3 bots',
                    onTap: () => _go(
                        context,
                        LudoSetupScreen(
                            store: store, sfx: sfx, vsComputer: true)),
                  ),
                  const SizedBox(height: 12),
                  BigButton(
                    color: theme.colors[1],
                    icon: Icons.wifi_tethering_rounded,
                    label: 'Play with Friends',
                    sub: 'Online room with a code and voice chat',
                    onTap: () =>
                        _go(context, OnlineScreen(store: store, sfx: sfx)),
                  ),
                  const SizedBox(height: 12),
                  BigButton(
                    color: theme.colors[3],
                    icon: Icons.groups_rounded,
                    label: 'Pass & Play',
                    sub: '2 to 4 friends on one phone',
                    onTap: () => _go(
                        context,
                        LudoSetupScreen(
                            store: store, sfx: sfx, vsComputer: false)),
                  ),
                  if (saved.isNotEmpty) ...[
                    LudoHeading('Unfinished games '
                        '(${saved.length}/${LudoStore.maxSaved})'),
                    for (final s in saved)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _SavedCard(
                          saved: s,
                          theme: theme,
                          onPlay: () => _go(
                            context,
                            LudoGameScreen(
                              engine: s.engine,
                              store: store,
                              sfx: sfx,
                              link: LocalLink(),
                              gameId: s.id,
                              me: 0,
                            ),
                          ),
                          onDelete: () => _delete(context, s),
                        ),
                      ),
                  ],
                  const SizedBox(height: 14),
                  _Stats(store: store, theme: theme),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Wordmark: [word] with each letter in a board colour.
class LudoLogo extends StatelessWidget {
  const LudoLogo({super.key, this.size = 40, this.word = 'LUDO'});

  final double size;
  final String word;

  @override
  Widget build(BuildContext context) {
    const colors = [
      Color(0xFFE53935),
      Color(0xFF43A047),
      Color(0xFFFDD835),
      Color(0xFF1E88E5),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < word.length; i++)
          Text(
            word[i],
            style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w900,
              color: colors[i % colors.length],
              letterSpacing: 2,
              shadows: const [
                Shadow(color: Colors.white, offset: Offset(0, -1)),
                Shadow(
                    color: Colors.black54, offset: Offset(0, 3), blurRadius: 4),
              ],
            ),
          ),
      ],
    );
  }
}

/// A small board with a few pieces, as cover art.
class LudoPreview extends StatelessWidget {
  const LudoPreview({super.key, required this.theme, this.size = 200});

  final LudoTheme theme;
  final double size;

  @override
  Widget build(BuildContext context) {
    final layer = PieceLayer(
      [for (var c = 0; c < 4; c++) theme.colors[c]],
      [
        Grid.tokenSpot(0, 3, 0, 4),
        Grid.tokenSpot(1, 20, 0, 4),
        Grid.yardSpot(2, 1),
        Grid.tokenSpot(3, 52, 0, 4),
      ],
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size / 24),
        boxShadow: const [
          BoxShadow(
              color: Colors.black54, blurRadius: 24, offset: Offset(0, 12)),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: LudoBoardPainter(theme))),
          Positioned.fill(child: CustomPaint(painter: PiecesPainter(layer))),
        ],
      ),
    );
  }
}

class _SavedCard extends StatelessWidget {
  const _SavedCard({
    required this.saved,
    required this.theme,
    required this.onPlay,
    required this.onDelete,
  });

  final SavedGame saved;
  final LudoTheme theme;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final g = saved.engine;
    final vsBot = g.players.any((p) => p.isBot);
    final leader = g.standings.first;
    final home = [
      for (var p = 0; p < g.players.length; p++)
        g.tokens[p].where((t) => t == Track.home).length
    ];
    return GestureDetector(
      onTap: onPlay,
      child: LudoPanel(
        theme: theme,
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${vsBot ? 'vs Computer' : 'Pass & Play'}'
                    '${g.rules.tokens == 2 ? ' · Quick' : ''}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (var p = 0; p < g.players.length; p++) ...[
                        PieceIcon(
                            color: theme.colors[g.players[p].color], size: 22),
                        Text('${home[p]}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 13)),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: g.progress(leader),
                      minHeight: 6,
                      color: theme.colors[g.players[leader].color],
                      backgroundColor: theme.onPanel.withValues(alpha: 0.12),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${timeAgo(saved.savedAt)} · '
                    "${g.currentPlayer.name}'s turn",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.onPanel.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.filled(
                  onPressed: onPlay,
                  tooltip: 'Continue',
                  style: IconButton.styleFrom(
                      backgroundColor: theme.colors[g.players[0].color]),
                  icon:
                      const Icon(Icons.play_arrow_rounded, color: Colors.white),
                ),
                IconButton(
                  onPressed: onDelete,
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.delete_outline_rounded,
                      color: theme.onPanel.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.store, required this.theme});

  final LudoStore store;
  final LudoTheme theme;

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, String value) => Expanded(
          child: Column(
            children: [
              Text(value,
                  style: TextStyle(
                      color: theme.onPanel,
                      fontSize: 22,
                      fontWeight: FontWeight.w900)),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: theme.onPanel.withValues(alpha: 0.7),
                      fontSize: 12)),
            ],
          ),
        );
    return LudoPanel(
      theme: theme,
      child: Row(
        children: [
          stat('Played', '${store.played}'),
          stat('Wins', '${store.wins}'),
          stat('Online', '${store.onlineGames}'),
          stat('Cuts', '${store.captures}'),
        ],
      ),
    );
  }
}
