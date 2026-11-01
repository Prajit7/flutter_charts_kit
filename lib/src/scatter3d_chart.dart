import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'chart_controller.dart';
import 'chart2d/cartesian_axes.dart';
import 'chart2d/common.dart';
import 'chart2d/legend.dart';
import 'chart2d/models.dart' show LegendEntry;
import 'chart2d/theme.dart';
import 'geometry.dart';
import 'grid_axes3d.dart';
import 'orbit_view.dart';

/// One point of a [Scatter3DChart] series, in data units.
class Scatter3DPoint {
  final double x;
  final double y;
  final double z;

  /// Shown in the tooltip.
  final String? label;

  /// Radius in pixels (before perspective), overriding the chart default —
  /// for 3D bubble charts.
  final double? size;

  const Scatter3DPoint({required this.x, required this.y, required this.z, this.label, this.size});
}

/// A named, colored set of [Scatter3DPoint]s.
class Scatter3DSeries {
  final String name;
  final Color color;
  final List<Scatter3DPoint> points;

  const Scatter3DSeries({required this.name, required this.color, required this.points});
}

/// A hovered/tapped point.
class Scatter3DHit {
  final String series;
  final Scatter3DPoint point;

  const Scatter3DHit(this.series, this.point);

  @override
  bool operator ==(Object other) => other is Scatter3DHit && other.series == series && identical(other.point, point);

  @override
  int get hashCode => Object.hash(series, identityHashCode(point));
}

/// A 3D scatter plot over three numeric axes — clusters, correlations
/// between three measures, or anything with an (x, y, z).
///
/// ```dart
/// Scatter3DChart(
///   xAxisTitle: 'Price', yAxisTitle: 'Rating', zAxisTitle: 'Sales',
///   series: [
///     Scatter3DSeries(name: 'Phones', color: Colors.blue, points: [
///       Scatter3DPoint(x: 499, y: 4.2, z: 1200, label: 'Model A'),
///       Scatter3DPoint(x: 899, y: 4.6, z: 640, label: 'Model B'),
///     ]),
///   ],
/// )
/// ```
///
/// Drag to rotate, pinch or scroll to zoom, hover/tap a point. Each axis is
/// scaled independently to its data's (nicely rounded) range. Data x/y
/// run along the floor; z is up.
class Scatter3DChart extends StatefulWidget {
  final List<Scatter3DSeries> series;
  final String xAxisTitle;
  final String yAxisTitle;
  final String zAxisTitle;
  final String Function(double value) xFormatter;
  final String Function(double value) yFormatter;
  final String Function(double value) zFormatter;

  /// Default point radius in pixels (scaled by perspective).
  final double pointRadius;

  /// Draw a thin line from each point down to the floor, which makes
  /// heights much easier to read.
  final bool showDropLines;
  final double initialRotationX;
  final double initialRotationY;
  final double initialZoom;
  final bool showResetButton;
  final bool enableScrollZoom;

  /// Tap-to-toggle series legend in a corner.
  final bool showLegend;
  final Alignment legendAlignment;
  final bool enableAnimation;
  final Duration animationDuration;

  /// Replaces the default tooltip card.
  final Widget Function(BuildContext context, Scatter3DHit hit)? tooltipBuilder;
  final Surface3DChartController? controller;
  final ValueChanged<Scatter3DHit?>? onPointHover;
  final ValueChanged<Scatter3DHit>? onPointTap;

  const Scatter3DChart({
    super.key,
    required this.series,
    this.xAxisTitle = '',
    this.yAxisTitle = '',
    this.zAxisTitle = '',
    this.xFormatter = Cartesian2DAxes.formatNumber,
    this.yFormatter = Cartesian2DAxes.formatNumber,
    this.zFormatter = Cartesian2DAxes.formatNumber,
    this.pointRadius = 5,
    this.showDropLines = false,
    this.initialRotationX = 0.5,
    this.initialRotationY = -0.7,
    this.initialZoom = 16,
    this.showResetButton = true,
    this.enableScrollZoom = true,
    this.showLegend = true,
    this.legendAlignment = Alignment.bottomLeft,
    this.enableAnimation = true,
    this.animationDuration = const Duration(milliseconds: 700),
    this.tooltipBuilder,
    this.controller,
    this.onPointHover,
    this.onPointTap,
  });

  @override
  State<Scatter3DChart> createState() => _Scatter3DChartState();
}

/// Half-size of the floor and height of the box, in model units.
const double _floorHalf = 150;
const double _boxHeight = 200;

