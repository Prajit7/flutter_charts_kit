import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'cartesian_axes.dart';
import 'legend.dart';
import 'models.dart';
import 'theme.dart';
import 'chart_chrome.dart';
import 'common.dart';
import 'controller.dart';
import 'hover_plot.dart';
import 'reference.dart';

/// A low–high span, with an optional middle value (mean, median, estimate).
class RangeValue {
  final double low;
  final double high;
  final double? mid;

  const RangeValue(this.low, this.high, {this.mid});

  @override
  bool operator ==(Object other) => other is RangeValue && other.low == low && other.high == high && other.mid == mid;

  @override
  int get hashCode => Object.hash(low, high, mid);
}

/// A named, colored set of ranges aligned 1:1 with a [RangeChart2D]'s
/// categories (null = no value for that category).
class RangeSeries {
  final String name;
  final Color color;
  final List<RangeValue?> values;

  const RangeSeries({required this.name, required this.color, required this.values});

  @override
  bool operator ==(Object other) =>
      other is RangeSeries && other.name == name && other.color == color && listEquals(other.values, values);

  @override
  int get hashCode => Object.hash(name, color, Object.hashAll(values));
}

/// How [RangeChart2D] draws each range.
enum RangeChartStyle {
  /// Floating bars from low to high (e.g. daily temperature span).
  bar,

  /// Two dots joined by a line — before/after, min/max, gap between groups.
  dumbbell,

  /// A point at the middle with whiskers to low and high (confidence
  /// intervals, measurement error). Uses [RangeValue.mid] or the midpoint.
  errorBar,

  /// A shaded band between the lows and highs, with a line through the
  /// middles — forecasts with uncertainty, min–max envelopes.
  area,
}

/// A hovered/tapped range.
class RangeHit {
  final String series;
  final int index;
  final String category;
  final RangeValue value;

  const RangeHit(this.series, this.index, this.category, this.value);

  @override
  bool operator ==(Object other) => other is RangeHit && other.series == series && other.index == index;

  @override
  int get hashCode => Object.hash(series, index);
}

/// Low–high ranges over categories: floating bars, dumbbells, error bars
/// or a shaded band.
///
/// ```dart
/// RangeChart2D(
///   style: RangeChartStyle.dumbbell,
///   categories: ['Q1', 'Q2', 'Q3', 'Q4'],
///   series: [
///     RangeSeries(name: 'Price range', color: Colors.indigo, values: [
///       RangeValue(98, 112), RangeValue(104, 120), RangeValue(101, 109), RangeValue(110, 131),
///     ]),
///   ],
/// )
/// ```
class RangeChart2D extends StatefulWidget {
  final List<String> categories;
  final List<RangeSeries> series;
  final RangeChartStyle style;
  final String? title;
  final String? subtitle;
  final String? xAxisTitle;
  final String? yAxisTitle;
  final String emptyStateMessage;
  final String Function(double value) valueFormatter;
  final bool showGrid;
  final bool showLegend;
  final ChartLegendPosition legendPosition;
  final List<ChartReferenceLine> referenceLines;
  final List<ChartReferenceBand> referenceBands;
  final bool enableAnimation;
  final Duration animationDuration;
  final Widget Function(BuildContext context, RangeHit hit)? tooltipBuilder;
  final ChartController? controller;
  final ValueChanged<RangeHit>? onRangeTap;

  const RangeChart2D({
    super.key,
    required this.categories,
    required this.series,
    this.style = RangeChartStyle.bar,
    this.title,
    this.subtitle,
    this.xAxisTitle,
    this.yAxisTitle,
    this.emptyStateMessage = 'No data to display',
    this.valueFormatter = Cartesian2DAxes.formatNumber,
    this.showGrid = true,
    this.showLegend = true,
    this.legendPosition = ChartLegendPosition.bottom,
    this.referenceLines = const [],
    this.referenceBands = const [],
    this.enableAnimation = true,
    this.animationDuration = const Duration(milliseconds: 550),
    this.tooltipBuilder,
    this.controller,
    this.onRangeTap,
  });

  @override
  State<RangeChart2D> createState() => _RangeChart2DState();
}

class _RangeChart2DState extends State<RangeChart2D> with ChartControllerMixin<RangeChart2D> {
  final ValueNotifier<Set<String>> _hidden = ValueNotifier(const {});

  @override
  ChartController? controllerOf(RangeChart2D widget) => widget.controller;

  @override
  void resetZoom() {} // no zoom on this chart

  @override
  void dispose() {
    _hidden.dispose();
    super.dispose();
  }

