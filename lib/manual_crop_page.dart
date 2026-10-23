import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class ManualCropPage extends StatefulWidget {
  const ManualCropPage({super.key, required this.source});
  final Uint8List source;
  @override
  State<ManualCropPage> createState() => _ManualCropPageState();
}

class _ManualCropPageState extends State<ManualCropPage> {
  // TL, TR, BR, BL normalized to displayed image.
  List<Offset> corners = [
    const Offset(.06, .06), const Offset(.94, .06),
    const Offset(.94, .94), const Offset(.06, .94),
  ];
  bool working = false;
  int? _draggedCorner;
  String? error;
  static const accent = Color(0xFFF36B21);
  Size? _imageSize;

  @override
  void initState() {
    super.initState();
    final decoded = img.decodeImage(widget.source);
    if (decoded != null) _imageSize = Size(
        decoded.width.toDouble(), decoded.height.toDouble());
  }

  void _move(Offset local, Size size, {bool start = false}) {
    final pos = Offset(
      (local.dx / size.width).clamp(0.0, 1.0),
      (local.dy / size.height).clamp(0.0, 1.0),
    );
    if (start) {
      var nearest = 0;
      var distance = double.infinity;
      for (var i = 0; i < corners.length; i++) {
        final d = (corners[i] - pos).distanceSquared;
        if (d < distance) { nearest = i; distance = d; }
      }
      if (distance > .045) { _draggedCorner = null; return; }
      _draggedCorner = nearest;
    }
    if (_draggedCorner == null) return;
    setState(() => corners[_draggedCorner!] = pos);
  }

