import 'package:flutter/material.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image_picker/image_picker.dart';

/// Opens the on-device document scanner (edge detection, crop, rotate and
/// filters all run on the phone). Returns JPEG page paths, empty if cancelled.
Future<List<String>> scanPages(BuildContext context, {int pageLimit = 50}) async {
  final scanner = DocumentScanner(
    options: DocumentScannerOptions(
      documentFormats: const {DocumentFormat.jpeg},
      mode: ScannerMode.full,
      isGalleryImport: true,
      pageLimit: pageLimit,
    ),
  );
  try {
    final result = await scanner.scanDocument();
    return result.images ?? const [];
  } catch (e) {
    // Cancelled by the user, or the scanner module isn't available on this
    // phone (no Google Play services). Offer the gallery instead.
    if (e.toString().toLowerCase().contains('cancel')) return const [];
    if (!context.mounted) return const [];
    final useGallery = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Scanner unavailable'),
        content: const Text(
            'The camera scanner could not start on this phone. Pick photos from your gallery instead?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Pick photos')),
        ],
      ),
    );
    return useGallery == true ? pickFromGallery() : const [];
  } finally {
    scanner.close();
  }
}

/// Picks existing photos to turn into PDF pages.
Future<List<String>> pickFromGallery() async {
  final files = await ImagePicker().pickMultiImage(imageQuality: 85);
  return [for (final f in files) f.path];
}

/// Takes plain photos with the camera (no cropping), one after another
/// until the user stops. Returns the photo paths.
Future<List<String>> takePhotos(BuildContext context) async {
  final picker = ImagePicker();
  final paths = <String>[];
  while (true) {
    final shot =
        await picker.pickImage(source: ImageSource.camera, imageQuality: 90);
    if (shot == null) break;
    paths.add(shot.path);
    if (!context.mounted) break;
    final again = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${paths.length} photo${paths.length == 1 ? '' : 's'} taken'),
        content: const Text('Take another photo?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Done')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Take another')),
        ],
      ),
    );
    if (again != true) break;
  }
  return paths;
}