class _Scale {
  final double lo;
  final double hi;
  const _Scale(this.lo, this.hi);

  factory _Scale.of(Iterable<double> values) {
    final list = values.toList();
    if (list.isEmpty) return const _Scale(0, 1);
    final (lo, hi) = Cartesian2DAxes.niceExtent(list.reduce(math.min), list.reduce(math.max));
    return lo == hi ? _Scale(lo - 1, hi + 1) : _Scale(lo, hi);
  }

  /// Data value → fraction 0..1 of the axis.
  double t(double v) => (v - lo) / (hi - lo);
}

class _Scatter3DChartState extends State<Scatter3DChart> {
  final ValueNotifier<Set<String>> _hidden = ValueNotifier(const {});

  @override
  void dispose() {
    _hidden.dispose();
    super.dispose();
  }

  Iterable<Scatter3DPoint> get _all => widget.series.expand((s) => s.points);
  _Scale get _xs => _Scale.of(_all.map((p) => p.x));
  _Scale get _ys => _Scale.of(_all.map((p) => p.y));
  _Scale get _zs => _Scale.of(_all.map((p) => p.z));

  Point3D _model(Scatter3DPoint p, _Scale xs, _Scale ys, _Scale zs, [double progress = 1]) => Point3D(
        -_floorHalf + 2 * _floorHalf * xs.t(p.x),
        // Data y grows away from the viewer at the default angle.
        _floorHalf - 2 * _floorHalf * ys.t(p.y),
        _boxHeight * zs.t(p.z) * progress,
      );

  Projector _projector(Size size, double rx, double ry, double zoom) => fitProjector(
        area: Offset.zero & size,
        rotationX: rx,
        rotationY: ry,
        zoom: zoom,
        xMin: -_floorHalf,
        xMax: _floorHalf,
        yMin: -_floorHalf,
        yMax: _floorHalf,
        zMin: 0,
        zMax: _boxHeight,
        fitRotationX: widget.initialRotationX,
        fitRotationY: widget.initialRotationY,
        defaultZoom: 16,
        margin: 44,
      );

  Axes3D _axes(Projector p, ChartTheme theme) {
    final xs = _xs, ys = _ys, zs = _zs;
    final xt = Cartesian2DAxes.niceTicks(xs.lo, xs.hi), yt = Cartesian2DAxes.niceTicks(ys.lo, ys.hi);
    double mx(double v) => -_floorHalf + 2 * _floorHalf * xs.t(v);
    double my(double v) => _floorHalf - 2 * _floorHalf * ys.t(v);
    return Axes3D(
      projector: p,
      theme: theme,
      xMin: -_floorHalf,
      xMax: _floorHalf,
      yMin: -_floorHalf,
      yMax: _floorHalf,
      zMin: 0,
      zMax: _boxHeight,
      xTicks: [for (final v in xt) (mx(v), widget.xFormatter(v))],
      yTicks: [for (final v in yt) (my(v), widget.yFormatter(v))],
      zTicks: [for (final v in Cartesian2DAxes.niceTicks(zs.lo, zs.hi)) (_boxHeight * zs.t(v), widget.zFormatter(v))],
      floorXLines: [for (final v in xt) mx(v)],
      floorYLines: [for (final v in yt) my(v)],
      xAxisTitle: widget.xAxisTitle,
      yAxisTitle: widget.yAxisTitle,
      zAxisTitle: widget.zAxisTitle,
    );
  }