  Future<void> _apply() async {
    if (working) return;
    setState(() { working = true; error = null; });
    try {
      final result = _rectify(widget.source, corners);
      if (!mounted) return;
      if (result == null) {
        setState(() {
          working = false;
          error = 'Narożniki nachodzą na siebie albo pole jest zbyt małe.';
        });
        return;
      }
      Navigator.of(context).pop(result);
    } catch (_) {
      if (mounted) setState(() {
        working = false;
        error = 'Nie udało się wyciąć obrazu. Spróbuj zmienić narożniki.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageSize = _imageSize;
    return Scaffold(
      appBar: AppBar(title: const Text('Ręczne kadrowanie')),
      body: SafeArea(child: Column(children: [
        const Padding(padding: EdgeInsets.all(12),
          child: Text('Przeciągnij cztery pomarańczowe punkty na narożniki kartki. '
            'Pozostaw niewielki margines, aby nie obciąć tekstu.',
            textAlign: TextAlign.center)),
        Expanded(child: LayoutBuilder(builder: (context, constraints) {
          if (imageSize == null) return const Center(child: Text('Błąd zdjęcia'));
          final scale = math.min(constraints.maxWidth / imageSize.width,
              constraints.maxHeight / imageSize.height);
          final size = Size(imageSize.width * scale, imageSize.height * scale);
          return Center(child: SizedBox(
            width: size.width, height: size.height,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) => _move(d.localPosition, size, start: true),
              onPanUpdate: (d) => _move(d.localPosition, size),
              onPanEnd: (_) => _draggedCorner = null,
              onTapDown: (d) {
                _move(d.localPosition, size, start: true);
                _draggedCorner = null;
              },
              child: Stack(fit: StackFit.expand, children: [
                Image.memory(widget.source, fit: BoxFit.fill,
                  gaplessPlayback: true),
                CustomPaint(painter: _CornersPainter(corners)),
              ]),
            ),
          ));
        })),
        if (error != null) Padding(padding: const EdgeInsets.all(8),
          child: Text(error!, style: const TextStyle(color: Colors.red))),
        if (working) const LinearProgressIndicator(),
        Padding(padding: const EdgeInsets.all(12), child: Row(children: [
          OutlinedButton(
            onPressed: working ? null : () => setState(() {
              corners = [
                const Offset(.06,.06), const Offset(.94,.06),
                const Offset(.94,.94), const Offset(.06,.94),
              ];
            }), child: const Text('Resetuj')),
          const SizedBox(width: 10),
          Expanded(child: FilledButton.icon(
            onPressed: working || imageSize == null ? null : _apply,
            icon: const Icon(Icons.crop),
            label: const Text('Podgląd korekty'),
            style: FilledButton.styleFrom(backgroundColor: accent),
          )),
        ])),
      ])),
    );
  }
}

class _CornersPainter extends CustomPainter {
  const _CornersPainter(this.points);
  final List<Offset> points;
  @override
  void paint(Canvas canvas, Size size) {
    final mapped = points.map((p) =>
        Offset(p.dx * size.width, p.dy * size.height)).toList();
    final polygon = Path()..moveTo(mapped[0].dx, mapped[0].dy);
    for (var i = 1; i < 4; i++) { polygon.lineTo(mapped[i].dx, mapped[i].dy); }
    polygon.close();
    final fill = Paint()..color = const Color(0x22F36B21);
    canvas.drawPath(polygon, fill);
    canvas.drawPath(polygon, Paint()
      ..color = const Color(0xFFF36B21)
      ..strokeWidth = 3..style = PaintingStyle.stroke);
    for (final p in mapped) {
      canvas.drawCircle(p, 11, Paint()..color = Colors.white);
      canvas.drawCircle(p, 8, Paint()..color = const Color(0xFFF36B21));
    }
  }
  @override
  bool shouldRepaint(covariant _CornersPainter old) => true;
}

/// Inverse projective mapping from output rectangle to four image corners.
/// Keeps the saved original intact; only the accepted variant is used for PDF.
Uint8List? _rectify(Uint8List data, List<Offset> normalized) {
  final source = img.decodeImage(data);
  if (source == null) return null;
  final pts = normalized.map((p) => Offset(
    p.dx * source.width, p.dy * source.height)).toList();
  final top = (pts[1] - pts[0]).distance;
  final bottom = (pts[2] - pts[3]).distance;
  final left = (pts[3] - pts[0]).distance;
  final right = (pts[2] - pts[1]).distance;
  if ([top,bottom,left,right].any((n) => n < 80)) return null;
  // Reject crossing and concave quadrilaterals.
  double cross(Offset a, Offset b) => a.dx*b.dy-a.dy*b.dx;
  final signs = List.generate(4, (i) => cross(
    pts[(i+1)%4]-pts[i], pts[(i+2)%4]-pts[(i+1)%4]));
  if (signs.any((v) => v <= 0)) return null;
  const maxEdge = 2200.0;
  final aspect = ((top + bottom) / (left + right)).clamp(.3, 3.0);
  final width = (aspect >= 1 ? maxEdge : maxEdge * aspect).round();
  final height = (aspect >= 1 ? maxEdge / aspect : maxEdge).round();
  if (width < 150 || height < 150) return null;

  // Compute projective transform of unit square to image quadrilateral.
  final dx1 = pts[1].dx-pts[2].dx;
  final dx2 = pts[3].dx-pts[2].dx;
  final dx3 = pts[0].dx-pts[1].dx+pts[2].dx-pts[3].dx;
  final dy1 = pts[1].dy-pts[2].dy;
  final dy2 = pts[3].dy-pts[2].dy;
  final dy3 = pts[0].dy-pts[1].dy+pts[2].dy-pts[3].dy;
  final determinant = dx1*dy2-dx2*dy1;
  if (determinant.abs() < 1e-5) return null;
  final g = (dx3*dy2-dx2*dy3)/determinant;
  final h = (dx1*dy3-dx3*dy1)/determinant;
  final a = pts[1].dx-pts[0].dx+g*pts[1].dx;
  final b = pts[3].dx-pts[0].dx+h*pts[3].dx;
  final c = pts[0].dx;
  final d = pts[1].dy-pts[0].dy+g*pts[1].dy;
  final e = pts[3].dy-pts[0].dy+h*pts[3].dy;
  final f = pts[0].dy;

  final out = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    final v = (y+.5)/height;
    for (var x = 0; x < width; x++) {
      final u = (x+.5)/width;
      final denominator = g*u+h*v+1;
      if (denominator.abs()<1e-6) return null;
      final sx = ((a*u+b*v+c)/denominator).round()
          .clamp(0,source.width-1).toInt();
      final sy = ((d*u+e*v+f)/denominator).round()
          .clamp(0,source.height-1).toInt();
      final pixel = source.getPixel(sx,sy);
      out.setPixelRgb(x,y,pixel.r,pixel.g,pixel.b);
    }
  }
  return Uint8List.fromList(img.encodeJpg(out, quality: 90));
}
