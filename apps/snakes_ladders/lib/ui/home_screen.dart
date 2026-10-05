import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import '../audio/sfx.dart';
import '../game/board.dart';
import '../game/engine.dart';
import '../game/store.dart';
import '../game/themes.dart';
import '../main.dart';
import 'board_painter.dart';
import 'game_screen.dart';
import 'settings_screen.dart';
import 'setup_screen.dart';
import 'tokens.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.store, required this.sfx});

  final Store store;
  final Sfx sfx;

  Future<void> _go(BuildContext context, Widget screen) {
    sfx.play(Sound.tap);
    return Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final theme = store.theme;
        final saved = store.loadSaved();
        return Scaffold(
          bottomNavigationBar: const BannerAdSlot(),
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: theme.background,
              ),
            ),
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
                  if (saved != null) ...[
                    _BigButton(
                      color: const Color(0xFFFFB300),
                      icon: Icons.play_circle_fill_rounded,
                      label: 'Continue game',
                      sub: _savedLabel(saved),
                      onTap: () => _go(context,
                          GameScreen(engine: saved, store: store, sfx: sfx)),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _BigButton(
                    color: tokenColors[0],
                    icon: Icons.smart_toy_rounded,
                    label: 'Play vs Computer',
                    sub: 'Play offline against 1 to 3 bots',
                    onTap: () => _go(context,
                        SetupScreen(store: store, sfx: sfx, vsComputer: true)),
                  ),
                  const SizedBox(height: 12),
                  _BigButton(
                    color: tokenColors[1],
                    icon: Icons.groups_rounded,
                    label: 'Pass & Play',
                    sub: '2 to 4 friends on one phone',
                    onTap: () => _go(context,
                        SetupScreen(store: store, sfx: sfx, vsComputer: false)),
                  ),
                  const SizedBox(height: 12),
                  _BigButton(
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

  String _savedLabel(GameEngine g) {
    final names = g.players.map((p) => p.name).join(', ');
    return '${g.board.name} · $names';
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
class _Preview extends StatelessWidget {
  const _Preview({required this.theme});

  final BoardTheme theme;

  @override
  Widget build(BuildContext context) {
    const size = 230.0;
    return Transform.rotate(
      angle: -0.06,
      child: Container(
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
                painter: BoardPainter(BoardLayout.classic, theme,
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
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.color,
    required this.icon,
    required this.label,
    required this.sub,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Color.lerp(color, Colors.black, 0.3)!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(colors: [color, dark]),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.6), width: 2),
            boxShadow: [
              BoxShadow(color: dark, offset: const Offset(0, 5)),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 34),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w900)),
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
          ),
        ),
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
