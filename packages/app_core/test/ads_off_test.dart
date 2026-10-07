import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// The method channel every google_mobile_ads call goes through.
const _adsChannel = 'plugins.flutter.io/google_mobile_ads';

const _off = AdConfig(
  enabled: false,
  bannerId: 'banner',
  interstitialId: 'interstitial',
  rewardedId: 'rewarded',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var sdkCalls = 0;

  setUp(() {
    sdkCalls = 0;
    // Any call into the ads SDK (consent, start-up, ad loads, banner size)
    // lands here, so a count above zero means an ads-off build touched it.
    messenger.setMockMessageHandler(_adsChannel, (_) async {
      sdkCalls++;
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMessageHandler(_adsChannel, null);
    AdService.instance.ready.value = false;
  });

  test('ADS=off: init never starts the SDK or asks for consent', () async {
    await AdService.instance.init(_off);
    expect(AdService.instance.enabled, isFalse);
    expect(AdService.instance.ready.value, isFalse);
    expect(AdService.instance.rewardedReady, isFalse);
    expect(await AdService.instance.privacyOptionsRequired(), isFalse);
    expect(sdkCalls, 0);
  });

  test('ADS=off: interstitial and rewarded ads never show', () async {
    await AdService.instance.init(_off);
    await AdService.instance.maybeShowInterstitial();
    expect(await AdService.instance.showRewarded(), isFalse);
    expect(sdkCalls, 0);
  });

  testWidgets('ADS=off: BannerAdSlot shows nothing and requests nothing',
      (tester) async {
    await AdService.instance.init(_off);
    // Even if something marked ads as ready, the slot must stay empty.
    AdService.instance.ready.value = true;
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(bottomNavigationBar: BannerAdSlot()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(AdWidget), findsNothing);
    expect(tester.getSize(find.byType(BannerAdSlot)), Size.zero);
    expect(sdkCalls, 0);
  });

  test('ADS=off and ADS=false switch ads off; anything else keeps them on',
      () {
    // CI also runs this file with --dart-define=ADS=off (see ci.yml).
    const ads = String.fromEnvironment('ADS');
    expect(AdConfig.fromEnvironment().enabled, ads != 'off' && ads != 'false');
  });
}
