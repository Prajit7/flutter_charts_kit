import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'chart_controller.dart';
import 'chart2d/common.dart';
import 'chart2d/theme.dart';
import 'geometry.dart';
import 'grid_axes3d.dart';
import 'legend.dart';
import 'orbit_view.dart';
import 'surface_3d_chart_widget.dart' show Surface3DHit;

/// A 3D bar chart: one bar per cell of a `data[row][col]` grid, colored by
/// value — e.g. sales by region (columns) and month (rows).
///
/// ```dart
/// Bar3DChart(
///   data: [
///     [12, 18, 9],   // row 0 ("Jan")
///     [15, 22, 14],  // row 1 ("Feb")
///   ],
///   xLabels: ['North', 'South', 'East'],
///   yLabels: ['Jan', 'Feb'],
///   xAxisTitle: 'Region',
///   yAxisTitle: 'Month',
///   zAxisTitle: 'Sales',
/// )
/// ```
///
/// Drag to rotate, pinch or scroll to zoom, hover/tap a bar for its value.
/// Takes the same `data`/labels shape as [Surface3DChart].
class Bar3DChart extends StatefulWidget {
  /// `data[rowIndex][colIndex]`; rows may be ragged (missing = no bar).
  final List<List<double>> data;
  final List<String> xLabels;
  final List<String> yLabels;
  final String xAxisTitle;
  final String yAxisTitle;
  final String zAxisTitle;
  final String Function(double value) valueFormatter;

  /// Color stops from low to high value. Pass a single-color list (twice)
  /// for uniform bars.
  final List<Color> gradient;

  /// Pin the color scale instead of using the data's min/max.
  final double? fixedMin;
  final double? fixedMax;

  /// Bar footprint as a fraction of the cell (0–1).
  final double barWidth;

  /// Max visual height (model units) of the tallest bar.
  final double maxBarHeight;
  final double cellSpacing;
  final double initialRotationX;
  final double initialRotationY;
  final double initialZoom;
  final bool showResetButton;
  final bool enableScrollZoom;

  /// Shows a color-scale legend in a corner.
  final bool showLegend;
  final Alignment legendAlignment;
  final String? legendTitle;
  final bool enableAnimation;
  final Duration animationDuration;

  /// Replaces the default tooltip card.
  final Widget Function(BuildContext context, Surface3DHit hit)? tooltipBuilder;
  final Surface3DChartController? controller;
  final ValueChanged<Surface3DHit?>? onBarHover;
  final ValueChanged<Surface3DHit>? onBarTap;

  const Bar3DChart({
    super.key,
    required this.data,
    required this.xLabels,
    required this.yLabels,
    this.xAxisTitle = '',
    this.yAxisTitle = '',
    this.zAxisTitle = '',
    this.valueFormatter = _defaultFormatter,
    this.gradient = const [Color(0xFF42A5F5), Color(0xFFFFCA28), Color(0xFFEF5350)],
    this.fixedMin,
    this.fixedMax,
    this.barWidth = 0.6,
    this.maxBarHeight = 160,
    this.cellSpacing = 45,
    this.initialRotationX = 0.6,
    this.initialRotationY = -0.7,
    this.initialZoom = 16,
    this.showResetButton = true,
    this.enableScrollZoom = true,
    this.showLegend = false,
    this.legendAlignment = Alignment.bottomLeft,
    this.legendTitle,
    this.enableAnimation = true,
    this.animationDuration = const Duration(milliseconds: 700),
    this.tooltipBuilder,
    this.controller,
    this.onBarHover,
    this.onBarTap,
  });

  static String _defaultFormatter(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  State<Bar3DChart> createState() => _Bar3DChartState();
}

/// One box's visible faces, ready to paint, plus what it represents.
class _Box {
  final int row;
  final int col;
  final double value;
  final double depth;
  final List<(Path, double)> faces; // path + shade (0 = lit, 1 = darkest)

  _Box(this.row, this.col, this.value, this.depth, this.faces);
}

class _Bar3DChartState extends State<Bar3DChart> {
  int get _rows => widget.data.length;
  int get _cols => widget.data.fold(0, (m, r) => math.max(m, r.length));

