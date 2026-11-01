import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'cartesian_axes.dart';
import 'theme.dart';
import 'chart_chrome.dart';
import 'common.dart';
import 'controller.dart';
import 'hover_plot.dart';
import 'reference.dart';

// ============================================================================
// Histogram
// ============================================================================

/// One histogram bar: values in `[start, end)` (the last bin includes `end`).
class HistogramBin {
  final double start;
  final double end;
  final int count;

  const HistogramBin(this.start, this.end, this.count);

  @override
  bool operator ==(Object other) => other is HistogramBin && other.start == start && other.end == end && other.count == count;

  @override
  int get hashCode => Object.hash(start, end, count);

  /// Bins [values] at a "nice" width (1/2/5 × 10ⁿ) aligned to multiples of
  /// that width. Pass [binWidth] to force a width, or [binCount] for a
  /// target number of bins; by default the Freedman–Diaconis rule picks one
  /// (falling back to Sturges' rule for degenerate spreads).
  static List<HistogramBin> compute(List<double> values, {int? binCount, double? binWidth}) {
    final data = values.where((v) => v.isFinite).toList()..sort();
    if (data.isEmpty) return const [];
    final lo = data.first, hi = data.last;
    if (lo == hi) return [HistogramBin(lo - 0.5, hi + 0.5, data.length)];

    double width;
    if (binWidth != null && binWidth > 0) {
      width = binWidth;
    } else {
      final target = binCount ?? _defaultBinCount(data);
      width = Cartesian2DAxes.niceStep(hi - lo, count: math.max(1, target));
    }
    final start = (lo / width).floor() * width;
    final n = math.max(1, ((hi - start) / width).floor() + 1);
    final counts = List<int>.filled(n, 0);
    for (final v in data) {
      counts[((v - start) / width).floor().clamp(0, n - 1)]++;
    }
    return [for (int i = 0; i < n; i++) HistogramBin(start + i * width, start + (i + 1) * width, counts[i])];
  }

  static int _defaultBinCount(List<double> sorted) {
    final n = sorted.length;
    final iqr = _quantile(sorted, 0.75) - _quantile(sorted, 0.25);
    final sturges = (math.log(n) / math.ln2).ceil() + 1;
    if (iqr <= 0) return sturges;
    final fdWidth = 2 * iqr / math.pow(n, 1 / 3);
    final fd = ((sorted.last - sorted.first) / fdWidth).ceil();
    return fd.clamp(1, 100);
  }
}

/// A histogram: how a set of raw values is distributed across ranges.
///
/// ```dart
/// Histogram2D(
///   values: responseTimesMs,
///   xAxisTitle: 'Response time (ms)',
///   yAxisTitle: 'Requests',
///   showMean: true,
/// )
/// ```
class Histogram2D extends StatefulWidget {
  /// Raw observations. Non-finite values are ignored.
  final List<double> values;

  /// Target number of bins; the actual width is rounded to a nice number.
  final int? binCount;

  /// Exact bin width (overrides [binCount]).
  final double? binWidth;
  final Color color;
  final String? title;
  final String? subtitle;
  final String? xAxisTitle;
  final String? yAxisTitle;
  final String emptyStateMessage;
  final String Function(double value) valueFormatter;
  final bool showGrid;

  /// Mark the mean with a vertical reference line.
  final bool showMean;
  final List<ChartReferenceLine> referenceLines;
  final List<ChartReferenceBand> referenceBands;
  final bool enableAnimation;
  final Duration animationDuration;

  /// Replaces the default tooltip card.
  final Widget Function(BuildContext context, HistogramBin bin)? tooltipBuilder;

  /// Export an image from outside the chart.
  final ChartController? controller;
  final ValueChanged<HistogramBin>? onBinTap;

  const Histogram2D({
    super.key,
    required this.values,
    this.binCount,
    this.binWidth,
    this.color = Colors.indigo,
    this.title,
    this.subtitle,
    this.xAxisTitle,
    this.yAxisTitle,
    this.emptyStateMessage = 'No data to display',
    this.valueFormatter = Cartesian2DAxes.formatNumber,
    this.showGrid = true,
    this.showMean = false,
    this.referenceLines = const [],
    this.referenceBands = const [],
    this.enableAnimation = true,
    this.animationDuration = const Duration(milliseconds: 550),
    this.tooltipBuilder,
    this.controller,
    this.onBinTap,
  });

