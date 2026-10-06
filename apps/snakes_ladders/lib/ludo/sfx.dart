import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import 'store.dart';

enum LudoSound {
  dice('dice', 0.9),
  step('step', 0.45),
  six('six', 0.7),
  capture('ludo_capture', 0.9),
  home('ludo_home', 0.8),
  out('ludo_out', 0.7),
  win('win', 0.9),
  tap('tap', 0.5);

  const LudoSound(this.file, this.volume);
  final String file;
  final double volume;
}

/// Short sound effects and vibration for Ludo, both switchable in settings.
class LudoSfx {
  LudoSfx(this.store);

  final LudoStore store;
  final _players = <LudoSound, AudioPlayer>{};

  Future<void> play(LudoSound s) async {
    if (!store.sound) return;
    final p = _players.putIfAbsent(s, () {
      final p = AudioPlayer();
      p.setPlayerMode(PlayerMode.lowLatency);
      p.setReleaseMode(ReleaseMode.stop);
      return p;
    });
    try {
      await p.stop();
      await p.play(AssetSource('sounds/${s.file}.wav'), volume: s.volume);
    } catch (_) {
      // A missing audio device must never break the game.
    }
  }

  void buzz({bool strong = false}) {
    if (!store.vibration) return;
    strong ? HapticFeedback.heavyImpact() : HapticFeedback.lightImpact();
  }

  void dispose() {
    for (final p in _players.values) {
      p.dispose();
    }
    _players.clear();
  }
}
