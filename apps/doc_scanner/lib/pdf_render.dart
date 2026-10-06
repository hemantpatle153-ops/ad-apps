import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:printing/printing.dart';

import 'ocr.dart';
import 'pdf_tools.dart';

/// Renders PDF pages to images with the phone's built-in PDF renderer.
class PdfRender {
  PdfRender._();

  /// PNG of each page in [pages] (all pages when null).
  static Future<List<Uint8List>> pngs(Uint8List pdf,
      {List<int>? pages, double dpi = 110}) async {
    final out = <Uint8List>[];
    await for (final r in Printing.raster(pdf, pages: pages, dpi: dpi)) {
      out.add(await r.toPng());
    }
    return out;
  }

  /// One page as PNG plus its size in points (as shown, rotation applied).
  static Future<(Uint8List, double, double)> pageWithSize(Uint8List pdf, int index,
      {double dpi = 110}) async {
    await for (final r in Printing.raster(pdf, pages: [index], dpi: dpi)) {
      return (await r.toPng(), r.width * 72 / dpi, r.height * 72 / dpi);
    }
    throw RangeError.index(index, 'pages');
  }

  static Future<Uint8List> page(Uint8List pdf, int index, {double dpi = 110}) async =>
      (await pngs(pdf, pages: [index], dpi: dpi)).first;

  /// JPEG of each page (PDF to JPG).
  static Future<List<Uint8List>> jpgs(Uint8List pdf, {double dpi = 150}) async {
    final out = <Uint8List>[];
    await for (final r in Printing.raster(pdf, dpi: dpi)) {
      final im = img.Image.fromBytes(
          width: r.width,
          height: r.height,
          bytes: Uint8List.fromList(r.pixels).buffer,
          numChannels: 4);
      final flat = img.Image(width: im.width, height: im.height)
        ..clear(img.ColorRgb8(255, 255, 255));
      img.compositeImage(flat, im);
      out.add(img.encodeJpg(flat, quality: 90));
    }
    return out;
  }

  /// Turns the given pages into images so nothing under a redaction box
  /// survives in the file.
  static Future<Uint8List> flattenPages(Uint8List pdf, Iterable<int> pages,
      {double dpi = 150}) async {
    final images = <int, Uint8List>{};
    final list = pages.toList()..sort();
    var k = 0;
    await for (final r in Printing.raster(pdf, pages: list, dpi: dpi)) {
      final im = img.Image.fromBytes(
          width: r.width, height: r.height, bytes: Uint8List.fromList(r.pixels).buffer, numChannels: 4);
      final flat = img.Image(width: im.width, height: im.height)
        ..clear(img.ColorRgb8(255, 255, 255));
      img.compositeImage(flat, im);
      images[list[k++]] = img.encodeJpg(flat, quality: 88);
    }
    return PdfTools.replaceWithImages(pdf, images);
  }

  /// Strong compression: every page becomes a smaller JPEG. Text in the
  /// file stops being selectable, which the tool screen says up front.
  static Future<Uint8List> compressStrong(Uint8List pdf,
      {double dpi = 100, int quality = 55}) async {
    final images = <int, Uint8List>{};
    var i = 0;
    await for (final r in Printing.raster(pdf, dpi: dpi)) {
      final im = img.Image.fromBytes(
          width: r.width, height: r.height, bytes: Uint8List.fromList(r.pixels).buffer, numChannels: 4);
      final flat = img.Image(width: im.width, height: im.height)
        ..clear(img.ColorRgb8(255, 255, 255));
      img.compositeImage(flat, im);
      images[i++] = img.encodeJpg(flat, quality: quality);
    }
    return PdfTools.replaceWithImages(pdf, images);
  }

  /// Text of every page; pages with no text layer (scans) are read with
  /// OCR from a rendered image.
  static Future<List<String>> textWithOcr(Uint8List pdf,
      {void Function(int done, int total)? progress}) async {
    final texts = PdfTools.pageTexts(pdf);
    for (var i = 0; i < texts.length; i++) {
      progress?.call(i, texts.length);
      if (texts[i].trim().length < 3) {
        final png = await page(pdf, i, dpi: 200);
        texts[i] = (await Ocr.readBytes(png)).plain;
      }
    }
    return texts;
  }
}
