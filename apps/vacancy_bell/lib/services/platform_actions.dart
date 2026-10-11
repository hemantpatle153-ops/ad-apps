import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Things that leave the app: opening links and the share sheet. Behind an
/// interface so widget tests can record them.
abstract class PlatformActions {
  /// Opens [url] in the browser (or PDF viewer). False if nothing opened.
  Future<bool> openUrl(String url);
  Future<void> shareText(String text, {String? subject});
}

class RealPlatformActions implements PlatformActions {
  const RealPlatformActions();

  @override
  Future<bool> openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return false;
    }
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> shareText(String text, {String? subject}) async {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
  }
}
