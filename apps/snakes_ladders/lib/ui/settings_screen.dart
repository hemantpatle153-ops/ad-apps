import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import '../audio/sfx.dart';
import '../game/board.dart';
import '../game/store.dart';
import '../game/themes.dart';
import '../main.dart';
import 'board_painter.dart';
import 'widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store, required this.sfx});

  final Store store;
  final Sfx sfx;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        bottomNavigationBar: const BannerAdSlot(),
        body: GameBackground(
          theme: store.theme,
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              children: [
                const Row(
                  children: [
                    BackButton(color: Colors.white),
                    Expanded(
                      child: Text(
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        'Themes & Settings',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SectionTitle('Board theme'),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.85,
                  children: [
                    for (var i = 0; i < BoardTheme.all.length; i++)
                      _ThemeTile(
                        theme: BoardTheme.all[i],
                        selected: store.themeIndex == i,
                        onTap: () {
                          sfx.play(Sound.tap);
                          store.themeIndex = i;
                        },
                      ),
                  ],
                ),
                const SectionTitle('Game'),
                Panel(
                  theme: store.theme,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.volume_up_rounded),
                        title: const Text('Sound effects'),
                        value: store.sound,
                        onChanged: (v) {
                          store.sound = v;
                          sfx.play(Sound.tap);
                        },
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.vibration_rounded),
                        title: const Text('Vibration'),
                        value: store.vibration,
                        onChanged: (v) {
                          store.vibration = v;
                          sfx.buzz();
                        },
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.fast_forward_rounded),
                        title: const Text('Fast moves'),
                        subtitle: const Text(
                            'Tokens and computer players move quicker'),
                        value: store.fastMoves,
                        onChanged: (v) => store.fastMoves = v,
                      ),
                      ListTile(
                        leading: const Icon(Icons.star_rounded),
                        title: const Text('Rate this app'),
                        onTap: () => openStorePage(packageName),
                      ),
                      ListTile(
                        leading: const Icon(Icons.privacy_tip_outlined),
                        title: const Text('Privacy policy'),
                        onTap: () => openLink(privacyPolicyUrl),
                      ),
                      FutureBuilder<bool>(
                        future: AdService.instance.privacyOptionsRequired(),
                        builder: (context, snap) => snap.data == true
                            ? ListTile(
                                leading: const Icon(Icons.ads_click_rounded),
                                title: const Text('Ad privacy choices'),
                                onTap: AdService.instance.showPrivacyOptions,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final BoardTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: theme.background,
          ),
          border: Border.all(
            color: selected ? theme.accent : Colors.transparent,
            width: 4,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                child: CustomPaint(
                  painter: BoardPainter(BoardLayout.classic, theme,
                      showNumbers: false),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (selected)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.check_circle_rounded,
                        color: Colors.white, size: 18),
                  ),
                Text(theme.name,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
