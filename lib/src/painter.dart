import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'geometry.dart';
import 'grid_axes3d.dart';
import 'chart2d/common.dart';
import 'chart2d/theme.dart';

/// How [Surface3DChart] draws its surface.
enum SurfaceRenderMode {
  /// Filled tiles colored by value, with a light mesh.
  solid,

  /// Only the mesh lines, colored by value — see-through, so nothing hides
  /// behind peaks.
  wireframe,
}

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

  /// Colors and fonts for the axes, labels, and floor grid. The surface
  /// itself is always colored by [gradient].
  final ChartTheme theme;

  /// Optional vertical reference line (e.g. "current price", "today") drawn
  /// through a specific column index, with a label at the top.
  final int? referenceColIndex;
  final String? referenceLabel;

  final SurfaceRenderMode renderMode;

  /// Draw contour lines (lines of equal value) projected onto the floor.
  final bool showContours;
  final int contourLevels;

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
    this.theme = ChartTheme.light,
    this.referenceColIndex,
    this.referenceLabel,
    this.renderMode = SurfaceRenderMode.solid,
    this.showContours = false,
    this.contourLevels = 8,
  });

  (double, double) get _range {
    if (fixedMin != null && fixedMax != null) return (fixedMin!, fixedMax!);
    double lo = double.infinity, hi = -double.infinity;
    for (final row in data) {
      for (final v in row) {
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
    return (lo, hi);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final quads = SurfaceGeometry(data: data, spacing: spacing, zScale: zScale, projector: projector).buildQuads();
    final (minV, maxV) = _range;
    final axes = GridAxes3D(
      rows: data.length,
      cols: data[0].length,
      spacing: spacing,
      zScale: zScale,
      projector: projector,
      theme: theme,
      xLabels: xLabels,
      yLabels: yLabels,
      xAxisTitle: xAxisTitle,
      yAxisTitle: yAxisTitle,
      zAxisTitle: zAxisTitle,
      valueFormatter: valueFormatter,
      minValue: minV,
      maxValue: maxV,
    );

    axes.drawFloor(canvas);
    axes.drawBackAxis(canvas);
    if (showContours) _drawContours(canvas, axes, minV, maxV);
    if (referenceColIndex != null) axes.drawReferenceColumn(canvas, referenceColIndex!, referenceLabel);

    Color colorFor(double v) => sampleGradient(gradient, maxV == minV ? 0.5 : (v - minV) / (maxV - minV));
    if (renderMode == SurfaceRenderMode.solid) {
      final fill = Paint()..style = PaintingStyle.fill;
      final mesh = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.white.withValues(alpha: 0.7);
      for (final q in quads) {
        fill.color = colorFor(q.value);
        canvas.drawPath(q.path, fill);
        canvas.drawPath(q.path, mesh);
      }
    } else {
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      for (final q in quads) {
        line.color = colorFor(q.value);
        canvas.drawPath(q.path, line);
      }
    }

    if (highlightedQuad != null) {
      canvas.drawPath(
        highlightedQuad!.path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = theme.axisColor,
      );
    }

    axes.drawFrontAxes(canvas);
  }

  /// Contour lines on the floor via marching squares over each grid cell.
  void _drawContours(Canvas canvas, GridAxes3D axes, double minV, double maxV) {
    if (maxV <= minV || data.length < 2 || data[0].length < 2) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    Offset project(double c, double r) => projector.project(Point3D(axes.colX(c), axes.rowY(r), 0));

    for (int k = 1; k <= contourLevels; k++) {
      final t = k / (contourLevels + 1);
      final level = minV + t * (maxV - minV);
      paint.color = sampleGradient(gradient, t).withValues(alpha: 0.9);
      for (final (a, b) in contourSegments(data, level)) {
        canvas.drawLine(project(a.dx, a.dy), project(b.dx, b.dy), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant Surface3DPainter oldDelegate) => true;
}

/// Line segments where `data[row][col]` crosses [level], in grid
/// coordinates `(col, row)` — one marching-squares pass over every cell.
List<(Offset, Offset)> contourSegments(List<List<double>> data, double level) {
  final segments = <(Offset, Offset)>[];
  for (int r = 0; r < data.length - 1; r++) {
    for (int c = 0; c < data[r].length - 1 && c < data[r + 1].length - 1; c++) {
      final tl = data[r][c], tr = data[r][c + 1], br = data[r + 1][c + 1], bl = data[r + 1][c];
      final pts = <Offset>[];
      // Edges in order: top, right, bottom, left.
      void edge(double a, double b, Offset from, Offset to) {
        if ((a < level) == (b < level) || a == b) return;
        final f = (level - a) / (b - a);
        pts.add(Offset.lerp(from, to, f)!);
      }

      final c0 = c.toDouble(), r0 = r.toDouble();
      edge(tl, tr, Offset(c0, r0), Offset(c0 + 1, r0));
      edge(tr, br, Offset(c0 + 1, r0), Offset(c0 + 1, r0 + 1));
      edge(bl, br, Offset(c0, r0 + 1), Offset(c0 + 1, r0 + 1));
      edge(tl, bl, Offset(c0, r0), Offset(c0, r0 + 1));
      if (pts.length == 2) {
        segments.add((pts[0], pts[1]));
      } else if (pts.length == 4) {
        // Saddle: pair crossings so the cell's centre value decides which
        // corners are connected.
        final centreAbove = (tl + tr + br + bl) / 4 >= level;
        final tlAbove = tl >= level;
        if (centreAbove == tlAbove) {
          segments.add((pts[0], pts[1]));
          segments.add((pts[2], pts[3]));
        } else {
          segments.add((pts[0], pts[3]));
          segments.add((pts[1], pts[2]));
        }
      }
    }
  }
  return segments;
}