  (double, double) get _range {
    double lo = 0, hi = 0;
    for (final row in widget.data) {
      for (final v in row) {
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
    return (widget.fixedMin ?? lo, widget.fixedMax ?? hi);
  }

  double get _zScale {
    final (lo, hi) = _range;
    final m = math.max(hi.abs(), lo.abs());
    return m == 0 ? 1 : widget.maxBarHeight / m;
  }

  GridAxes3D _axes(Projector p, ChartTheme theme) {
    final (lo, hi) = _range;
    return GridAxes3D(
      rows: _rows,
      cols: _cols,
      spacing: widget.cellSpacing,
      zScale: _zScale,
      projector: p,
      theme: theme,
      xLabels: widget.xLabels,
      yLabels: widget.yLabels,
      xAxisTitle: widget.xAxisTitle,
      yAxisTitle: widget.yAxisTitle,
      zAxisTitle: widget.zAxisTitle,
      valueFormatter: widget.valueFormatter,
      minValue: lo,
      maxValue: hi,
      cellFloor: true,
    );
  }

  Projector _projector(Size size, double rx, double ry, double zoom) {
    final (lo, hi) = _range;
    final s = widget.cellSpacing;
    return fitProjector(
      area: Offset.zero & size,
      rotationX: rx,
      rotationY: ry,
      zoom: zoom,
      xMin: (-0.6 - _cols / 2) * s,
      xMax: (_cols - 1 + 0.6 - _cols / 2) * s,
      yMin: (-0.6 - _rows / 2) * s,
      yMax: (_rows - 1 + 0.6 - _rows / 2) * s,
      zMin: math.min(0.0, lo * _zScale),
      zMax: math.max(0.0, hi * _zScale),
      fitRotationX: widget.initialRotationX,
      fitRotationY: widget.initialRotationY,
      defaultZoom: 16,
      margin: 40,
    );
  }

  /// Boxes back-to-front, each with only its camera-facing faces.
  List<_Box> _boxes(Projector p, double progress) {
    final s = widget.cellSpacing;
    final half = s * widget.barWidth.clamp(0.05, 1.0) / 2;
    final zScale = _zScale;
    final boxes = <_Box>[];
    for (int r = 0; r < _rows; r++) {
      for (int c = 0; c < widget.data[r].length; c++) {
        final v = widget.data[r][c];
        final cx = (c - _cols / 2) * s, cy = (r - _rows / 2) * s;
        final h = v * zScale * progress;
        final z0 = math.min(0.0, h), z1 = math.max(0.0, h);
        final x0 = cx - half, x1 = cx + half, y0 = cy - half, y1 = cy + half;

        // Each face: corners (any winding) + outward normal.
        final faces = <(List<Point3D>, Point3D)>[
          ([Point3D(x0, y0, z1), Point3D(x1, y0, z1), Point3D(x1, y1, z1), Point3D(x0, y1, z1)], const Point3D(0, 0, 1)),
          ([Point3D(x0, y0, z0), Point3D(x1, y0, z0), Point3D(x1, y1, z0), Point3D(x0, y1, z0)], const Point3D(0, 0, -1)),
          ([Point3D(x0, y0, z0), Point3D(x1, y0, z0), Point3D(x1, y0, z1), Point3D(x0, y0, z1)], const Point3D(0, -1, 0)),
          ([Point3D(x0, y1, z0), Point3D(x1, y1, z0), Point3D(x1, y1, z1), Point3D(x0, y1, z1)], const Point3D(0, 1, 0)),
          ([Point3D(x0, y0, z0), Point3D(x0, y1, z0), Point3D(x0, y1, z1), Point3D(x0, y0, z1)], const Point3D(-1, 0, 0)),
          ([Point3D(x1, y0, z0), Point3D(x1, y1, z0), Point3D(x1, y1, z1), Point3D(x1, y0, z1)], const Point3D(1, 0, 0)),
        ];
        final visible = <(Path, double)>[];
        final camera = Point3D(0, 0, p.cameraDistance);
        for (final (corners, normal) in faces) {
          if (z1 - z0 < 0.01 && normal.z == 0) continue; // flat bar: top only
          // Back-face cull: keep faces whose rotated normal points toward the camera.
          final centre = Point3D(
            corners.fold(0.0, (a, q) => a + q.x) / 4,
            corners.fold(0.0, (a, q) => a + q.y) / 4,
            corners.fold(0.0, (a, q) => a + q.z) / 4,
          );
          final rc = p.rotate(centre);
          final rn = p.rotate(normal);
          final toCamera = Point3D(camera.x - rc.x, camera.y - rc.y, camera.z - rc.z);
          if (rn.x * toCamera.x + rn.y * toCamera.y + rn.z * toCamera.z <= 0) continue;
          final pts = corners.map(p.project).toList();
          // Top faces are brightest; sides shade by how far they turn away.
          final shade = normal.z != 0 ? 0.0 : (0.18 + 0.2 * (1 - rn.z.abs().clamp(0.0, 1.0)));
          visible.add((Path()..addPolygon(pts, true), shade));
        }
        final depth = p.rotate(Point3D(cx, cy, (z0 + z1) / 2)).z;
        boxes.add(_Box(r, c, v, depth, visible));
      }
    }
    boxes.sort((a, b) => a.depth.compareTo(b.depth)); // far first
    return boxes;
  }

  Surface3DHit _hitFor(_Box b) => Surface3DHit(
        colIndex: b.col,
        rowIndex: b.row,
        value: b.value,
        xLabel: b.col < widget.xLabels.length ? widget.xLabels[b.col] : '',
        yLabel: b.row < widget.yLabels.length ? widget.yLabels[b.row] : '',
      );

  @override
  Widget build(BuildContext context) {
    // Checked here, not in the constructor, so `const Bar3DChart(...)` compiles.
    assert(widget.gradient.length >= 2, 'gradient needs at least 2 colors');
    final theme = ChartThemeScope.of(context);
    final (lo, hi) = _range;
    return Semantics(
      container: true,
      label: describeChart('3D bar chart', widget.zAxisTitle, [
        '$_rows rows by $_cols columns',
        'values from ${widget.valueFormatter(lo)} to ${widget.valueFormatter(hi)}',
      ]),
      child: Orbit3DView<Surface3DHit>(
      initialRotationX: widget.initialRotationX,
      initialRotationY: widget.initialRotationY,
      initialZoom: widget.initialZoom,
      showResetButton: widget.showResetButton,
      enableScrollZoom: widget.enableScrollZoom,
      controller: widget.controller,
      enableAnimation: widget.enableAnimation,
      animationDuration: widget.animationDuration,
      animationKey: Object.hashAll([for (final r in widget.data) Object.hashAll(r)]),
      onHover: widget.onBarHover,
      onTap: widget.onBarTap,
      overlayAlignment: widget.legendAlignment,
      overlay: widget.showLegend
          ? Surface3DLegend(
              gradient: widget.gradient,
              min: lo,
              max: hi,
              valueFormatter: widget.valueFormatter,
              title: widget.legendTitle ?? widget.zAxisTitle,
            )
          : null,
      projectorBuilder: _projector,
      hitTest: (pos, size, p) {
        for (final b in _boxes(p, 1).reversed) {
          if (b.faces.any((f) => f.$1.contains(pos))) return _hitFor(b);
        }
        return null;
      },
      painterBuilder: (size, p, hover, progress) => _Bar3DPainter(
        axes: _axes(p, theme),
        boxes: _boxes(p, Curves.easeOutCubic.transform(progress)),
        colorFor: (v) => sampleGradient(widget.gradient, hi == lo ? 0.5 : (v - lo) / (hi - lo)),
        hover: hover,
        theme: theme,
      ),
      tooltipBuilder: (context, hit, pointer, size) {
        final custom = widget.tooltipBuilder;
        return positionChartTooltip(
          anchor: pointer,
          areaSize: size,
          cardWidth: 170,
          child: custom != null
              ? custom(context, hit)
              : ChartTooltipCard(
                  theme: theme,
                  width: 170,
                  title: hit.xLabel,
                  subtitle: [widget.yAxisTitle, hit.yLabel].where((s) => s.isNotEmpty).join('  '),
                  value: [widget.zAxisTitle, widget.valueFormatter(hit.value)].where((s) => s.isNotEmpty).join('  '),
                ),
        );
      },
    ),
    );
  }
}

class _Bar3DPainter extends CustomPainter {
  final GridAxes3D axes;
  final List<_Box> boxes;
  final Color Function(double value) colorFor;
  final Surface3DHit? hover;
  final ChartTheme theme;

  _Bar3DPainter({required this.axes, required this.boxes, required this.colorFor, required this.hover, required this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    axes.drawFloor(canvas);
    axes.drawBackAxis(canvas);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = Colors.black.withValues(alpha: 0.18);
    for (final b in boxes) {
      final base = colorFor(b.value);
      final hovered = hover != null && hover!.rowIndex == b.row && hover!.colIndex == b.col;
      for (final (path, shade) in b.faces) {
        final c = Color.lerp(base, Colors.black, shade)!;
        canvas.drawPath(path, Paint()..color = hovered ? Color.lerp(c, Colors.white, 0.25)! : c);
        canvas.drawPath(path, edge);
      }
      if (hovered) {
        for (final (path, _) in b.faces) {
          canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6
              ..color = theme.axisColor,
          );
        }
      }
    }
    axes.drawFrontAxes(canvas);
  }

  @override
  bool shouldRepaint(covariant _Bar3DPainter old) => true;
}
