import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import 'audio/sfx.dart';
import 'game/board.dart';
import 'game/store.dart';
import 'ludo/sfx.dart';
import 'ludo/store.dart';
import 'ludo/ui/kit.dart';
import 'ludo/ui/ludo_home.dart';
import 'ui/board_painter.dart';
import 'ui/home_screen.dart';
import 'ui/widgets.dart' show gameRoute;

/// The app's front door: pick a game.
class HubScreen extends StatelessWidget {
  const HubScreen({
    super.key,
    required this.store,
    required this.sfx,
    required this.ludo,
    required this.ludoSfx,
  });

  final Store store;
  final Sfx sfx;
  final LudoStore ludo;
  final LudoSfx ludoSfx;

  void _go(BuildContext context, Widget screen) {
    ludoSfx.play(LudoSound.tap);
    Navigator.of(context).push(gameRoute<void>(screen));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([store, ludo]),
      builder: (context, _) {
        final theme = ludo.theme;
        final ludoSaved = ludo.savedGames.length;
        final snakesSaved = store.savedGames.length;
        return Scaffold(
          bottomNavigationBar: const BannerAdSlot(),
          body: LudoBackground(
            theme: theme,
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                children: [
                  const Align(
                    alignment: Alignment.centerRight,
                    child: AppMenu(),
                  ),
                  const _Wordmark(),
                  const SizedBox(height: 28),
                  _GameCard(
                    title: 'Ludo',
                    subtitle: 'vs Computer · Online with voice chat · '
                        'Pass & Play',
                    badge: ludoSaved > 0 ? '$ludoSaved unfinished' : null,
                    colors: const [Color(0xFF1E88E5), Color(0xFF0D47A1)],
                    art: LudoPreview(theme: theme, size: 120),
                    onTap: () =>
                        _go(context, LudoHome(store: ludo, sfx: ludoSfx)),
                  ),
                  const SizedBox(height: 16),
                  _GameCard(
                    title: 'Snakes & Ladders',
                    subtitle: 'Saanp Seedhi · vs Computer · Pass & Play',
                    badge: snakesSaved > 0 ? '$snakesSaved unfinished' : null,
                    colors: const [Color(0xFF43A047), Color(0xFF1B5E20)],
                    art: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black45,
                              blurRadius: 14,
                              offset: Offset(0, 6)),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CustomPaint(
                          painter: BoardPainter(
                              BoardLayout.classic, store.theme,
                              showNumbers: false),
                        ),
                      ),
                    ),
                    onTap: () =>
                        _go(context, HomeScreen(store: store, sfx: sfx)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        LudoLogo(size: 48),
        Text(
          'PARTY',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: 10,
            shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Classic board games with friends',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ],
    );
  }
}

/// A big tile for one game: art on the left, name and modes on the right.
class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.art,
    required this.onTap,
    this.badge,
  });

  final String title;
  final String subtitle;
  final List<Color> colors;
  final Widget art;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.5), width: 2),
            boxShadow: [
              BoxShadow(color: colors.last, offset: const Offset(0, 6)),
            ],
          ),
          child: Row(
            children: [
              art,
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 13)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('PLAY',
                              style: TextStyle(
                                  color: colors.last,
                                  fontWeight: FontWeight.w900)),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(badge!,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
