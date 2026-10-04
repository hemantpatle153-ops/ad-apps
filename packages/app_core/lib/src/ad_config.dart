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
  });

  /// Reads IDs from --dart-define, falling back to Google's test IDs.
  factory AdConfig.fromEnvironment() => const AdConfig(
        bannerId: String.fromEnvironment(
          'ADMOB_BANNER_ID',
          defaultValue: 'ca-app-pub-3940256099942544/9214589741',
        ),
        interstitialId: String.fromEnvironment(
          'ADMOB_INTERSTITIAL_ID',
          defaultValue: 'ca-app-pub-3940256099942544/1033173712',
        ),
        rewardedId: String.fromEnvironment(
          'ADMOB_REWARDED_ID',
          defaultValue: 'ca-app-pub-3940256099942544/5224354917',
        ),
      );

  final String bannerId;
  final String interstitialId;
  final String rewardedId;

  /// Minimum gap between two interstitials, to keep ads at natural breaks
  /// and stay inside AdMob policy.
  final Duration interstitialCooldown;
}
