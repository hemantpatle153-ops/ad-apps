import 'package:flutter/material.dart';

import '../sfx.dart';
import '../store.dart';
import '../themes.dart';
import 'board_painter.dart';
import 'kit.dart';

/// Ludo board themes plus the app-wide sound, vibration and speed switches.
class LudoSettingsScreen extends StatelessWidget {
  const LudoSettingsScreen({super.key, required this.store, required this.sfx});

  final LudoStore store;
  final LudoSfx sfx;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final theme = store.theme;
        return LudoPage(
          theme: theme,
          title: 'Ludo settings',
          children: [
            const LudoHeading('Board'),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: LudoTheme.all.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final t = LudoTheme.all[i];
                  final selected = store.themeIndex == i;
                  return GestureDetector(
                    onTap: () {
                      sfx.play(LudoSound.tap);
                      store.themeIndex = i;
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 116,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: t.background,
                        ),
                        border: Border.all(
                          color: selected ? Colors.white : Colors.white24,
                          width: selected ? 3 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          SizedBox.square(
                            dimension: 96,
                            child: CustomPaint(painter: LudoBoardPainter(t)),
                          ),
                          const SizedBox(height: 6),
                          Text(t.name,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const LudoHeading('Game'),
            LudoPanel(
              theme: theme,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.volume_up_rounded),
                    title: const Text('Sound effects'),
                    value: store.sound,
                    onChanged: (v) {
                      store.sound = v;
                      sfx.play(LudoSound.tap);
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
                    subtitle:
                        const Text('Pieces and computer players move quicker'),
                    value: store.fastMoves,
                    onChanged: (v) => store.fastMoves = v,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
