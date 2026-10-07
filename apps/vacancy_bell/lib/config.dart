/// App-wide constants. Values that differ per build come from
/// --dart-define so nothing secret lives in the (public) repository.
abstract final class AppConfig {
  static const packageName = 'in.onlysoftware.vacancy_bell';

  /// Where the feed files live. Every path in SCHEMA.md is appended to this.
  /// Override for a test feed with --dart-define=FEED_BASE_URL=https://.../
  static const feedBaseUrl = String.fromEnvironment(
    'FEED_BASE_URL',
    defaultValue:
        'https://raw.githubusercontent.com/hemantpatle153-ops/ad-apps-builds/feed-data/',
  );

  /// Highest feed schema this build understands. Newer files are still read
  /// (unknown keys are ignored) but a hint asks the user to update.
  static const supportedSchema = 1;

  /// Ads are off for the first release. A build turns them on with
  /// --dart-define=ADS=on (and the AdMob IDs, see README.md).
  static const adsEnabled =
      String.fromEnvironment('ADS', defaultValue: 'off') == 'on';

  /// Store page used in shared text. Placeholder until the app is live.
  static const playLink =
      'https://play.google.com/store/apps/details?id=$packageName';

  /// Written by website/build.py, served by Firebase Hosting.
  static const privacyPolicyUrl =
      'https://dice-dhamaal.web.app/privacy/vacancy_bell.html';

  /// Name used in the feedReports database entries.
  static const reportAppId = 'vacancy_bell';
}
