import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'src/app.dart';
import 'src/player/background_audio.dart';
import 'src/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final settings = await Settings.open();
  runApp(VideoPlayerApp(settings: settings));
  // Background audio, consent and ads start after the first frame so the
  // app opens instantly.
  BackgroundAudio.instance.init();
  AdService.instance.init(AdConfig.fromEnvironment());
}
