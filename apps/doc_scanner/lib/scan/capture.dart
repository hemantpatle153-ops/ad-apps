import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'edge_detect.dart';
import 'geometry.dart';

/// Where a cropped page came from, so its crop can be changed later.
class PageSource {
  const PageSource(this.original, this.quad);
  final String original;
  final Quad quad;
}

/// Cropped page path -> original photo and the corners used.
final pageSources = <String, PageSource>{};

/// Result of processing one camera shot.
class Captured {
  const Captured(this.jpeg, this.quad, this.found);
  final Uint8List jpeg;
  final Quad quad;

  /// False when no page was found and [quad] is just a guess.
  final bool found;
}

/// Finds the page in a photo and flattens it. [hint] (e.g. the outline
/// shown live) is used when the photo itself gives no clear page; with
/// neither, the whole photo is kept. Top-level so it can run in an isolate.
Captured processCapture((Uint8List, Quad?, bool) a) {
  final (bytes, hint, crop) = a;
  final src = img.decodeImage(bytes);
  if (src == null) throw const FormatException('Not an image.');
  final up = img.bakeOrientation(src);
  if (!crop) {
    return Captured(_limit(up), Quad.full, false);
  }
  final small = up.width > up.height
      ? img.copyResize(up, width: 360)
      : img.copyResize(up, height: 360);
  final found = detectDocument(Luma.fromImage(small));
  final quad = found ?? hint ?? Quad.full;
  if (identical(quad, Quad.full)) return Captured(_limit(up), quad, false);
  return Captured(
      img.encodeJpg(warpPerspective(up, quad), quality: 92), quad, found != null);
}

/// Re-crops a photo with corners the user placed by hand.
Uint8List recropJob((Uint8List, Quad) a) => cropDocument(a.$1, a.$2);

/// Detects the page in a photo (for the crop editor's "Auto" button).
Quad? detectPhotoJob(Uint8List bytes) => detectInPhoto(bytes);

/// Detects the page in a small live frame.
Quad? detectFrameJob(Luma frame) => detectDocument(frame);

Uint8List _limit(img.Image up, {int maxSide = 2600}) {
  var im = up;
  if (im.width > maxSide || im.height > maxSide) {
    im = im.width >= im.height
        ? img.copyResize(im, width: maxSide)
        : img.copyResize(im, height: maxSide);
  }
  return img.encodeJpg(im, quality: 92);
}

/// Samples a camera's luminance plane down to about [target] pixels on the
/// long side (nearest neighbour; detection blurs anyway).
Luma sampleLuma(Uint8List y, int width, int height, int stride, {int target = 200}) {
  final step = (width > height ? width : height) / target;
  if (step <= 1) return Luma(y, width, height, stride);
  final w = (width / step).floor(), h = (height / step).floor();
  final out = Uint8List(w * h);
  for (var j = 0; j < h; j++) {
    final row = (j * step).floor() * stride;
    for (var i = 0; i < w; i++) {
      out[j * w + i] = y[row + (i * step).floor()];
    }
  }
  return Luma(out, w, h);
}
