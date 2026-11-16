import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'cartesian_axes.dart';
import 'theme.dart';
import 'chart_chrome.dart';
import 'common.dart';
import 'controller.dart';
import 'hover_plot.dart';
import 'reference.dart';

/// One bar of a [WaterfallChart2D]: a change, or (with [isTotal]) a bar
/// showing the running total so far.
class WaterfallStep {
  final String label;

  /// The change this step adds (positive) or removes (negative). Ignored
  /// for totals, which always show the running total.
  final double value;
  final bool isTotal;

  /// Overrides the chart's increase/decrease/total color for this bar.
  final Color? color;

  const WaterfallStep({required this.label, this.value = 0, this.isTotal = false, this.color});

  /// A bar showing the running total, e.g. "Gross profit" or "Net".
  const WaterfallStep.total(this.label, {this.color})
      : value = 0,
        isTotal = true;
}

/// A [WaterfallStep] laid out: where its bar starts and ends.
class WaterfallBar {
  final WaterfallStep step;
  final int index;
  final double start;
  final double end;

  const WaterfallBar(this.step, this.index, this.start, this.end);

  /// The signed change (or, for totals, the total).
  double get delta => step.isTotal ? end : end - start;

  @override
  bool operator ==(Object other) => other is WaterfallBar && other.index == index && other.end == end;

  @override
  int get hashCode => Object.hash(index, end);

  /// Running totals for [steps], left to right.
  static List<WaterfallBar> layout(List<WaterfallStep> steps) {
    double running = 0;
    return [
      for (int i = 0; i < steps.length; i++)
        if (steps[i].isTotal)
          WaterfallBar(steps[i], i, 0, running)
        else
          WaterfallBar(steps[i], i, running, running += steps[i].value),
    ];
  }
}

/// A waterfall (bridge) chart: how a starting value is built up or worn
/// down by successive changes — revenue to profit, budget to actual, the
/// month's cash flow.
///
/// ```dart
/// WaterfallChart2D(
///   steps: [
///     WaterfallStep(label: 'Revenue', value: 420),
///     WaterfallStep(label: 'COGS', value: -180),
///     WaterfallStep.total('Gross profit'),
///     WaterfallStep(label: 'Opex', value: -120),
///     WaterfallStep(label: 'Tax', value: -25),
///     WaterfallStep.total('Net'),
///   ],
/// )
/// ```
class WaterfallChart2D extends StatefulWidget {
  final List<WaterfallStep> steps;
  final String? title;
  final String? subtitle;
  final String? yAxisTitle;
  final String emptyStateMessage;
  final String Function(double value) valueFormatter;
  final Color increaseColor;
  final Color decreaseColor;
  final Color totalColor;

  /// Dashed lines joining each bar's end to the next bar's start.
  final bool showConnectors;

  /// Print each step's change (or total) above/below its bar.
  final bool showValueLabels;
  final bool showGrid;
  final List<ChartReferenceLine> referenceLines;
  final bool enableAnimation;
  final Duration animationDuration;

  /// Replaces the default tooltip card.
  final Widget Function(BuildContext context, WaterfallBar bar)? tooltipBuilder;

  /// Export an image from outside the chart.
  final ChartController? controller;
  final ValueChanged<WaterfallBar>? onStepTap;

  const WaterfallChart2D({
    super.key,
    required this.steps,
    this.title,
    this.subtitle,
    this.yAxisTitle,
    this.emptyStateMessage = 'No data to display',
    this.valueFormatter = Cartesian2DAxes.formatNumber,
    this.increaseColor = const Color(0xFF26A69A),
    this.decreaseColor = const Color(0xFFEF5350),
    this.totalColor = const Color(0xFF5C6BC0),
    this.showConnectors = true,
    this.showValueLabels = true,
    this.showGrid = true,
    this.referenceLines = const [],
    this.enableAnimation = true,
    this.animationDuration = const Duration(milliseconds: 600),
    this.tooltipBuilder,
    this.controller,
    this.onStepTap,
  });

  @override
  State<WaterfallChart2D> createState() => _WaterfallChart2DState();
}

class _WaterfallChart2DState extends State<WaterfallChart2D> with ChartControllerMixin<WaterfallChart2D> {
  @override
  ChartController? controllerOf(WaterfallChart2D widget) => widget.controller;

  @override
  void resetZoom() {} // no zoom on this chart

  Color _color(WaterfallBar b) =>
      b.step.color ?? (b.step.isTotal ? widget.totalColor : (b.end >= b.start ? widget.increaseColor : widget.decreaseColor));

  Cartesian2DAxes _axes(Size size, List<WaterfallBar> bars, ChartTheme theme) {
    double lo = 0, hi = 0;
    for (final b in bars) {
      lo = math.min(lo, math.min(b.start, b.end));
      hi = math.max(hi, math.max(b.start, b.end));
    }
    final (a, z) = Cartesian2DAxes.niceExtent(lo, hi);
    return Cartesian2DAxes(
      plotArea: Cartesian2DAxes.computePlotArea(size),
      minX: 0,
      maxX: 1,
      minY: a,
      maxY: z == a ? a + 1 : z,
      theme: theme,
    );
  }

