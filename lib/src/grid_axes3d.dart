import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'geometry.dart';
import 'chart2d/cartesian_axes.dart';
import 'chart2d/common.dart';
import 'chart2d/theme.dart';

/// Floor grid and labelled axes for a 3D chart, in model space.
///
/// The floor spans `[xMin, xMax] × [yMin, yMax]` at height 0. The x and y
/// axes run along whichever floor edges face the viewer (re-chosen at every
/// angle, so labels never hide behind the data); the vertical axis stands
/// at the back corner. Draw [drawFloor] and [drawBackAxis] before the data
/// and [drawFrontAxes] after it.
class Axes3D {
  final Projector projector;
  final ChartTheme theme;
  final double xMin;
  final double xMax;
  final double yMin;
  final double yMax;

  /// Vertical axis extent.
  final double zMin;
  final double zMax;

  /// Tick positions (model units) and their labels.
  final List<(double, String)> xTicks;
  final List<(double, String)> yTicks;
  final List<(double, String)> zTicks;

  /// Where to draw floor grid lines (model units).
  final List<double> floorXLines;
  final List<double> floorYLines;
  final String xAxisTitle;
  final String yAxisTitle;
  final String zAxisTitle;

  const Axes3D({
    required this.projector,
    required this.theme,
    required this.xMin,
    required this.xMax,
    required this.yMin,
    required this.yMax,
    required this.zMin,
    required this.zMax,
    required this.xTicks,
    required this.yTicks,
    required this.zTicks,
    required this.floorXLines,
    required this.floorYLines,
    this.xAxisTitle = '',
    this.yAxisTitle = '',
    this.zAxisTitle = '',
  });

  double _depth(double x, double y, double z) => projector.rotate(Point3D(x, y, z)).z;

  /// The floor edges nearest the viewer.
  double get _frontY => _depth(0, yMin, 0) > _depth(0, yMax, 0) ? yMin : yMax;
  double get _frontX => _depth(xMin, 0, 0) > _depth(xMax, 0, 0) ? xMin : xMax;

  /// The floor corner farthest from the viewer.
  (double, double) get _backCorner => (_frontX == xMin ? xMax : xMin, _frontY == yMin ? yMax : yMin);

  Offset get _floorCenter => projector.project(Point3D((xMin + xMax) / 2, (yMin + yMax) / 2, 0));

  /// Unit screen direction from the floor's centre toward [p] — labels are
  /// pushed this way so they sit outside the grid.
  Offset _outward(Offset p) {
    final d = p - _floorCenter;
    return d.distance == 0 ? const Offset(0, 1) : d / d.distance;
  }

  /// Dashed floor grid lines.
  void drawFloor(Canvas canvas) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = theme.gridColor;
    for (final y in floorYLines) {
      dashedLine(canvas, projector.project(Point3D(xMin, y, 0)), projector.project(Point3D(xMax, y, 0)), paint);
    }
    for (final x in floorXLines) {
      dashedLine(canvas, projector.project(Point3D(x, yMin, 0)), projector.project(Point3D(x, yMax, 0)), paint);
    }
  }

  /// The vertical axis line and ticks, at the back corner. Draw before the
  /// data so the data can pass in front of it; its labels are drawn by
  /// [drawFrontAxes], on top, so they stay readable.
  void drawBackAxis(Canvas canvas) {
    final (bx, by) = _backCorner;
    canvas.drawLine(
      projector.project(Point3D(bx, by, zMin)),
      projector.project(Point3D(bx, by, zMax)),
      Paint()
        ..color = theme.axisColor
        ..strokeWidth = 1.4,
    );
    final tickPaint = Paint()
      ..color = theme.axisColor.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (final (z, _) in zTicks) {
      final p = projector.project(Point3D(bx, by, z));
      canvas.drawLine(Offset(p.dx - 4, p.dy), Offset(p.dx + 4, p.dy), tickPaint);
    }
  }

  /// The x and y axes along the front floor edges, plus the vertical axis'
  /// labels. Draw after the data so labels stay readable.
  void drawFrontAxes(Canvas canvas) {
    final axisPaint = Paint()
      ..color = theme.axisColor
      ..strokeWidth = 1.4;
    final tickPaint = Paint()
      ..color = theme.axisColor.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    final fy = _frontY, fx = _frontX;

    void edgeAxis(Offset a, Offset b, List<(Offset, String)> ticks, String title) {
      canvas.drawLine(a, b, axisPaint);
      final out = _outward((a + b) / 2);
      final stride = _stride(ticks.length, (b - a).distance);
      for (int i = 0; i < ticks.length; i++) {
        final (p, label) = ticks[i];
        canvas.drawLine(p - out * 3, p + out * 3, tickPaint);
        if (i % stride == 0) _label(canvas, label, p + out * 8, _alignFor(out));
      }
      _title(canvas, title, (a + b) / 2 + out * 30, _alignFor(out));
    }

    edgeAxis(
      projector.project(Point3D(xMin, fy, 0)),
      projector.project(Point3D(xMax, fy, 0)),
      [for (final (x, l) in xTicks) (projector.project(Point3D(x, fy, 0)), l)],
      xAxisTitle,
    );
    edgeAxis(
      projector.project(Point3D(fx, yMin, 0)),
      projector.project(Point3D(fx, yMax, 0)),
      [for (final (y, l) in yTicks) (projector.project(Point3D(fx, y, 0)), l)],
      yAxisTitle,
    );

    // Vertical axis labels, on the side facing away from the grid.
    final (bx, by) = _backCorner;
    final leftSide = _outward(projector.project(Point3D(bx, by, 0))).dx < 0;
    // When perspective squashes the axis, skip labels that would overlap the
    // last one drawn (at least ~1.2 lines apart).
    final minGap = theme.tickFontSize * 1.6;
    double? lastY;
    for (final (z, label) in zTicks) {
      final p = projector.project(Point3D(bx, by, z));
      if (lastY != null && (p.dy - lastY).abs() < minGap) continue;
      _label(canvas, label, p + Offset(leftSide ? -8 : 8, 0), leftSide ? _Align.right : _Align.left);
      lastY = p.dy;
    }
    _title(canvas, zAxisTitle, projector.project(Point3D(bx, by, zMax)) - const Offset(0, 8), _Align.bottom);
  }

  /// All axis layers at once, for callers that don't interleave data.
  void drawAxes(Canvas canvas) {
    drawBackAxis(canvas);
    drawFrontAxes(canvas);
  }

  /// Anchor a label so it extends in direction [d] from its anchor point.
  _Align _alignFor(Offset d) {
    if (d.dx.abs() > d.dy.abs() * 1.5) return d.dx > 0 ? _Align.left : _Align.right;
    return d.dy > 0 ? _Align.top : _Align.bottom;
  }

  /// Label every n-th tick so labels ~40px apart don't collide.
  int _stride(int count, double axisLength) {
    if (count <= 1) return 1;
    final gap = axisLength / count;
    return math.max(1, (40 / math.max(gap, 1)).ceil());
  }

  void _label(Canvas canvas, String text, Offset anchor, _Align align) {
    final tp = layoutChartText(text, color: theme.tickTextColor, fontSize: theme.tickFontSize, fontFamily: theme.fontFamily);
    _paintAligned(canvas, tp, anchor, align);
  }

  void _title(Canvas canvas, String text, Offset anchor, _Align align) {
    if (text.isEmpty) return;
    final tp = layoutChartText(text, color: theme.titleColor, fontSize: 13, fontFamily: theme.fontFamily);
    _paintAligned(canvas, tp, anchor, align);
  }

  void _paintAligned(Canvas canvas, TextPainter tp, Offset anchor, _Align align) {
    final offset = switch (align) {
      _Align.top => Offset(-tp.width / 2, 0), // anchor at top-centre
      _Align.right => Offset(-tp.width, -tp.height / 2), // anchor at right-middle
      _Align.left => Offset(0, -tp.height / 2), // anchor at left-middle
      _Align.bottom => Offset(-tp.width / 2, -tp.height), // anchor at bottom-centre
    };
    tp.paint(canvas, anchor + offset);
  }

  static void dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0, gap = 3.0;
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    for (double d = 0; d < total; d += dash + gap) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, total), paint);
    }
  }
}

