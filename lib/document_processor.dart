import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Experimental document detector for a bright sheet against a darker,
/// contrasting background. It never overwrites the original scan.
/// Returns null when the boundary is uncertain.
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
  if (w < 60 || h < 60) return null;

  bool isPaper(int x, int y) {
    final p = preview.getPixel(x, y);
    final r = p.r.toDouble();
    final g = p.g.toDouble();
    final b = p.b.toDouble();
    final minChannel = math.min(r, math.min(g, b));
    final maxChannel = math.max(r, math.max(g, b));
    return minChannel > 155 && maxChannel - minChannel < 65;
  }

  // Reject light backgrounds where the paper boundary is ambiguous.
  var cornersBright = 0;
  for (final point in [[8, 8], [w - 9, 8], [8, h - 9], [w - 9, h - 9]]) {
    if (isPaper(point[0], point[1])) cornersBright++;
  }
  if (cornersBright >= 2) return null;

  final cx = w ~/ 2;
  int? top;
  int? bottom;
  // Require runs to avoid mistaking bright lettering and reflections for paper.
  for (var y = 5; y < h - 5; y++) {
    if (List.generate(7, (i) => isPaper(cx, y + i - 3))
        .where((v) => v).length >= 5) {
      top = y;
      break;
    }
  }
  for (var y = h - 6; y >= 5; y--) {
    if (List.generate(7, (i) => isPaper(cx, y + i - 3))
        .where((v) => v).length >= 5) {
      bottom = y;
      break;
    }
  }
  if (top == null || bottom == null || bottom - top < h * .32) return null;

  // Measure left/right margins at upper and lower portions of the sheet.
  (double, double)? span(int y) {
    int? left;
    int? right;
    for (var x = 4; x < w - 4; x++) {
      if (isPaper(x, y) && isPaper(x + 2, y) && isPaper(x + 4, y)) {
        left = x;
        break;
      }
    }
    for (var x = w - 5; x >= 4; x--) {
      if (isPaper(x, y) && isPaper(x - 2, y) && isPaper(x - 4, y)) {
        right = x;
        break;
      }
    }
    if (left == null || right == null || right - left < w * .30) return null;
    return (left.toDouble(), right.toDouble());
  }

  final upperY = (top + (bottom - top) * .16).round();
  final lowerY = (top + (bottom - top) * .84).round();
  final upper = span(upperY);
  final lower = span(lowerY);
  if (upper == null || lower == null) return null;

  final widthFrac = ((upper.$2 - upper.$1) +
      (lower.$2 - lower.$1)) / (2 * w);
  final heightFrac = (bottom - top) / h;
  if (widthFrac < .35 || heightFrac < .32) return null;

  // Preserve useful document detail while limiting mobile-browser memory.
  const longEdge = 2400;
  final ratio = ((widthFrac * decoded.width) /
      (heightFrac * decoded.height)).clamp(.35, 2.6).toDouble();
  final outputWidth = ratio >= 1 ? longEdge : (longEdge * ratio).round();
  final outputHeight = ratio >= 1 ? (longEdge / ratio).round() : longEdge;
  final output = img.Image(width: outputWidth, height: outputHeight);
  final topLeft = upper.$1 / w * decoded.width;
  final topRight = upper.$2 / w * decoded.width;
  final bottomLeft = lower.$1 / w * decoded.width;
  final bottomRight = lower.$2 / w * decoded.width;
  final firstY = top / h * decoded.height;
  final lastY = bottom / h * decoded.height;

  // Trapezoidal perspective approximation. Fully projective correction and
  // manual corner positioning are planned for the next imaging iteration.
  for (var y = 0; y < outputHeight; y++) {
    final v = (y + .5) / outputHeight;
    final left = topLeft * (1 - v) + bottomLeft * v;
    final right = topRight * (1 - v) + bottomRight * v;
    final sy = (firstY + (lastY - firstY) * v).round()
        .clamp(0, decoded.height - 1).toInt();
    for (var x = 0; x < outputWidth; x++) {
      final u = (x + .5) / outputWidth;
      final sx = (left + (right - left) * u).round()
          .clamp(0, decoded.width - 1).toInt();
      final pixel = decoded.getPixel(sx, sy);
      output.setPixelRgb(x, y, pixel.r, pixel.g, pixel.b);
    }
  }
  return Uint8List.fromList(img.encodeJpg(output, quality: 90));
}
