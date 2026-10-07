import 'dart:typed_data';

import 'package:doc_scanner/image_filters.dart';
import 'package:doc_scanner/review_screen.dart';
import 'package:doc_scanner/scan/capture.dart';
import 'package:doc_scanner/scan/geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('a capture without cropping keeps the whole photo', () {
    final photo = img.fill(img.Image(width: 300, height: 200), color: img.ColorRgb8(90, 90, 90));
    final res = processCapture((Uint8List.fromList(img.encodeJpg(photo)), null, false));
    final out = img.decodeJpg(res.jpeg)!;
    expect([out.width, out.height], [300, 200]);
    expect(res.quad, Quad.full);
  });

  test('document scans default to Magic color, photos to Original', () {
    pageSources['/doc.jpg'] = const PageSource('/o1.jpg', Quad.full, enhance: true);
    pageSources['/photo.jpg'] = const PageSource('/o2.jpg', Quad.full);
    expect(ScanPage('/doc.jpg').filter, PageFilter.magic);
    expect(ScanPage('/photo.jpg').filter, PageFilter.original);
    expect(ScanPage('/imported.jpg').filter, PageFilter.original);
  });
}