  @override
  State<Histogram2D> createState() => _Histogram2DState();
}

class _Histogram2DState extends State<Histogram2D> with ChartControllerMixin<Histogram2D> {
  late List<HistogramBin> _bins;
  late int _total;

  @override
  ChartController? controllerOf(Histogram2D widget) => widget.controller;

  @override
  void resetZoom() {} // no zoom on this chart

  @override
  void initState() {
    super.initState();
    _computeBins();
  }

  @override
  void didUpdateWidget(covariant Histogram2D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.values, widget.values) ||
        oldWidget.binCount != widget.binCount ||
        oldWidget.binWidth != widget.binWidth) {
      _computeBins();
    }
  }

  void _computeBins() {
    _bins = HistogramBin.compute(widget.values, binCount: widget.binCount, binWidth: widget.binWidth);
    _total = _bins.fold(0, (s, b) => s + b.count);
  }

  Cartesian2DAxes _axes(Size size, ChartTheme theme) {
    final maxCount = _bins.fold(0, (m, b) => math.max(m, b.count));
    final (_, top) = Cartesian2DAxes.niceExtent(0, maxCount.toDouble());
    return Cartesian2DAxes(
      plotArea: Cartesian2DAxes.computePlotArea(size),
      minX: _bins.first.start,
      maxX: _bins.last.end,
      minY: 0,
      maxY: top == 0 ? 1 : top,
      theme: theme,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    if (_bins.isEmpty) {
      return ChartFrame(
        boundaryKey: chartBoundaryKey,
        title: widget.title,
        subtitle: widget.subtitle,
        plot: ChartEmptyState(message: widget.emptyStateMessage),
      );
    }
    final finite = widget.values.where((v) => v.isFinite);
    final mean = finite.fold(0.0, (s, v) => s + v) / finite.length;
    final lines = [
      if (widget.showMean) ChartReferenceLine.x(mean, label: 'Mean ${widget.valueFormatter(mean)}'),
      ...widget.referenceLines,
    ];

    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Histogram', widget.title, [summarizeValues('$_total values', widget.values, widget.valueFormatter), '${_bins.length} bins']),
      title: widget.title,
      subtitle: widget.subtitle,
      plot: HoverPlot<HistogramBin>(
        enableAnimation: widget.enableAnimation,
        animationDuration: widget.animationDuration,
        animationKey: Object.hashAll(_bins),
        onTap: widget.onBinTap,
        hitTest: (pos, size) {
          final axes = _axes(size, theme);
          if (!axes.plotArea.contains(pos)) return null;
          final x = axes.toDataX(pos.dx);
          for (final b in _bins) {
            if (x >= b.start && x < b.end && b.count > 0) return b;
          }
          return null;
        },
        painterBuilder: (size, hover, progress) => _HistogramPainter(
          axes: _axes(size, theme),
          bins: _bins,
          color: widget.color,
          widget: widget,
          lines: lines,
          hover: hover,
          progress: Curves.easeOutCubic.transform(progress),
        ),
        tooltipBuilder: (context, bin, pointer, size) {
          final axes = _axes(size, theme);
          final custom = widget.tooltipBuilder;
          final f = widget.valueFormatter;
          return positionChartTooltip(
            anchor: Offset(axes.toScreenX((bin.start + bin.end) / 2), axes.toScreenY(bin.count.toDouble())),
            areaSize: size,
            child: custom != null
                ? custom(context, bin)
                : ChartTooltipCard(
                    theme: theme,
                    width: 150,
                    title: '${f(bin.start)} – ${f(bin.end)}',
                    subtitle: '${(bin.count / _total * 100).toStringAsFixed(1)}% of $_total',
                    value: '${bin.count}',
                  ),
          );
        },
      ),
    );
  }
}

class _HistogramPainter extends CustomPainter {
  final Cartesian2DAxes axes;
  final List<HistogramBin> bins;
  final Color color;
  final Histogram2D widget;
  final List<ChartReferenceLine> lines;
  final HistogramBin? hover;
  final double progress;

