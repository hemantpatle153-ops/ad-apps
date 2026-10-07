import 'package:flutter/material.dart';

import '../l10n/s.dart';
import '../l10n/strings.dart';
import '../state/app_controller.dart';

/// Makes the [AppController] available below and rebuilds dependents when
/// it changes.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController controller, required super.child})
      : super(notifier: controller);

  static AppController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Without subscribing to changes (for callbacks).
  static AppController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

extension AppContext on BuildContext {
  AppController get app => AppScope.of(this);
  S get s => AppScope.of(this).s;
  String tr(L key, [Map<String, Object?> args = const {}]) => s.t(key, args);

  void toast(String message, {SnackBarAction? action}) {
    final m = ScaffoldMessenger.maybeOf(this);
    m?.hideCurrentSnackBar();
    m?.showSnackBar(SnackBar(content: Text(message), action: action));
  }
}