  Cartesian2DAxes _axes(Size size, List<RangeSeries> visible, ChartTheme theme) {
    double lo = double.infinity, hi = -double.infinity;
    for (final s in visible) {
      for (final v in s.values) {
        if (v == null) continue;
        lo = math.min(lo, math.min(v.low, v.high));
        hi = math.max(hi, math.max(v.low, v.high));
      }
    }
    if (!lo.isFinite) (lo, hi) = (0.0, 1.0);
    final pad = (hi - lo) * 0.08 + (hi == lo ? 1 : 0);
    final (a, z) = Cartesian2DAxes.niceExtent(lo - pad, hi + pad);
    return Cartesian2DAxes(plotArea: Cartesian2DAxes.computePlotArea(size), minX: 0, maxX: 1, minY: a, maxY: z, theme: theme);
  }

  /// x of series [s] (of [count]) within category [i]'s slot: side by side
  /// for bars/dumbbells/error bars, centred for bands.
  double _x(Rect plot, int i, int s, int count) {
    final slot = plot.width / widget.categories.length;
    if (widget.style == RangeChartStyle.area || count == 1) return plot.left + (i + 0.5) * slot;
    final w = slot * 0.7 / count;
    return plot.left + i * slot + slot * 0.15 + (s + 0.5) * w;
  }

  RangeHit? _hit(Offset pos, Size size, List<RangeSeries> visible, ChartTheme theme) {
    final axes = _axes(size, visible, theme);
    final plot = axes.plotArea;
    if (!plot.contains(pos) || widget.categories.isEmpty) return null;
    final i = ((pos.dx - plot.left) / (plot.width / widget.categories.length)).floor().clamp(0, widget.categories.length - 1);
    RangeHit? best;
    double bestDist = double.infinity;
    for (int s = 0; s < visible.length; s++) {
      final v = i < visible[s].values.length ? visible[s].values[i] : null;
      if (v == null) continue;
      // Nearest series by horizontal position, then by distance to the span.
      final dx = (_x(plot, i, s, visible.length) - pos.dx).abs();
      final yLo = axes.toScreenY(math.max(v.low, v.high)), yHi = axes.toScreenY(math.min(v.low, v.high));
      final dy = pos.dy < yLo ? yLo - pos.dy : (pos.dy > yHi ? pos.dy - yHi : 0);
      final d = dx + dy;
      if (d < bestDist) {
        bestDist = d;
        best = RangeHit(visible[s].name, i, widget.categories[i], v);
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    if (widget.categories.isEmpty || widget.series.isEmpty) {
      return ChartFrame(
        boundaryKey: chartBoundaryKey,
        title: widget.title,
        subtitle: widget.subtitle,
        plot: ChartEmptyState(message: widget.emptyStateMessage),
      );
    }
    final f = widget.valueFormatter;
    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Range chart', widget.title, [
        '${widget.categories.length} categories',
        for (final s in widget.series)
          summarizeValues(s.name, [for (final v in s.values) if (v != null) ...[v.low, v.high]], f),
      ]),
      title: widget.title,
      subtitle: widget.subtitle,
      legendPosition: widget.legendPosition,
      legendBuilder: widget.showLegend && widget.series.length > 1
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
          return HoverPlot<RangeHit>(
            enableAnimation: widget.enableAnimation,
            animationDuration: widget.animationDuration,
            animationKey: Object.hashAll(widget.series),
            onTap: widget.onRangeTap,
            hitTest: (pos, size) => _hit(pos, size, visible, theme),
            painterBuilder: (size, hover, progress) => _RangePainter(
              axes: _axes(size, visible, theme),
              series: visible,
              xOf: _x,
              widget: widget,
              hover: hover,
              progress: Curves.easeOutCubic.transform(progress),
            ),
            tooltipBuilder: (context, hit, pointer, size) {
              final axes = _axes(size, visible, theme);
              final s = visible.indexWhere((v) => v.name == hit.series);
              final custom = widget.tooltipBuilder;
              return positionChartTooltip(
                anchor: Offset(_x(axes.plotArea, hit.index, s, visible.length), axes.toScreenY(math.max(hit.value.low, hit.value.high))),
                areaSize: size,
                cardWidth: 160,
                child: custom != null
                    ? custom(context, hit)
                    : ChartTooltipCard(
                        theme: theme,
                        width: 160,
                        title: widget.series.length > 1 ? hit.series : hit.category,
                        subtitle: [
                          if (widget.series.length > 1) hit.category,
                          if (hit.value.mid != null) 'Mid ${f(hit.value.mid!)}',
                        ].join('\n'),
                        value: '${f(hit.value.low)} – ${f(hit.value.high)}',
                      ),
              );
            },
          );
        },
      ),
    );
  }
}

