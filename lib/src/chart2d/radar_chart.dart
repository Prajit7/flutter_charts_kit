import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'cartesian_axes.dart';
import 'legend.dart';
import 'models.dart';
import 'theme.dart';
import 'chart_chrome.dart';
import 'common.dart';
import 'controller.dart';
import 'hover_plot.dart';

/// One hovered/tapped radar vertex.
class RadarHit {
  final String series;
  final int axisIndex;
  final String axis;
  final double value;

  const RadarHit({required this.series, required this.axisIndex, required this.axis, required this.value});

  @override
  bool operator ==(Object other) => other is RadarHit && other.series == series && other.axisIndex == axisIndex;

  @override
  int get hashCode => Object.hash(series, axisIndex);
}

/// A radar / spider chart: several series compared across the same set of
/// axes (skills, product attributes, survey scores…).
///
/// ```dart
/// RadarChart2D(
///   axes: ['Speed', 'Power', 'Range', 'Comfort', 'Price'],
///   series: [
///     CategorySeries(name: 'Model A', color: Colors.blue, values: [8, 6, 7, 9, 4]),
///     CategorySeries(name: 'Model B', color: Colors.orange, values: [6, 9, 5, 6, 8]),
///   ],
///   max: 10,
/// )
/// ```
///
/// Each series' `values` align 1:1 with [axes]; missing values count as 0.
class RadarChart2D extends StatefulWidget {
  /// One label per spoke, clockwise from the top.
  final List<String> axes;
  final List<CategorySeries> series;

  /// Value at the outer ring. Defaults to a nice number above the data max.
  final double? max;

  /// Number of concentric rings.
  final int rings;

  /// Draw rings as polygons (true) or circles (false).
  final bool polygonGrid;

  final bool filled;
  final bool showPoints;
  final String? title;
  final String? subtitle;
  final String emptyStateMessage;
  final String Function(double value) valueFormatter;

  /// Print the value of each ring along the top spoke.
  final bool showRingLabels;
  final bool showLegend;
  final ChartLegendPosition legendPosition;
  final bool enableAnimation;
  final Duration animationDuration;

  /// Replaces the default tooltip card.
  final Widget Function(BuildContext context, RadarHit hit)? tooltipBuilder;

  /// Export an image from outside the chart.
  final ChartController? controller;

  final ValueChanged<RadarHit?>? onPointHover;
  final ValueChanged<RadarHit>? onPointTap;

  const RadarChart2D({
    super.key,
    required this.axes,
    required this.series,
    this.max,
    this.rings = 4,
    this.polygonGrid = true,
    this.filled = true,
    this.showPoints = true,
    this.title,
    this.subtitle,
    this.emptyStateMessage = 'No data to display',
    this.valueFormatter = Cartesian2DAxes.formatNumber,
    this.showRingLabels = true,
    this.showLegend = true,
    this.legendPosition = ChartLegendPosition.bottom,
    this.enableAnimation = true,
    this.animationDuration = const Duration(milliseconds: 600),
    this.tooltipBuilder,
    this.controller,
    this.onPointHover,
    this.onPointTap,
  });

  @override
  State<RadarChart2D> createState() => _RadarChart2DState();
}

class _RadarGeometry {
  final Offset center;
  final double radius;
  final int spokes;
  final double max;

  _RadarGeometry(this.center, this.radius, this.spokes, this.max);

  double angle(int i) => -math.pi / 2 + 2 * math.pi * i / spokes;

  Offset point(int i, double value, [double progress = 1]) {
    final r = radius * (max == 0 ? 0 : (value / max).clamp(0.0, 1.0)) * progress;
    return center + Offset(math.cos(angle(i)), math.sin(angle(i))) * r;
  }
}

class _RadarChart2DState extends State<RadarChart2D> with ChartControllerMixin<RadarChart2D> {
  final ValueNotifier<Set<String>> _hidden = ValueNotifier(const {});

