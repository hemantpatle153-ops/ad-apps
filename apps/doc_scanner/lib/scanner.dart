import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'scan/camera_scan_screen.dart';

/// Opens the app's own document camera (live edge detection, auto-crop,
/// auto-capture). Returns cropped JPEG page paths, empty if cancelled.
/// Everything runs inside the app; no Google Play services scanner.
Future<List<String>> scanPages(BuildContext context,
    {int pageLimit = 50, String? title}) async {
  final pages = await Navigator.of(context).push<List<String>>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CameraScanScreen(pageLimit: pageLimit, title: title),
    ),
  );
  return pages ?? const [];
}

/// Picks existing photos to turn into PDF pages.
Future<List<String>> pickFromGallery() async {
  final files = await ImagePicker().pickMultiImage(imageQuality: 90);
  return [for (final f in files) f.path];
}

/// Takes plain photos (no cropping) with the in-app camera.
Future<List<String>> takePhotos(BuildContext context) async {
  final pages = await Navigator.of(context).push<List<String>>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const CameraScanScreen(mode: ScanMode.photo),
    ),
  );
  return pages ?? const [];
}