  _HistogramPainter({
    required this.axes,
    required this.bins,
    required this.color,
    required this.widget,
    required this.lines,
    required this.hover,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    axes.drawGridAndAxes(
      canvas,
      yTicks: Cartesian2DAxes.niceTicks(axes.minY, axes.maxY).where((t) => t == t.roundToDouble()).toList(),
      yFormatter: Cartesian2DAxes.formatNumber,
      xAxisTitle: widget.xAxisTitle,
      yAxisTitle: widget.yAxisTitle,
      showGrid: widget.showGrid,
    );
    // Ticks on bin edges, thinned to avoid overlap.
    axes.drawXTicks(canvas, [
      for (final b in bins) (axes.toScreenX(b.start), widget.valueFormatter(b.start)),
      (axes.toScreenX(bins.last.end), widget.valueFormatter(bins.last.end)),
    ]);

    final references = ReferencePainter(axes);
    references.paintBands(canvas, widget.referenceBands);

    final zero = axes.toScreenY(0);
    for (final b in bins) {
      if (b.count == 0) continue;
      final top = zero + (axes.toScreenY(b.count.toDouble()) - zero) * progress;
      // A 1px gap between bars keeps adjacent bins distinguishable.
      final rect = Rect.fromLTRB(axes.toScreenX(b.start) + 0.5, top, axes.toScreenX(b.end) - 0.5, zero);
      canvas.drawRect(rect, Paint()..color = b == hover ? color : color.withValues(alpha: 0.8));
    }

    references.paintLines(canvas, lines);
  }

  @override
  bool shouldRepaint(covariant _HistogramPainter old) => true;
}

// ============================================================================
// Box plot
// ============================================================================

/// Linear-interpolation quantile (the "R-7" / Excel `PERCENTILE.INC` method)
/// of already-sorted data.
double _quantile(List<double> sorted, double q) {
  if (sorted.length == 1) return sorted.first;
  final pos = (sorted.length - 1) * q;
  final i = pos.floor();
  final frac = pos - i;
  return i + 1 < sorted.length ? sorted[i] + (sorted[i + 1] - sorted[i]) * frac : sorted[i];
}

/// Five-number summary (plus mean and outliers) of a sample, as drawn by
/// [BoxPlot2D]. Whiskers reach the most extreme values within 1.5 × IQR of
/// the box; anything beyond is an outlier.
class BoxPlotStats {
  final int count;
  final double min;
  final double q1;
  final double median;
  final double q3;
  final double max;
  final double mean;

  /// Lower and upper whisker ends.
  final double whiskerLow;
  final double whiskerHigh;
  final List<double> outliers;

  const BoxPlotStats({
    required this.count,
    required this.min,
    required this.q1,
    required this.median,
    required this.q3,
    required this.max,
    required this.mean,
    required this.whiskerLow,
    required this.whiskerHigh,
    required this.outliers,
  });

  double get iqr => q3 - q1;

  /// Null when [values] has no finite numbers.
  static BoxPlotStats? fromValues(List<double> values) {
    final s = values.where((v) => v.isFinite).toList()..sort();
    if (s.isEmpty) return null;
    final q1 = _quantile(s, 0.25), q3 = _quantile(s, 0.75);
    final fenceLow = q1 - 1.5 * (q3 - q1), fenceHigh = q3 + 1.5 * (q3 - q1);
    final inside = s.where((v) => v >= fenceLow && v <= fenceHigh);
    return BoxPlotStats(
      count: s.length,
      min: s.first,
      q1: q1,
      median: _quantile(s, 0.5),
      q3: q3,
      max: s.last,
      mean: s.fold(0.0, (a, b) => a + b) / s.length,
      whiskerLow: inside.isEmpty ? q1 : inside.first,
      whiskerHigh: inside.isEmpty ? q3 : inside.last,
      outliers: s.where((v) => v < fenceLow || v > fenceHigh).toList(),
    );
  }
}

/// One box in a [BoxPlot2D]: a label and its raw sample.
class BoxPlotGroup {
  final String label;
  final List<double> values;

  /// Defaults to the chart's [BoxPlot2D.color].
  final Color? color;

  const BoxPlotGroup({required this.label, required this.values, this.color});
}

/// Box-and-whisker plot comparing the spread of several samples.
///
/// ```dart
/// BoxPlot2D(
///   groups: [
///     BoxPlotGroup(label: 'Team A', values: [12, 15, 14, 19, 22, 13, 41]),
///     BoxPlotGroup(label: 'Team B', values: [18, 21, 17, 25, 24, 20]),
///   ],
///   yAxisTitle: 'Minutes',
/// )
/// ```
class BoxPlot2D extends StatefulWidget {
  final List<BoxPlotGroup> groups;
  final Color color;

