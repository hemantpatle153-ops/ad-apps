import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app/controller.dart';
import '../l10n/strings.dart';

/// Gives every screen the [AppController] and rebuilds on its changes.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController controller, required super.child})
      : super(notifier: controller);

  static AppController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Without listening (for callbacks).
  static AppController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

extension ScopeContext on BuildContext {
  AppController get app => AppScope.of(this);
  S get s => AppScope.of(this).s;
}

/// Platform hooks the tests replace.
abstract final class Hooks {
  static Future<void> Function(String text) share =
      (text) => SharePlus.instance.share(ShareParams(text: text));
}

/// Taps, sounds and vibration for answers, following the settings.
void answerFeedback(AppController app, {required bool correct}) {
  final s = app.settings;
  if (s.haptics) {
    correct ? HapticFeedback.lightImpact() : HapticFeedback.heavyImpact();
  }
  if (s.sound) SystemSound.play(SystemSoundType.click);
}

void showSnack(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