enum _Align { top, right, left, bottom }

/// [Axes3D] for a `rows × cols` category grid — shared by [Surface3DChart]
/// and [Bar3DChart].
///
/// Grid point `(row, col)` sits at model `x = (col - cols/2) * spacing`,
/// `y = (row - rows/2) * spacing`; a value `v` sits at height `v * zScale`.
class GridAxes3D extends Axes3D {
  final int rows;
  final int cols;
  final double spacing;
  final double zScale;

  GridAxes3D({
    required this.rows,
    required this.cols,
    required this.spacing,
    required this.zScale,
    required super.projector,
    required super.theme,
    required List<String> xLabels,
    required List<String> yLabels,
    required super.xAxisTitle,
    required super.yAxisTitle,
    required super.zAxisTitle,
    required String Function(double value) valueFormatter,
    required double minValue,
    required double maxValue,

    /// Floor lines around cells (bars) rather than through grid points (surfaces).
    bool cellFloor = false,
  }) : super(
          xMin: (-0.6 - cols / 2) * spacing,
          xMax: (cols - 1 + 0.6 - cols / 2) * spacing,
          yMin: (-0.6 - rows / 2) * spacing,
          yMax: (rows - 1 + 0.6 - rows / 2) * spacing,
          zMin: math.min(0.0, minValue * zScale),
          zMax: math.max(0.0, maxValue * zScale),
          xTicks: [for (int c = 0; c < math.min(cols, xLabels.length); c++) ((c - cols / 2) * spacing, xLabels[c])],
          yTicks: [for (int r = 0; r < math.min(rows, yLabels.length); r++) ((r - rows / 2) * spacing, yLabels[r])],
          zTicks: [
            for (final v in minValue == maxValue ? [minValue] : Cartesian2DAxes.niceTicks(math.min(0, minValue), maxValue))
              (v * zScale, valueFormatter(v)),
          ],
          floorXLines: [for (int c = 0; c < cols + (cellFloor ? 1 : 0); c++) (c - (cellFloor ? 0.5 : 0) - cols / 2) * spacing],
          floorYLines: [for (int r = 0; r < rows + (cellFloor ? 1 : 0); r++) (r - (cellFloor ? 0.5 : 0) - rows / 2) * spacing],
        );

  double colX(num c) => (c - cols / 2) * spacing;
  double rowY(num r) => (r - rows / 2) * spacing;

  /// Model-space top of the value axis.
  double get zTop => zMax;

  /// A dashed vertical marker through column [col], labelled at the top.
  void drawReferenceColumn(Canvas canvas, int col, String? label) {
    final x = colX(col);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = theme.crosshairColor;
    Axes3D.dashedLine(
        canvas, projector.project(Point3D(x, rowY(0), zTop + 30)), projector.project(Point3D(x, rowY(rows - 1), 0)), paint);
    if (label != null) {
      final p = projector.project(Point3D(x, rowY(0), zTop + 45));
      final tp = layoutChartText(label, color: theme.titleColor, fontSize: 11, fontFamily: theme.fontFamily);
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height));
    }
  }
}