  /// Visible points with their screen position, radius and depth, far first.
  List<(Scatter3DHit, Offset, double, double, Color, Offset)> _projected(Projector p, Set<String> hidden, double progress) {
    final xs = _xs, ys = _ys, zs = _zs;
    final out = <(Scatter3DHit, Offset, double, double, Color, Offset)>[];
    for (final s in widget.series) {
      if (hidden.contains(s.name)) continue;
      for (final pt in s.points) {
        final m = _model(pt, xs, ys, zs, progress);
        final r = p.rotate(m);
        final perspective = p.cameraDistance / (p.cameraDistance - r.z);
        final floor = p.project(Point3D(m.x, m.y, 0));
        out.add((Scatter3DHit(s.name, pt), p.project(m), (pt.size ?? widget.pointRadius) * perspective, r.z, s.color, floor));
      }
    }
    out.sort((a, b) => a.$4.compareTo(b.$4));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    return Semantics(
      container: true,
      label: describeChart('3D scatter chart', null, [for (final s in widget.series) '${s.name}: ${s.points.length} points']),
      child: ValueListenableBuilder<Set<String>>(
      valueListenable: _hidden,
      builder: (context, hidden, _) => Orbit3DView<Scatter3DHit>(
        initialRotationX: widget.initialRotationX,
        initialRotationY: widget.initialRotationY,
        initialZoom: widget.initialZoom,
        showResetButton: widget.showResetButton,
        enableScrollZoom: widget.enableScrollZoom,
        controller: widget.controller,
        enableAnimation: widget.enableAnimation,
        animationDuration: widget.animationDuration,
        animationKey: Object.hashAll([for (final s in widget.series) Object.hash(s.name, s.points.length)]),
        onHover: widget.onPointHover,
        onTap: widget.onPointTap,
        overlayAlignment: widget.legendAlignment,
        overlay: widget.showLegend && widget.series.length > 1
            ? Chart2DLegend(
                direction: Axis.vertical,
                entries: [for (final s in widget.series) LegendEntry(label: s.name, color: s.color)],
                hidden: hidden,
                onToggle: (name) {
                  final next = {...hidden};
                  next.contains(name) ? next.remove(name) : next.add(name);
                  _hidden.value = next;
                },
              )
            : null,
        projectorBuilder: _projector,
        hitTest: (pos, size, p) {
          // Nearest (front-most on ties) point within its radius + slop.
          Scatter3DHit? best;
          double bestDist = double.infinity;
          for (final (hit, screen, radius, _, _, _) in _projected(p, hidden, 1).reversed) {
            final d = (screen - pos).distance;
            if (d <= radius + 6 && d < bestDist) {
              bestDist = d;
              best = hit;
            }
          }
          return best;
        },
        painterBuilder: (size, p, hover, progress) => _Scatter3DPainter(
          axes: _axes(p, theme),
          points: _projected(p, hidden, Curves.easeOutCubic.transform(progress)),
          dropLines: widget.showDropLines,
          hover: hover,
          theme: theme,
        ),
        tooltipBuilder: (context, hit, pointer, size) {
          final custom = widget.tooltipBuilder;
          final pt = hit.point;
          String axis(String title, String fallback, String value) => '${title.isEmpty ? fallback : title} $value';
          return positionChartTooltip(
            anchor: pointer,
            areaSize: size,
            cardWidth: 170,
            child: custom != null
                ? custom(context, hit)
                : ChartTooltipCard(
                    theme: theme,
                    width: 170,
                    title: pt.label ?? hit.series,
                    subtitle: [
                      if (pt.label != null) hit.series,
                      axis(widget.xAxisTitle, 'x', widget.xFormatter(pt.x)),
                      axis(widget.yAxisTitle, 'y', widget.yFormatter(pt.y)),
                    ].join('\n'),
                    value: axis(widget.zAxisTitle, 'z', widget.zFormatter(pt.z)),
                  ),
          );
        },
      ),
    ),
    );
  }
}

class _Scatter3DPainter extends CustomPainter {
  final Axes3D axes;
  final List<(Scatter3DHit, Offset, double, double, Color, Offset)> points;
  final bool dropLines;
  final Scatter3DHit? hover;
  final ChartTheme theme;

  _Scatter3DPainter({required this.axes, required this.points, required this.dropLines, required this.hover, required this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    axes.drawFloor(canvas);
    axes.drawBackAxis(canvas);

    for (final (hit, screen, radius, _, color, floor) in points) {
      if (dropLines) {
        canvas.drawLine(screen, floor, Paint()
          ..color = color.withValues(alpha: 0.35)
          ..strokeWidth = 1);
        canvas.drawCircle(floor, 1.5, Paint()..color = color.withValues(alpha: 0.35));
      }
      final hovered = hit == hover;
      // A soft radial gradient reads as a sphere.
      final rect = Rect.fromCircle(center: screen, radius: radius);
      canvas.drawCircle(
        screen,
        radius,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.35, -0.35),
            colors: [Color.lerp(color, Colors.white, 0.45)!, color, Color.lerp(color, Colors.black, 0.25)!],
            stops: const [0, 0.55, 1],
          ).createShader(rect),
      );
      if (hovered) {
        canvas.drawCircle(screen, radius + 3, Paint()
          ..color = theme.axisColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6);
      }
    }

    axes.drawFrontAxes(canvas);
  }

  @override
  bool shouldRepaint(covariant _Scatter3DPainter old) => true;
}
