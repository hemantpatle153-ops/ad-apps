import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import '../game/store.dart';

enum Sound {
  dice(0.9),
  step(0.5),
  ladder(0.8),
  snake(0.8),
  six(0.7),
  win(0.9),
  tap(0.5);

  const Sound(this.volume);
  final double volume;
}

/// Short sound effects and vibration, both switchable in settings.
class Sfx {
  Sfx(this.store) {
    // Mix with the player's own music instead of pausing it.
    AudioPlayer.global
        .setAudioContext(
          AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers)
              .build(),
        )
        .ignore();
  }

  final Store store;
  final _players = <Sound, AudioPlayer>{};

  Future<void> play(Sound s) async {
    if (!store.sound) return;
    final p = _players.putIfAbsent(s, () {
      final p = AudioPlayer();
      p.setPlayerMode(PlayerMode.lowLatency);
      p.setReleaseMode(ReleaseMode.stop);
      return p;
    });
    try {
      await p.stop();
      await p.play(AssetSource('sounds/${s.name}.wav'), volume: s.volume);
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
