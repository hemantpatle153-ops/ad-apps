import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'src/app.dart';
import 'src/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'in.onlysoftware.multi_speaker.playback',
    androidNotificationChannelName: 'Party music',
    androidNotificationIcon: 'drawable/ic_stat_speaker',
    // Keep the service alive while paused so the party survives the
    // screen going off.
    androidStopForegroundOnPause: false,
  );
  final settings = await Settings.load();
  runApp(MultiSpeakerApp(settings: settings));
  // Consent and ads start after the first frame so the app opens instantly.
  AdService.instance.init(AdConfig.fromEnvironment());
}