  /// Mark each group's mean with a small diamond.
  final bool showMean;

  /// Draw outliers as dots.
  final bool showOutliers;
  final String? title;
  final String? subtitle;
  final String? xAxisTitle;
  final String? yAxisTitle;
  final String emptyStateMessage;
  final String Function(double value) valueFormatter;
  final bool showGrid;
  final List<ChartReferenceLine> referenceLines;
  final List<ChartReferenceBand> referenceBands;
  final bool enableAnimation;
  final Duration animationDuration;

  /// Replaces the default tooltip card.
  final Widget Function(BuildContext context, String label, BoxPlotStats stats)? tooltipBuilder;

  /// Export an image from outside the chart.
  final ChartController? controller;

  const BoxPlot2D({
    super.key,
    required this.groups,
    this.color = Colors.indigo,
    this.showMean = true,
    this.showOutliers = true,
    this.title,
    this.subtitle,
    this.xAxisTitle,
    this.yAxisTitle,
    this.emptyStateMessage = 'No data to display',
    this.valueFormatter = Cartesian2DAxes.formatNumber,
    this.showGrid = true,
    this.referenceLines = const [],
    this.referenceBands = const [],
    this.enableAnimation = true,
    this.animationDuration = const Duration(milliseconds: 550),
    this.tooltipBuilder,
    this.controller,
  });

  @override
  State<BoxPlot2D> createState() => _BoxPlot2DState();
}

class _BoxPlot2DState extends State<BoxPlot2D> with ChartControllerMixin<BoxPlot2D> {
  late List<BoxPlotStats?> _stats;

  @override
  ChartController? controllerOf(BoxPlot2D widget) => widget.controller;

  @override
  void resetZoom() {} // no zoom on this chart

  @override
  void initState() {
    super.initState();
    _stats = [for (final g in widget.groups) BoxPlotStats.fromValues(g.values)];
  }

  @override
  void didUpdateWidget(covariant BoxPlot2D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.groups, widget.groups)) {
      _stats = [for (final g in widget.groups) BoxPlotStats.fromValues(g.values)];
    }
  }

  Cartesian2DAxes _axes(Size size, ChartTheme theme) {
    double lo = double.infinity, hi = -double.infinity;
    for (final s in _stats.whereType<BoxPlotStats>()) {
      lo = math.min(lo, widget.showOutliers ? s.min : s.whiskerLow);
      hi = math.max(hi, widget.showOutliers ? s.max : s.whiskerHigh);
    }
    final pad = (hi - lo) * 0.05 + (hi == lo ? 1 : 0);
    final (a, b) = Cartesian2DAxes.niceExtent(lo - pad, hi + pad);
    return Cartesian2DAxes(plotArea: Cartesian2DAxes.computePlotArea(size), minX: 0, maxX: 1, minY: a, maxY: b, theme: theme);
  }

  double _slotCenter(Rect plot, int i) => plot.left + (i + 0.5) * plot.width / widget.groups.length;

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    if (_stats.every((s) => s == null)) {
      return ChartFrame(
        boundaryKey: chartBoundaryKey,
        title: widget.title,
        subtitle: widget.subtitle,
        plot: ChartEmptyState(message: widget.emptyStateMessage),
      );
    }
    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Box plot', widget.title, [for (int i = 0; i < widget.groups.length; i++) if (_stats[i] != null) '${widget.groups[i].label}: median ${widget.valueFormatter(_stats[i]!.median)}, ${_stats[i]!.count} values']),
      title: widget.title,
      subtitle: widget.subtitle,
      plot: HoverPlot<int>(
        enableAnimation: widget.enableAnimation,
        animationDuration: widget.animationDuration,
        animationKey: Object.hashAll([for (final g in widget.groups) Object.hashAll(g.values)]),
        hitTest: (pos, size) {
          final plot = _axes(size, theme).plotArea;
          if (!plot.contains(pos)) return null;
          final i = ((pos.dx - plot.left) / (plot.width / widget.groups.length)).floor().clamp(0, widget.groups.length - 1);
          return _stats[i] == null ? null : i;
        },
        painterBuilder: (size, hover, progress) => _BoxPlotPainter(
          axes: _axes(size, theme),
          widget: widget,
          stats: _stats,
          hover: hover,
          progress: Curves.easeOutCubic.transform(progress),
        ),
        tooltipBuilder: (context, i, pointer, size) {
          final s = _stats[i]!;
          final axes = _axes(size, theme);
          final custom = widget.tooltipBuilder;
          final f = widget.valueFormatter;
          return positionChartTooltip(
            anchor: Offset(_slotCenter(axes.plotArea, i), axes.toScreenY(s.q3)),
            areaSize: size,
            cardWidth: 160,
            child: custom != null
                ? custom(context, widget.groups[i].label, s)
                : ChartTooltipCard(
                    theme: theme,
                    width: 160,
                    title: '${widget.groups[i].label}  (n=${s.count})',
                    subtitle: 'Max ${f(s.max)}\nQ3 ${f(s.q3)}\nQ1 ${f(s.q1)}\nMin ${f(s.min)}'
                        '${s.outliers.isEmpty ? '' : '\n${s.outliers.length} outlier${s.outliers.length == 1 ? '' : 's'}'}',
                    value: 'Median ${f(s.median)}',
                  ),
          );
        },
      ),
    );
  }
}

