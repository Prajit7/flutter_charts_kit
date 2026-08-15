import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'geometry.dart';

class Surface3DPainter extends CustomPainter {
  final List<List<double>> data;
  final List<String> xLabels;
  final List<String> yLabels;
  final String xAxisTitle;
  final String yAxisTitle;
  final String zAxisTitle;
  final String Function(double value) valueFormatter;
  final List<Color> gradient;
  final double? fixedMin;
  final double? fixedMax;
  final double spacing;
  final double zScale;
  final Projector projector;
  final SurfaceQuad? highlightedQuad;

  /// Optional vertical reference line (e.g. "current price", "today") drawn
  /// through a specific column index, with a label at the top.
  final int? referenceColIndex;
  final String? referenceLabel;

  Surface3DPainter({
    required this.data,
    required this.xLabels,
    required this.yLabels,
    required this.xAxisTitle,
    required this.yAxisTitle,
    required this.zAxisTitle,
    required this.valueFormatter,
    required this.gradient,
    required this.spacing,
    required this.zScale,
    required this.projector,
    this.fixedMin,
    this.fixedMax,
    this.highlightedQuad,
    this.referenceColIndex,
    this.referenceLabel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = SurfaceGeometry(
      data: data,
      spacing: spacing,
      zScale: zScale,
      projector: projector,
    );
    final quads = geometry.buildQuads();

    double minV, maxV;
    if (fixedMin != null && fixedMax != null) {
      minV = fixedMin!;
      maxV = fixedMax!;
    } else {
      minV = double.infinity;
      maxV = -double.infinity;
      for (final row in data) {
        for (final v in row) {
          if (v < minV) minV = v;
          if (v > maxV) maxV = v;
        }
      }
    }

    _drawFloorGrid(canvas, geometry);
    if (referenceColIndex != null) {
      _drawReferenceLine(canvas, referenceColIndex!);
    }

    final fill = Paint()..style = PaintingStyle.fill;
    final mesh = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.white.withOpacity(0.7);
    final highlightStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = Colors.black87;

    for (final q in quads) {
      final t = maxV == minV ? 0.5 : (q.value - minV) / (maxV - minV);
      fill.color = _gradientColor(t.clamp(0.0, 1.0));
      canvas.drawPath(q.path, fill);
      canvas.drawPath(q.path, mesh);
    }

    if (highlightedQuad != null) {
      canvas.drawPath(highlightedQuad!.path, highlightStroke);
    }

    _drawAxes(canvas, minV, maxV);
  }

  Color _gradientColor(double t) {
    final scaled = t * (gradient.length - 1);
    final idx = scaled.floor().clamp(0, gradient.length - 2);
    final frac = scaled - idx;
    return Color.lerp(gradient[idx], gradient[idx + 1], frac)!;
  }

  void _drawFloorGrid(Canvas canvas, SurfaceGeometry geometry) {
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = Colors.grey.withOpacity(0.25);

    final rows = data.length;
    final cols = data[0].length;

    for (int r = 0; r < rows; r++) {
      final p1 = Point3D((0 - cols / 2) * spacing, (r - rows / 2) * spacing, 0);
      final p2 = Point3D((cols - 1 - cols / 2) * spacing, (r - rows / 2) * spacing, 0);
      _drawDashedLine(canvas, projector.project(p1), projector.project(p2), gridPaint);
    }
    for (int c = 0; c < cols; c++) {
      final p1 = Point3D((c - cols / 2) * spacing, (0 - rows / 2) * spacing, 0);
      final p2 = Point3D((c - cols / 2) * spacing, (rows - 1 - rows / 2) * spacing, 0);
      _drawDashedLine(canvas, projector.project(p1), projector.project(p2), gridPaint);
    }
  }

  void _drawReferenceLine(Canvas canvas, int colIndex) {
    final rows = data.length;
    final cols = data[0].length;
    final x = (colIndex - cols / 2) * spacing;

    final top = Point3D(x, (0 - rows / 2) * spacing, 160);
    final bottom = Point3D(x, (rows - 1 - rows / 2) * spacing, 0);

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.black45;

    _drawDashedLine(canvas, projector.project(top), projector.project(bottom), linePaint);

    if (referenceLabel != null) {
      final labelPos = projector.project(Point3D(x, (0 - rows / 2) * spacing, 175));
      _drawText(canvas, referenceLabel!, Offset(labelPos.dx - 40, labelPos.dy - 14),
          Colors.black87, size: 11);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dashLength = 4.0;
    const gapLength = 3.0;
    final total = (b - a).distance;
    if (total == 0) return;
    final direction = (b - a) / total;
    double drawn = 0;
    while (drawn < total) {
      final segEnd = math.min(drawn + dashLength, total);
      canvas.drawLine(a + direction * drawn, a + direction * segEnd, paint);
      drawn += dashLength + gapLength;
    }
  }

  void _drawAxes(Canvas canvas, double minV, double maxV) {
    final axisPaint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 1.4;
    final tickPaint = Paint()
      ..color = Colors.grey.shade500
      ..strokeWidth = 1;

    final rows = data.length;
    final cols = data[0].length;

    final origin = Point3D((0 - cols / 2) * spacing - spacing * 0.6,
        (rows - 1 - rows / 2) * spacing + spacing * 0.6, 0);
    final o = projector.project(origin);

    // ---------------- X AXIS ----------------
    final xEnd = Point3D(origin.x + (cols + 0.6) * spacing, origin.y, 0);
    canvas.drawLine(o, projector.project(xEnd), axisPaint);

    for (int c = 0; c < cols; c++) {
      final p = projector.project(
        Point3D(origin.x + spacing * 0.6 + c * spacing, origin.y, 0),
      );
      canvas.drawLine(Offset(p.dx, p.dy - 4), Offset(p.dx, p.dy + 4), tickPaint);
      if (c % _labelStride(cols) == 0) {
        _drawText(canvas, xLabels[c], Offset(p.dx - 18, p.dy + 8), Colors.black54, size: 10);
      }
    }
    final xEndProj = projector.project(xEnd);
    _drawText(canvas, xAxisTitle, Offset(xEndProj.dx - 10, xEndProj.dy + 20),
        Colors.black87, size: 13);

    // ---------------- Y AXIS ----------------
    final yEnd = Point3D(origin.x, origin.y - (rows + 0.6) * spacing, 0);
    canvas.drawLine(o, projector.project(yEnd), axisPaint);

    for (int r = 0; r < rows; r++) {
      final p = projector.project(
        Point3D(origin.x, origin.y - spacing * 0.6 - r * spacing, 0),
      );
      canvas.drawLine(Offset(p.dx - 4, p.dy), Offset(p.dx + 4, p.dy), tickPaint);
      _drawText(canvas, yLabels[r], Offset(p.dx - 60, p.dy - 4), Colors.black54, size: 10);
    }
    final yEndProj = projector.project(yEnd);
    _drawText(canvas, yAxisTitle, Offset(yEndProj.dx - 60, yEndProj.dy - 16),
        Colors.black87, size: 13);

    // ---------------- Z AXIS ----------------
    final zEnd = Point3D(origin.x, origin.y, 160);
    canvas.drawLine(o, projector.project(zEnd), axisPaint);

    const levels = 5;
    for (int i = 0; i <= levels; i++) {
      final frac = i / levels;
      final z = frac * 160;
      final value = minV + frac * (maxV - minV);
      final p = projector.project(Point3D(origin.x, origin.y, z));
      canvas.drawLine(Offset(p.dx - 4, p.dy), Offset(p.dx + 4, p.dy), tickPaint);
      _drawText(canvas, valueFormatter(value), Offset(p.dx - 46, p.dy - 4),
          Colors.black54, size: 10);
    }
    final zEndProj = projector.project(zEnd);
    _drawText(canvas, zAxisTitle, Offset(zEndProj.dx - 10, zEndProj.dy - 18),
        Colors.black87, size: 13);
  }

  /// Skip labels if there are too many columns to fit legibly.
  int _labelStride(int cols) => cols > 12 ? 2 : 1;

  void _drawText(Canvas canvas, String text, Offset position, Color color, {double size = 12}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    painter.paint(canvas, position);
  }

  @override
  bool shouldRepaint(covariant Surface3DPainter oldDelegate) => true;
}