class _RangePainter extends CustomPainter {
  final Cartesian2DAxes axes;
  final List<RangeSeries> series;
  final double Function(Rect plot, int i, int s, int count) xOf;
  final RangeChart2D widget;
  final RangeHit? hover;
  final double progress;

  _RangePainter({required this.axes, required this.series, required this.xOf, required this.widget, required this.hover, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final plot = axes.plotArea;
    final n = widget.categories.length;
    axes.drawGridAndAxes(
      canvas,
      yTicks: Cartesian2DAxes.niceTicks(axes.minY, axes.maxY),
      yFormatter: widget.valueFormatter,
      xAxisTitle: widget.xAxisTitle,
      yAxisTitle: widget.yAxisTitle,
      showGrid: widget.showGrid,
    );
    axes.drawXTicks(canvas, [for (int i = 0; i < n; i++) (plot.left + (i + 0.5) * plot.width / n, widget.categories[i])]);
    final refs = ReferencePainter(axes, supportsX: false);
    refs.paintBands(canvas, widget.referenceBands);

    final slot = plot.width / n;
    final barW = math.min(28.0, slot * 0.7 / math.max(1, widget.style == RangeChartStyle.area ? 1 : series.length) * 0.8);
    // Entrance: spans open out from their middles.
    (double, double) ys(RangeValue v) {
      final mid = axes.toScreenY(v.mid ?? (v.low + v.high) / 2);
      final a = axes.toScreenY(v.low), b = axes.toScreenY(v.high);
      return (mid + (a - mid) * progress, mid + (b - mid) * progress);
    }

    for (int si = 0; si < series.length; si++) {
      final s = series[si];
      final active = hover == null || hover!.series == s.name;
      final color = active ? s.color : s.color.withValues(alpha: 0.45);
      final stroke = Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;

      if (widget.style == RangeChartStyle.area) {
        final top = <Offset>[], bottom = <Offset>[], mids = <Offset>[];
        for (int i = 0; i < math.min(n, s.values.length); i++) {
          final v = s.values[i];
          if (v == null) continue;
          final x = xOf(plot, i, si, series.length);
          final (a, b) = ys(v);
          top.add(Offset(x, math.min(a, b)));
          bottom.add(Offset(x, math.max(a, b)));
          mids.add(Offset(x, axes.toScreenY(v.mid ?? (v.low + v.high) / 2)));
        }
        if (top.length > 1) {
          canvas.drawPath(Path()..addPolygon([...top, ...bottom.reversed], true), Paint()..color = color.withValues(alpha: 0.18));
          canvas.drawPath(Path()..addPolygon(mids, false),
              Paint()
                ..color = color
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2);
        }
        continue;
      }

      for (int i = 0; i < math.min(n, s.values.length); i++) {
        final v = s.values[i];
        if (v == null) continue;
        final x = xOf(plot, i, si, series.length);
        final (a, b) = ys(v);
        final hovered = hover?.series == s.name && hover?.index == i;
        switch (widget.style) {
          case RangeChartStyle.bar:
            canvas.drawRRect(
              RRect.fromRectAndRadius(Rect.fromLTRB(x - barW / 2, math.min(a, b), x + barW / 2, math.max(math.max(a, b), math.min(a, b) + 1)),
                  const Radius.circular(3)),
              Paint()..color = hovered ? s.color : color.withValues(alpha: active ? 0.85 : 0.45),
            );
          case RangeChartStyle.dumbbell:
            canvas.drawLine(Offset(x, a), Offset(x, b), stroke..color = color.withValues(alpha: 0.5));
            canvas.drawCircle(Offset(x, a), hovered ? 6 : 5, Paint()..color = color.withValues(alpha: 0.55));
            canvas.drawCircle(Offset(x, b), hovered ? 6 : 5, Paint()..color = color);
          case RangeChartStyle.errorBar:
            final cap = math.min(10.0, barW / 2);
            canvas.drawLine(Offset(x, a), Offset(x, b), stroke);
            canvas.drawLine(Offset(x - cap, a), Offset(x + cap, a), stroke);
            canvas.drawLine(Offset(x - cap, b), Offset(x + cap, b), stroke);
            canvas.drawCircle(Offset(x, axes.toScreenY(v.mid ?? (v.low + v.high) / 2)), hovered ? 5.5 : 4.5, Paint()..color = color);
          case RangeChartStyle.area:
            break;
        }
      }
    }
    refs.paintLines(canvas, widget.referenceLines);
  }

  @override
  bool shouldRepaint(covariant _RangePainter old) => true;
}
