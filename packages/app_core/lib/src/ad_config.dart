/// Ad unit IDs for one app.
///
/// Defaults are Google's public test IDs, which are safe to tap during
/// development. Release builds pass real IDs with --dart-define, e.g.
///   flutter build appbundle --dart-define=ADMOB_BANNER_ID=ca-app-pub-xxx/yyy
class AdConfig {
  const AdConfig({
    required this.bannerId,
    required this.interstitialId,
    required this.rewardedId,
    this.interstitialCooldown = const Duration(minutes: 2),
    this.enabled = true,
  });

  /// Reads IDs from --dart-define, falling back to Google's test IDs.
  ///
  /// Only apps that offer a rewarded ad pass [rewarded]; the others leave
  /// [rewardedId] empty so no rewarded ad is ever requested.
  ///
  /// `--dart-define=ADS=off` (or `ADS=false`) builds the app with ads switched
  /// off: the ad SDK is never started, no consent form is shown and nothing
  /// is requested.
  factory AdConfig.fromEnvironment({bool rewarded = false}) => AdConfig(
        enabled: !const ['off', 'false']
            .contains(const String.fromEnvironment('ADS', defaultValue: 'on')),
        bannerId: const String.fromEnvironment(
          'ADMOB_BANNER_ID',
          defaultValue: 'ca-app-pub-3940256099942544/9214589741',
        ),
        interstitialId: const String.fromEnvironment(
          'ADMOB_INTERSTITIAL_ID',
          defaultValue: 'ca-app-pub-3940256099942544/1033173712',
        ),
        rewardedId: rewarded
            ? const String.fromEnvironment(
                'ADMOB_REWARDED_ID',
                defaultValue: 'ca-app-pub-3940256099942544/5224354917',
              )
            : '',
      );

  final String bannerId;
  final String interstitialId;
  final String rewardedId;

  /// False when the app was built with ads switched off.
  final bool enabled;

  /// Minimum gap between two interstitials, to keep ads at natural breaks
  /// and stay inside AdMob policy.
  final Duration interstitialCooldown;
}
