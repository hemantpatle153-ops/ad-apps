import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import '../audio/sfx.dart';
import '../game/board.dart';
import '../game/store.dart';
import '../game/themes.dart';
import '../main.dart';
import 'board_painter.dart';
import 'dice.dart';
import 'game_screen.dart';
import 'settings_screen.dart';
import 'setup_screen.dart';
import 'tokens.dart';
import 'widgets.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.store, required this.sfx});

  final Store store;
  final Sfx sfx;

  Future<void> _go(BuildContext context, Widget screen) {
    sfx.play(Sound.tap);
    return Navigator.of(context).push(gameRoute<void>(screen));
  }

  Future<void> _delete(BuildContext context, SavedGame s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this saved game?'),
        content: Text('${s.game.board.name} with '
            '${s.game.players.map((p) => p.name).join(', ')}'),
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
    if (ok == true) await store.deleteSaved(s.game.id);
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
          body: GameBackground(
            theme: theme,
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                children: [
                  const Align(
                    alignment: Alignment.centerRight,
                    child: AppMenu(),
                  ),
                  _Title(theme: theme),
                  const SizedBox(height: 16),
                  Center(child: _Preview(theme: theme)),
                  const SizedBox(height: 24),
                  BigButton(
                    color: tokenColors[0],
                    icon: Icons.smart_toy_rounded,
                    label: 'Play vs Computer',
                    sub: 'Play offline against 1 to 3 bots',
                    onTap: () => _go(context,
                        SetupScreen(store: store, sfx: sfx, vsComputer: true)),
                  ),
                  const SizedBox(height: 12),
                  BigButton(
                    color: tokenColors[1],
                    icon: Icons.groups_rounded,
                    label: 'Pass & Play',
                    sub: '2 to 4 friends on one phone',
                    onTap: () => _go(context,
                        SetupScreen(store: store, sfx: sfx, vsComputer: false)),
                  ),
                  if (saved.isNotEmpty) ...[
                    SectionTitle(
                        'Unfinished games (${saved.length}/${Store.maxSaved})'),
                    for (final s in saved)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _SavedCard(
                          saved: s,
                          theme: theme,
                          onPlay: () => _go(
                              context,
                              GameScreen(
                                  engine: s.game, store: store, sfx: sfx)),
                          onDelete: () => _delete(context, s),
                        ),
                      ),
                  ],
                  const SizedBox(height: 12),
                  BigButton(
                    color: tokenColors[3],
                    icon: Icons.palette_rounded,
                    label: 'Themes & Settings',
                    sub: '${theme.name} theme',
                    onTap: () =>
                        _go(context, SettingsScreen(store: store, sfx: sfx)),
                  ),
                  const SizedBox(height: 20),
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

/// One unfinished game: board, players, who leads, and when it was played.
class _SavedCard extends StatelessWidget {
  const _SavedCard({
    required this.saved,
    required this.theme,
    required this.onPlay,
    required this.onDelete,
  });

  final SavedGame saved;
  final BoardTheme theme;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final g = saved.game;
    final leader = g.standings.first;
    final lead = g.positions[leader];
    final vsBot = g.players.any((p) => p.isBot);
    return GestureDetector(
      onTap: onPlay,
      child: Panel(
        theme: theme,
        padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox.square(
                dimension: 58,
                child: CustomPaint(
                  painter: BoardPainter(g.board, theme, showNumbers: false),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${g.board.name} · ${vsBot ? 'vs Computer' : 'Pass & Play'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      for (var i = 0; i < g.players.length; i++)
                        PawnIcon(color: g.players[i].color, size: 22),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          lead == 0
                              ? 'Nobody has started'
                              : '${g.players[leader].name} leads on $lead',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: lead / 100,
                      minHeight: 6,
                      color: tokenColors[g.players[leader].color],
                      backgroundColor: theme.onPanel.withValues(alpha: 0.12),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Played ${timeAgo(saved.savedAt)} · '
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
                      backgroundColor: tokenColors[g.players[0].color]),
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

class _Title extends StatelessWidget {
  const _Title({required this.theme});

  final BoardTheme theme;

  @override
  Widget build(BuildContext context) {
    const shadow = [
      Shadow(color: Colors.black54, offset: Offset(0, 3), blurRadius: 6),
    ];
    return Column(
      children: [
        const Text(
          'Snakes & Ladders',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 34,
            fontWeight: FontWeight.w900,
            shadows: shadow,
          ),
        ),
        Text(
          'Saanp Seedhi',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: theme.accent,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            shadows: shadow,
          ),
        ),
      ],
    );
  }
}

/// A small tilted board with a few tokens, as cover art.
class _Preview extends StatefulWidget {
  const _Preview({required this.theme});

  final BoardTheme theme;

  @override
  State<_Preview> createState() => _PreviewState();
}

/// A small tilted board that gently floats, with two dice beside it.
class _PreviewState extends State<_Preview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 220.0;
    final board = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size / 28),
        boxShadow: const [
          BoxShadow(
              color: Colors.black54, blurRadius: 24, offset: Offset(0, 12)),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: BoardPainter(BoardLayout.classic, widget.theme,
                  showNumbers: false),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: TokensPainter(TokenLayer(
                [0, 1, 2, 3],
                const [
                  Offset(2.5, 7.5),
                  Offset(6.5, 4.5),
                  Offset(4.5, 1.5),
                  Offset(8.5, 6.5)
                ],
              )),
            ),
          ),
        ],
      ),
    );
    return SizedBox(
      width: size + 80,
      height: size + 40,
      child: AnimatedBuilder(
        animation: _c,
        child: board,
        builder: (context, child) {
          final v = Curves.easeInOut.transform(_c.value);
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.translate(
                offset: Offset(0, -6 + 12 * v),
                child: Transform.rotate(angle: -0.07 + 0.03 * v, child: child),
              ),
              Positioned(
                left: 0,
                bottom: 6 + 10 * v,
                child: Transform.rotate(
                  angle: -0.4 + 0.25 * v,
                  child: DiceView(value: 6, color: tokenColors[0], size: 54),
                ),
              ),
              Positioned(
                right: 2,
                top: 4 + 10 * (1 - v),
                child: Transform.rotate(
                  angle: 0.35 - 0.25 * v,
                  child: DiceView(value: 3, color: tokenColors[3], size: 44),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.store, required this.theme});

  final Store store;
  final BoardTheme theme;

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, String value) => Expanded(
          child: Column(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value,
                    style: TextStyle(
                        color: theme.onPanel,
                        fontSize: 22,
                        fontWeight: FontWeight.w900)),
              ),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: theme.onPanel.withValues(alpha: 0.7),
                      fontSize: 12)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.panel.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          stat('Games\nplayed', '${store.played}'),
          stat('Wins vs\nbots', '${store.wins}/${store.botGames}'),
          stat('Ladders\nclimbed', '${store.laddersClimbed}'),
          stat('Snake\nbites', '${store.snakeBites}'),
          stat('Fastest win\n(rolls)',
              store.fastestWin == 0 ? '-' : '${store.fastestWin}'),
        ],
      ),
    );
  }
}

/// Rate, privacy policy and (in the EU/UK) ad privacy choices.
class AppMenu extends StatelessWidget {
  const AppMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AdService.instance.privacyOptionsRequired(),
      builder: (context, snap) => PopupMenuButton<VoidCallback>(
        icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
        onSelected: (fn) => fn(),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: () => openStorePage(packageName),
            child: const Text('Rate this app'),
          ),
          PopupMenuItem(
            value: () => openLink(privacyPolicyUrl),
            child: const Text('Privacy policy'),
          ),
          if (snap.data == true)
            PopupMenuItem(
              value: AdService.instance.showPrivacyOptions,
              child: const Text('Ad privacy choices'),
            ),
        ],
      ),
    );
  }
}