  /// Screen rect of bar [b] (grown toward its start by [progress]).
  Rect _rect(Cartesian2DAxes axes, WaterfallBar b, int count, [double progress = 1]) {
    final slot = axes.plotArea.width / count;
    final left = axes.plotArea.left + b.index * slot + slot * 0.18;
    final y0 = axes.toScreenY(b.start), y1 = axes.toScreenY(b.end);
    final grown = y0 + (y1 - y0) * progress;
    return Rect.fromLTRB(left, math.min(y0, grown), left + slot * 0.64, math.max(math.max(y0, grown), math.min(y0, grown) + 1));
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    if (widget.steps.isEmpty) {
      return ChartFrame(
        boundaryKey: chartBoundaryKey,
        title: widget.title,
        subtitle: widget.subtitle,
        plot: ChartEmptyState(message: widget.emptyStateMessage),
      );
    }
    final bars = WaterfallBar.layout(widget.steps);
    final f = widget.valueFormatter;
    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Waterfall chart', widget.title, [
        for (final b in bars) '${b.step.label}: ${b.step.isTotal ? 'total ${f(b.end)}' : '${b.delta >= 0 ? '+' : ''}${f(b.delta)}'}',
      ]),
      title: widget.title,
      subtitle: widget.subtitle,
      plot: HoverPlot<WaterfallBar>(
        enableAnimation: widget.enableAnimation,
        animationDuration: widget.animationDuration,
        animationKey: Object.hashAll(bars),
        onTap: widget.onStepTap,
        hitTest: (pos, size) {
          final axes = _axes(size, bars, theme);
          if (!axes.plotArea.contains(pos)) return null;
          final i = ((pos.dx - axes.plotArea.left) / (axes.plotArea.width / bars.length)).floor();
          return i >= 0 && i < bars.length ? bars[i] : null;
        },
        painterBuilder: (size, hover, progress) => _WaterfallPainter(
          axes: _axes(size, bars, theme),
          bars: bars,
          rectFor: (axes, b, p) => _rect(axes, b, bars.length, p),
          colorFor: _color,
          widget: widget,
          hover: hover,
          progress: Curves.easeOutCubic.transform(progress),
        ),
        tooltipBuilder: (context, b, pointer, size) {
          final rect = _rect(_axes(size, bars, theme), b, bars.length);
          final custom = widget.tooltipBuilder;
          return positionChartTooltip(
            anchor: Offset(rect.right, rect.top),
            areaSize: size,
            cardWidth: 160,
            child: custom != null
                ? custom(context, b)
                : ChartTooltipCard(
                    theme: theme,
                    width: 160,
                    title: b.step.label,
                    subtitle: b.step.isTotal ? 'Total' : '${f(b.start)} → ${f(b.end)}',
                    value: b.step.isTotal ? f(b.end) : '${b.delta >= 0 ? '+' : ''}${f(b.delta)}',
                  ),
          );
        },
      ),
    );
  }
}

class _WaterfallPainter extends CustomPainter {
  final Cartesian2DAxes axes;
  final List<WaterfallBar> bars;
  final Rect Function(Cartesian2DAxes axes, WaterfallBar bar, double progress) rectFor;
  final Color Function(WaterfallBar bar) colorFor;
  final WaterfallChart2D widget;
  final WaterfallBar? hover;
  final double progress;

  _WaterfallPainter({
    required this.axes,
    required this.bars,
    required this.rectFor,
    required this.colorFor,
    required this.widget,
    required this.hover,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final theme = axes.theme;
    axes.drawGridAndAxes(
      canvas,
      yTicks: Cartesian2DAxes.niceTicks(axes.minY, axes.maxY),
      yFormatter: widget.valueFormatter,
      yAxisTitle: widget.yAxisTitle,
      showGrid: widget.showGrid,
    );
    axes.drawXTicks(canvas, [for (final b in bars) (rectFor(axes, b, 1).center.dx, b.step.label)]);

    // Connectors: from each bar's end level across to the next bar.
    if (widget.showConnectors && progress >= 1) {
      final paint = Paint()
        ..color = theme.crosshairColor
        ..strokeWidth = 1;
      for (int i = 0; i + 1 < bars.length; i++) {
        final a = rectFor(axes, bars[i], 1), b = rectFor(axes, bars[i + 1], 1);
        final y = axes.toScreenY(bars[i].end);
        axes.dashedLine(canvas, Offset(a.right, y), Offset(b.left, y), paint);
      }
    }

    for (final b in bars) {
      final rect = rectFor(axes, b, progress);
      final color = colorFor(b);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)),
          Paint()..color = hover == null || hover == b ? color : color.withValues(alpha: 0.75));
      if (widget.showValueLabels && progress >= 1) {
        final f = widget.valueFormatter;
        final text = b.step.isTotal ? f(b.end) : '${b.delta >= 0 ? '+' : ''}${f(b.delta)}';
        final s = axes.measureLabel(text);
        // Above upward/total bars, below downward ones.
        final above = b.step.isTotal ? b.end >= 0 : b.end >= b.start;
        final y = above ? rect.top - s.height - 2 : rect.bottom + 2;
        axes.drawLabel(canvas, text, Offset(rect.center.dx - s.width / 2, y), color: theme.axisColor);
      }
    }

    ReferencePainter(axes, supportsX: false).paintLines(canvas, widget.referenceLines);
  }

  @override
  bool shouldRepaint(covariant _WaterfallPainter old) => true;
}
