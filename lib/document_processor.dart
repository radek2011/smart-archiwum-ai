import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Safe crop for a bright document on a dark background.
/// Uses the full paper silhouette instead of the central-column estimate.
/// Does not distort pixels or apply unreliable perspective transforms.
/// Returns null when boundary detection is unsafe.
Uint8List? deskewDocument(Uint8List source) {
  final decoded = img.decodeImage(source);
  if (decoded == null) return null;
  final preview = img.copyResize(
    decoded,
    width: decoded.width >= decoded.height ? 360 : null,
    height: decoded.height > decoded.width ? 360 : null,
    interpolation: img.Interpolation.average,
  );
  final w = preview.width;
  final h = preview.height;
  if (w < 100 || h < 100) return null;

  bool lightPaper(int x, int y) {
    final p = preview.getPixel(x, y);
    final r = p.r.toDouble();
    final g = p.g.toDouble();
    final b = p.b.toDouble();
    final minValue = math.min(r, math.min(g, b));
    final maxValue = math.max(r, math.max(g, b));
    return minValue > 145 && (maxValue - minValue) < 85;
  }

  // Reject white/bright backgrounds without distinguishable page edges.
  var brightCorners = 0;
  for (final p in [
    [5, 5], [w - 6, 5], [5, h - 6], [w - 6, h - 6]
  ]) {
    if (lightPaper(p[0], p[1])) brightCorners++;
  }
  if (brightCorners >= 2) return null;

  // Each scan row contributes to the sheet outline, including the empty
  // bottom margin and handwritten notes which the old detector cropped.
  final rows = <int>[];
  final leftEdges = <int>[];
  final rightEdges = <int>[];
  for (var y = 5; y < h - 5; y++) {
    var count = 0;
    var left = w;
    var right = 0;
    for (var x = 4; x < w - 4; x += 2) {
      if (lightPaper(x, y)) {
        count++;
        if (left == w) left = x;
        right = x;
      }
    }
    // Require a sufficiently wide bright region (not just a reflection).
    if (count >= (w * .33 / 2).ceil() &&
        right - left >= (w * .42).round()) {
      rows.add(y);
      leftEdges.add(left);
      rightEdges.add(right);
    }
  }
  if (rows.length < (h * .32).round()) return null;

  // Percentiles reject individual speckles on the dark background.
  int percentile(List<int> input, double fraction) {
    final ordered = List<int>.from(input)..sort();
    return ordered[((ordered.length - 1) * fraction).floor()];
  }

  var top = percentile(rows, .005);
  var bottom = percentile(rows, .995);
  var left = percentile(leftEdges, .02);
  var right = percentile(rightEdges, .98);

  // Broad safety margin guarantees preservation of handwriting along edges.
  final horizontalMargin = math.max(6, (w * .025).round());
  final verticalMargin = math.max(6, (h * .025).round());
  left = math.max(0, left - horizontalMargin);
  right = math.min(w - 1, right + horizontalMargin);
  top = math.max(0, top - verticalMargin);
  bottom = math.min(h - 1, bottom + verticalMargin);

  final cropW = right - left + 1;
  final cropH = bottom - top + 1;
  if (cropW < w * .40 || cropH < h * .35) return null;

  // Reject accidental detection of almost the whole photo or tiny pieces.
  if (cropW / w > .985 && cropH / h > .985) return null;

  final x0 = (left * decoded.width / w).floor().clamp(0, decoded.width - 1);
  final y0 = (top * decoded.height / h).floor().clamp(0, decoded.height - 1);
  final x1 = ((right + 1) * decoded.width / w).ceil()
      .clamp(x0 + 1, decoded.width);
  final y1 = ((bottom + 1) * decoded.height / h).ceil()
      .clamp(y0 + 1, decoded.height);
  final cropped = img.copyCrop(decoded,
    x: x0, y: y0, width: x1 - x0, height: y1 - y0);

  // Preserve details and previously validated image quality.
  return Uint8List.fromList(img.encodeJpg(cropped, quality: 90));
}
