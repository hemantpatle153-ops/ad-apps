import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';

/// Owns consent, SDK start-up and the full-screen ads for the app.
///
/// Call [init] once from main(). Every other method is safe to call before
/// init finishes or when consent was refused: it simply shows nothing.
class AdService {
  AdService._();

  static final AdService instance = AdService._();

  AdConfig _config = AdConfig.fromEnvironment();
  AdConfig get config => _config;

  /// True once the user's consent state allows ad requests.
  final ValueNotifier<bool> ready = ValueNotifier(false);

  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  DateTime? _lastInterstitialShown;

  Future<void> init(AdConfig config) async {
    _config = config;
    if (!config.enabled) return;
    await _gatherConsent();
    if (await ConsentInformation.instance.canRequestAds()) {
      await MobileAds.instance.initialize();
      ready.value = true;
      _loadInterstitial();
      _loadRewarded();
    }
  }

  /// Shows Google's consent form when the user's region needs one (EU, UK).
  Future<void> _gatherConsent() {
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => ConsentForm.loadAndShowConsentFormIfRequired((_) {
        if (!done.isCompleted) done.complete();
      }),
      (_) {
        if (!done.isCompleted) done.complete();
      },
    );
    return done.future;
  }

  /// Whether settings should offer a "Privacy options" entry.
  Future<bool> privacyOptionsRequired() async =>
      _config.enabled &&
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
      PrivacyOptionsRequirementStatus.required;

  /// Lets the user change their consent choice later.
  void showPrivacyOptions() => ConsentForm.showPrivacyOptionsForm((_) {});

  void _loadInterstitial() {
    InterstitialAd.load(
      adUnitId: _config.interstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (_) => _interstitial = null,
      ),
    );
  }

  void _loadRewarded() {
    if (_config.rewardedId.isEmpty) return;
    RewardedAd.load(
      adUnitId: _config.rewardedId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewarded = ad,
        onAdFailedToLoad: (_) => _rewarded = null,
      ),
    );
  }

  /// Shows an interstitial if one is loaded and the cooldown has passed.
  ///
  /// Call only at natural breaks (after a result, between games), never on
  /// app open or in the middle of a task.
  Future<void> maybeShowInterstitial() async {
    final ad = _interstitial;
    final last = _lastInterstitialShown;
    if (ad == null) return;
    if (last != null &&
        DateTime.now().difference(last) < _config.interstitialCooldown) {
      return;
    }
    _interstitial = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _loadInterstitial();
      },
    );
    _lastInterstitialShown = DateTime.now();
    await ad.show();
  }

  bool get rewardedReady => _rewarded != null;

  /// Shows a rewarded ad. Completes with true only if the user earned the
  /// reward, so callers unlock the feature only on true.
  Future<bool> showRewarded() {
    final ad = _rewarded;
    if (ad == null) return Future.value(false);
    _rewarded = null;
    final result = Completer<bool>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadRewarded();
        if (!result.isCompleted) result.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _loadRewarded();
        if (!result.isCompleted) result.complete(false);
      },
    );
    ad.show(onUserEarnedReward: (_, __) => earned = true);
    return result.future;
  }
}
