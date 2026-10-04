import 'package:url_launcher/url_launcher.dart';

/// Opens a link in the browser (privacy policy, store page).
Future<void> openLink(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// Opens this app's Play Store page so the user can leave a rating.
Future<void> openStorePage(String packageName) =>
    openLink('https://play.google.com/store/apps/details?id=$packageName');
