/// Build-time settings, all overridable with --dart-define.
abstract final class AppConfig {
  static const packageName = 'in.onlysoftware.roz_quiz';
  static const appVersion = '1.0.0';

  /// Where the published feed lives (see ad-apps-builds/feeds/SCHEMA.md).
  /// Must end with a slash; paths like `quiz/index.json` are appended.
  static const feedBaseUrl = String.fromEnvironment(
    'FEED_BASE_URL',
    defaultValue:
        'https://raw.githubusercontent.com/hemantpatle153-ops/ad-apps-builds/feed-data/',
  );

  /// The first release ships without ads. `--dart-define=ADS=on` turns on
  /// consent, the AdMob SDK and the banner (see android/app/build.gradle.kts
  /// for what a Play bundle then needs).
  static const adsEnabled = String.fromEnvironment('ADS', defaultValue: 'off') == 'on';

  /// Placeholder until website/build.py has a Roz Quiz page.
  static const privacyPolicyUrl =
      'https://dice-dhamaal.web.app/privacy/roz_quiz.html';

  static const storeUrl =
      'https://play.google.com/store/apps/details?id=$packageName';
}