  @override
  ChartController? controllerOf(RadarChart2D widget) => widget.controller;

  @override
  void resetZoom() {} // no zoom on this chart

  @override
  void dispose() {
    _hidden.dispose();
    super.dispose();
  }

  double get _max {
    if (widget.max != null) return widget.max!;
    double m = 0;
    for (final s in widget.series) {
      for (final v in s.values) {
        m = math.max(m, v);
      }
    }
    return m == 0 ? 1 : Cartesian2DAxes.niceExtent(0, m, count: widget.rings).$2;
  }

  _RadarGeometry _geometry(Size size, ChartTheme theme) {
    // Leave room around the web for the spoke labels.
    double labelWidth = 0;
    for (final a in widget.axes) {
      labelWidth = math.max(labelWidth, layoutChartText(a, color: theme.tickTextColor, fontSize: theme.tickFontSize).width);
    }
    final pad = math.min(labelWidth, size.width * 0.22) + 10;
    final radius = math.max(0.0, math.min(size.width / 2 - pad, size.height / 2 - 18));
    return _RadarGeometry(size.center(Offset.zero), radius, widget.axes.length, _max);
  }

  double _value(CategorySeries s, int i) => i < s.values.length ? s.values[i] : 0;

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    if (widget.axes.length < 3 || widget.series.isEmpty) {
      return ChartFrame(
        boundaryKey: chartBoundaryKey,
        title: widget.title,
        subtitle: widget.subtitle,
        plot: ChartEmptyState(message: widget.emptyStateMessage),
      );
    }

    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Radar chart', widget.title, ['${widget.axes.length} axes: ${widget.axes.join(', ')}', for (final s in widget.series) summarizeValues(s.name, s.values, widget.valueFormatter)]),
      title: widget.title,
      subtitle: widget.subtitle,
      legendPosition: widget.legendPosition,
      legendBuilder: widget.showLegend
          ? (direction) => ValueListenableBuilder<Set<String>>(
                valueListenable: _hidden,
                builder: (context, hidden, _) => Chart2DLegend(
                  direction: direction,
                  entries: [for (final s in widget.series) LegendEntry(label: s.name, color: s.color)],
                  hidden: hidden,
                  onToggle: (name) {
                    final next = {...hidden};
                    next.contains(name) ? next.remove(name) : next.add(name);
                    _hidden.value = next;
                  },
                ),
              )
          : null,
      plot: ValueListenableBuilder<Set<String>>(
        valueListenable: _hidden,
        builder: (context, hidden, _) {
          final visible = widget.series.where((s) => !hidden.contains(s.name)).toList();
          return HoverPlot<RadarHit>(
            enableAnimation: widget.enableAnimation,
            animationDuration: widget.animationDuration,
            animationKey: Object.hash(Object.hashAll(widget.series), Object.hashAll(widget.axes)),
            onHover: widget.onPointHover,
            onTap: widget.onPointTap,
            hitTest: (pos, size) {
              final g = _geometry(size, theme);
              RadarHit? best;
              double bestDist = 18;
              for (final s in visible) {
                for (int i = 0; i < widget.axes.length; i++) {
                  final d = (g.point(i, _value(s, i)) - pos).distance;
                  if (d < bestDist) {
                    bestDist = d;
                    best = RadarHit(series: s.name, axisIndex: i, axis: widget.axes[i], value: _value(s, i));
                  }
                }
              }
              return best;
            },
            painterBuilder: (size, hover, progress) => _RadarPainter(
              geometry: _geometry(size, theme),
              axes: widget.axes,
              series: visible,
              rings: widget.rings,
              polygonGrid: widget.polygonGrid,
              filled: widget.filled,
              showPoints: widget.showPoints,
              showRingLabels: widget.showRingLabels,
              valueFormatter: widget.valueFormatter,
              theme: theme,
              hover: hover,
              progress: Curves.easeOutCubic.transform(progress),
            ),
            tooltipBuilder: (context, hit, pointer, size) {
              final s = visible.firstWhere((s) => s.name == hit.series);
              final custom = widget.tooltipBuilder;
              return positionChartTooltip(
                anchor: _geometry(size, theme).point(hit.axisIndex, _value(s, hit.axisIndex)),
                areaSize: size,
                child: custom != null
                    ? custom(context, hit)
                    : ChartTooltipCard(
                        theme: theme, width: 150, title: hit.series, subtitle: hit.axis, value: widget.valueFormatter(hit.value)),
              );
            },
          );
        },
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final _RadarGeometry geometry;
  final List<String> axes;
  final List<CategorySeries> series;
  final int rings;
  final bool polygonGrid;
  final bool filled;
  final bool showPoints;
  final bool showRingLabels;
  final String Function(double) valueFormatter;
  final ChartTheme theme;
  final RadarHit? hover;
  final double progress;

  _RadarPainter({
    required this.geometry,
    required this.axes,
    required this.series,
    required this.rings,
    required this.polygonGrid,
    required this.filled,
    required this.showPoints,
    required this.showRingLabels,
    required this.valueFormatter,
    required this.theme,
    required this.hover,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;
    if (g.radius <= 0) return;
    final gridPaint = Paint()
      ..color = theme.gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Rings
    for (int k = 1; k <= rings; k++) {
      final value = g.max * k / rings;
      if (polygonGrid) {
        final ring = Path();
        for (int i = 0; i < g.spokes; i++) {
          final p = g.point(i, value);
          i == 0 ? ring.moveTo(p.dx, p.dy) : ring.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(ring..close(), gridPaint);
      } else {
        canvas.drawCircle(g.center, g.radius * k / rings, gridPaint);
      }
    }

    // Spokes and their labels
    for (int i = 0; i < g.spokes; i++) {
      final end = g.point(i, g.max);
      canvas.drawLine(g.center, end, gridPaint);
      final tp = layoutChartText(axes[i], color: theme.axisColor, fontSize: theme.tickFontSize, fontFamily: theme.fontFamily);
      final dir = Offset(math.cos(g.angle(i)), math.sin(g.angle(i)));
      final anchor = end + dir * 8;
      // Align the label away from the web: right-aligned on the left side,
      // centred at the top/bottom.
      final dx = dir.dx > 0.3 ? 0.0 : (dir.dx < -0.3 ? -tp.width : -tp.width / 2);
      final dy = dir.dy > 0.3 ? 0.0 : (dir.dy < -0.3 ? -tp.height : -tp.height / 2);
      tp.paint(canvas, anchor + Offset(dx, dy));
    }

    if (showRingLabels) {
      // The outer ring's value would collide with the top spoke's label.
      for (int k = 1; k < rings; k++) {
        final p = g.point(0, g.max * k / rings);
        final tp = layoutChartText(valueFormatter(g.max * k / rings),
            color: theme.tickTextColor, fontSize: theme.tickFontSize - 1, fontFamily: theme.fontFamily);
        tp.paint(canvas, p + Offset(3, -tp.height / 2));
      }
    }

    // Series
    for (final s in series) {
      final pts = [for (int i = 0; i < g.spokes; i++) g.point(i, i < s.values.length ? s.values[i] : 0, progress)];
      final shape = Path()..addPolygon(pts, true);
      final isHoveredSeries = hover?.series == s.name;
      if (filled) {
        canvas.drawPath(shape, Paint()..color = s.color.withValues(alpha: isHoveredSeries ? 0.32 : 0.18));
      }
      canvas.drawPath(
        shape,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = isHoveredSeries ? 2.6 : 2
          ..strokeJoin = StrokeJoin.round,
      );
      if (showPoints) {
        for (int i = 0; i < pts.length; i++) {
          final hovered = isHoveredSeries && hover?.axisIndex == i;
          canvas.drawCircle(pts[i], hovered ? 5 : 3, Paint()..color = s.color);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) => true;
}