class _BoxPlotPainter extends CustomPainter {
  final Cartesian2DAxes axes;
  final BoxPlot2D widget;
  final List<BoxPlotStats?> stats;
  final int? hover;
  final double progress;

  _BoxPlotPainter({required this.axes, required this.widget, required this.stats, required this.hover, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final plot = axes.plotArea;
    axes.drawGridAndAxes(
      canvas,
      yTicks: Cartesian2DAxes.niceTicks(axes.minY, axes.maxY),
      yFormatter: widget.valueFormatter,
      xAxisTitle: widget.xAxisTitle,
      yAxisTitle: widget.yAxisTitle,
      showGrid: widget.showGrid,
    );
    final slot = plot.width / widget.groups.length;
    axes.drawXTicks(canvas, [
      for (int i = 0; i < widget.groups.length; i++) (plot.left + (i + 0.5) * slot, widget.groups[i].label),
    ]);

    final references = ReferencePainter(axes, supportsX: false);
    references.paintBands(canvas, widget.referenceBands);

    for (int i = 0; i < stats.length; i++) {
      final s = stats[i];
      if (s == null) continue;
      final color = widget.groups[i].color ?? widget.color;
      final cx = plot.left + (i + 0.5) * slot;
      final w = math.min(slot * 0.5, 80.0);
      final mid = axes.toScreenY(s.median);
      // Entrance: everything grows vertically out of the median.
      double y(double v) => mid + (axes.toScreenY(v) - mid) * progress;

      final stroke = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = hover == i ? 2 : 1.4;

      // Whiskers + caps
      canvas.drawLine(Offset(cx, y(s.whiskerHigh)), Offset(cx, y(s.q3)), stroke);
      canvas.drawLine(Offset(cx, y(s.q1)), Offset(cx, y(s.whiskerLow)), stroke);
      canvas.drawLine(Offset(cx - w / 4, y(s.whiskerHigh)), Offset(cx + w / 4, y(s.whiskerHigh)), stroke);
      canvas.drawLine(Offset(cx - w / 4, y(s.whiskerLow)), Offset(cx + w / 4, y(s.whiskerLow)), stroke);

      // Box + median
      final box = Rect.fromLTRB(cx - w / 2, y(s.q3), cx + w / 2, y(s.q1));
      canvas.drawRect(box, Paint()..color = color.withValues(alpha: hover == i ? 0.35 : 0.22));
      canvas.drawRect(box, stroke);
      canvas.drawLine(Offset(box.left, mid), Offset(box.right, mid), stroke..strokeWidth = 2.4);

      if (widget.showMean) {
        final m = Offset(cx, y(s.mean));
        canvas.drawPath(
          Path()
            ..moveTo(m.dx, m.dy - 4)
            ..lineTo(m.dx + 4, m.dy)
            ..lineTo(m.dx, m.dy + 4)
            ..lineTo(m.dx - 4, m.dy)
            ..close(),
          Paint()..color = color,
        );
      }
      if (widget.showOutliers && progress >= 1) {
        for (final o in s.outliers) {
          canvas.drawCircle(Offset(cx, axes.toScreenY(o)), 3,
              Paint()
                ..color = color
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.2);
        }
      }
    }

    references.paintLines(canvas, widget.referenceLines);
  }

  @override
  bool shouldRepaint(covariant _BoxPlotPainter old) => true;
}
