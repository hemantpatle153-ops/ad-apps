import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_app/src/party/online.dart';

void main() {
  FirebaseException fb(String code) =>
      FirebaseException(plugin: 'firebase_database', code: code);

  test('network problems say no internet', () {
    expect(OnlineException.from(TimeoutException(null)).error,
        OnlineError.offline);
    expect(OnlineException.from(fb('network-request-failed')).error,
        OnlineError.offline);
  });

  test('a refused write is not reported as no internet', () {
    final e = OnlineException.from(fb('permission-denied'));
    expect(e.error, OnlineError.denied);
    expect(e.message, isNot(contains('internet')));
    expect(e.message, contains('permission-denied'));
  });

  test('other errors show their code', () {
    final e = OnlineException.from(fb('unknown'));
    expect(e.error, OnlineError.failed);
    expect(e.message, contains('(unknown)'));
    expect(
        OnlineException.from(StateError('x')).message, contains('StateError'));
  });

  test('an OnlineException passes through unchanged', () {
    const e = OnlineException(OnlineError.notFound);
    expect(OnlineException.from(e), same(e));
  });
}
