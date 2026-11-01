import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'models.dart';
import 'legend.dart';
import 'cartesian_axes.dart';
import 'theme.dart';
import 'chart_chrome.dart';
import 'common.dart';
import 'controller.dart';
import 'reference.dart';
import 'curves.dart';

/// How a [ComboSeries] is drawn.
enum ComboSeriesType { bar, line }

/// One series of a [ComboChart2D]: values aligned 1:1 with the chart's
/// categories, drawn as bars or a line.
class ComboSeries {
  final String name;
  final Color color;
  final List<double> values;
  final ComboSeriesType type;

  /// Plot this series against the secondary (right-hand) y-axis. Only
  /// honored for line series — bars always use the primary axis, since
  /// bars on two different scales side by side are hard to read.
  final bool secondaryAxis;

  const ComboSeries({
    required this.name,
    required this.color,
    required this.values,
    this.type = ComboSeriesType.bar,
    this.secondaryAxis = false,
  });

  /// Shorthand for a line series.
  const ComboSeries.line({
    required this.name,
    required this.color,
    required this.values,
    this.secondaryAxis = false,
  }) : type = ComboSeriesType.line;

  bool get _onSecondary => secondaryAxis && type == ComboSeriesType.line;

  @override
  bool operator ==(Object other) =>
      other is ComboSeries &&
      other.name == name &&
      other.color == color &&
      other.type == type &&
      other.secondaryAxis == secondaryAxis &&
      listEquals(other.values, values);

  @override
  int get hashCode => Object.hash(name, color, type, secondaryAxis, Object.hashAll(values));
}

/// Builds a custom tooltip for a hovered category of a [ComboChart2D]:
/// every visible series with its value there (null where it has none).
typedef ComboTooltipBuilder = Widget Function(
    BuildContext context, String category, List<(ComboSeries series, double? value)> values);

/// Bars and lines over the same categories — e.g. monthly revenue as bars
/// with growth % as a line on a second y-axis.
///
/// ```dart
/// ComboChart2D(
///   categories: ['Jan', 'Feb', 'Mar', 'Apr'],
///   series: [
///     ComboSeries(name: 'Revenue', color: Colors.blue, values: [120, 150, 170, 160]),
///     ComboSeries.line(name: 'Growth %', color: Colors.orange, values: [4, 25, 13, -6], secondaryAxis: true),
///   ],
///   yAxisTitle: 'Revenue',
///   secondaryYAxisTitle: 'Growth %',
/// )
/// ```
///
/// Hovering anywhere over a category shows every series' value there in one
/// tooltip.
class ComboChart2D extends StatefulWidget {
  final List<String> categories;
  final List<ComboSeries> series;
  final String? title;
  final String? subtitle;
  final String? xAxisTitle;
  final String? yAxisTitle;

  /// Title for the right-hand axis. The axis itself appears only when some
  /// line series sets [ComboSeries.secondaryAxis].
  final String? secondaryYAxisTitle;
  final String emptyStateMessage;
  final String Function(double value) yTickFormatter;

  /// Defaults to [yTickFormatter].
  final String Function(double value)? secondaryYTickFormatter;

  /// Stack the bar series instead of grouping them side by side.
  final bool stackedBars;
  final LineChartCurve curve;
  final double lineWidth;
  final bool showGrid;
  final bool showLegend;
  final ChartLegendPosition legendPosition;

  /// Primary-axis marker lines. Lines on the x-axis are ignored.
  final List<ChartReferenceLine> referenceLines;

  /// Primary-axis shaded ranges, drawn behind the data.
  final List<ChartReferenceBand> referenceBands;

  final bool enableAnimation;
  final Duration animationDuration;

  /// Replaces the default tooltip card.
  final ComboTooltipBuilder? tooltipBuilder;

  /// Export an image from outside the chart (this chart has no zoom).
  final ChartController? controller;

  /// Fired once per tap on a category, with its index into [categories].
  final void Function(String category, int index)? onCategoryTap;

  const ComboChart2D({
    super.key,
    required this.categories,
    required this.series,
    this.title,
    this.subtitle,
    this.xAxisTitle,
    this.yAxisTitle,
    this.secondaryYAxisTitle,
    this.emptyStateMessage = 'No data to display',
    this.yTickFormatter = Cartesian2DAxes.formatNumber,
    this.secondaryYTickFormatter,
    this.stackedBars = false,
    this.curve = LineChartCurve.straight,
    this.lineWidth = 2.2,
    this.showGrid = true,
    this.showLegend = true,
    this.legendPosition = ChartLegendPosition.bottom,
    this.referenceLines = const [],
    this.referenceBands = const [],
    this.enableAnimation = true,
    this.animationDuration = const Duration(milliseconds: 600),
    this.tooltipBuilder,
    this.controller,
    this.onCategoryTap,
  });

  @override
  State<ComboChart2D> createState() => _ComboChart2DState();
}

/// Positions shared by the painter and hit-testing.
class _ComboLayout {
  final List<String> categories;
  final List<ComboSeries> series;
  final bool stackedBars;
  final Rect plotArea;
  final Cartesian2DAxes primary;
  final Cartesian2DAxes? secondary;

  _ComboLayout._(this.categories, this.series, this.stackedBars, this.plotArea, this.primary, this.secondary);

  factory _ComboLayout(Size size, List<String> categories, List<ComboSeries> series, bool stackedBars, ChartTheme theme,
      {required bool reserveSecondary}) {
    final plotArea = Cartesian2DAxes.computePlotArea(size, rightPad: reserveSecondary ? 52 : 12);
    double v(ComboSeries s, int i) => i < s.values.length ? s.values[i] : 0;

    // Primary range: bars (summed when stacked) and primary-axis lines.
    double pMin = 0, pMax = 0;
    final bars = series.where((s) => s.type == ComboSeriesType.bar).toList();
    for (int i = 0; i < categories.length; i++) {
      if (stackedBars) {
        double pos = 0, neg = 0;
        for (final s in bars) {
          v(s, i) >= 0 ? pos += v(s, i) : neg += v(s, i);
        }
        pMin = math.min(pMin, neg);
        pMax = math.max(pMax, pos);
      } else {
        for (final s in bars) {
          pMin = math.min(pMin, v(s, i));
          pMax = math.max(pMax, v(s, i));
        }
      }
    }
    for (final s in series.where((s) => s.type == ComboSeriesType.line && !s._onSecondary)) {
      for (final value in s.values) {
        pMin = math.min(pMin, value);
        pMax = math.max(pMax, value);
      }
    }
    final (p0, p1) = Cartesian2DAxes.niceExtent(pMin, pMax);
    final primary = Cartesian2DAxes(plotArea: plotArea, minX: 0, maxX: 1, minY: p0, maxY: p1 == p0 ? p0 + 1 : p1, theme: theme);

    Cartesian2DAxes? secondary;
    final secondaryValues = [for (final s in series.where((s) => s._onSecondary)) ...s.values];
    if (secondaryValues.isNotEmpty) {
      final sMin = math.min(0.0, secondaryValues.reduce(math.min));
      final sMax = math.max(0.0, secondaryValues.reduce(math.max));
      final (s0, s1) = Cartesian2DAxes.niceExtent(sMin, sMax);
      secondary = Cartesian2DAxes(plotArea: plotArea, minX: 0, maxX: 1, minY: s0, maxY: s1 == s0 ? s0 + 1 : s1, theme: theme);
    }
    return _ComboLayout._(categories, series, stackedBars, plotArea, primary, secondary);
  }

  double get slotWidth => plotArea.width / categories.length;
  double slotCenter(int i) => plotArea.left + (i + 0.5) * slotWidth;

  /// Category index under screen x, or null outside the plot.
  int? slotAt(Offset pos) {
    if (!plotArea.contains(pos)) return null;
    return ((pos.dx - plotArea.left) / slotWidth).floor().clamp(0, categories.length - 1);
  }

  Cartesian2DAxes axesFor(ComboSeries s) => s._onSecondary && secondary != null ? secondary! : primary;

  /// (seriesIndex, categoryIndex, rect) for every bar, grown from zero by [progress].
  List<(int, int, Rect)> bars(double progress) {
    final result = <(int, int, Rect)>[];
    final barIdx = [for (int i = 0; i < series.length; i++) if (series[i].type == ComboSeriesType.bar) i];
    if (barIdx.isEmpty) return result;
    final zero = primary.toScreenY(0);
    double grow(double y) => zero + (y - zero) * progress;
    for (int c = 0; c < categories.length; c++) {
      final left = plotArea.left + c * slotWidth;
      if (stackedBars) {
        final w = slotWidth * 0.6;
        final x = left + (slotWidth - w) / 2;
        double pos = 0, neg = 0;
        for (final si in barIdx) {
          final value = c < series[si].values.length ? series[si].values[c] : 0.0;
          final from = value >= 0 ? pos : neg;
          final a = grow(primary.toScreenY(from)), b = grow(primary.toScreenY(from + value));
          result.add((si, c, Rect.fromLTRB(x, math.min(a, b), x + w, math.max(a, b))));
          value >= 0 ? pos += value : neg += value;
        }
      } else {
        final w = slotWidth * 0.7 / barIdx.length;
        for (int k = 0; k < barIdx.length; k++) {
          final si = barIdx[k];
          final value = c < series[si].values.length ? series[si].values[c] : 0.0;
          final x = left + slotWidth * 0.15 + k * w;
          final top = grow(primary.toScreenY(value));
          result.add((si, c, Rect.fromLTRB(x, math.min(zero, top), x + w, math.max(zero, top))));
        }
      }
    }
    return result;
  }

  /// Screen points of a line series (categories it has a value for).
  List<(int, Offset)> linePoints(ComboSeries s) {
    final axes = axesFor(s);
    return [
      for (int c = 0; c < math.min(s.values.length, categories.length); c++)
        (c, Offset(slotCenter(c), axes.toScreenY(s.values[c]))),
    ];
  }
}

class _ComboChart2DState extends State<ComboChart2D>
    with SingleTickerProviderStateMixin, ChartControllerMixin<ComboChart2D> {
  final ValueNotifier<Set<String>> _hiddenNotifier = ValueNotifier(const {});

  /// Hovered category index and pointer position.
  final ValueNotifier<(int, Offset)?> _hoverNotifier = ValueNotifier(null);
  late final AnimationController _controller;

  @override
  ChartController? controllerOf(ComboChart2D widget) => widget.controller;

  @override
  void resetZoom() {} // no zoom on this chart

  bool get _hasSecondary => widget.series.any((s) => s._onSecondary);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.animationDuration);
    if (widget.enableAnimation) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant ComboChart2D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.series, widget.series) || !listEquals(oldWidget.categories, widget.categories)) {
      if (widget.enableAnimation) _controller.forward(from: 0);
      _hoverNotifier.value = null;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _hiddenNotifier.dispose();
    _hoverNotifier.dispose();
    super.dispose();
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

    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Combo chart', widget.title, ['${widget.categories.length} categories', for (final s in widget.series) summarizeValues('${s.name} (${s.type.name})', s.values, widget.yTickFormatter)]),
      title: widget.title,
      subtitle: widget.subtitle,
      legendPosition: widget.legendPosition,
      legendBuilder: widget.showLegend ? _buildLegend : null,
      plot: ValueListenableBuilder<Set<String>>(
        valueListenable: _hiddenNotifier,
        builder: (context, hidden, _) {
          final visible = widget.series.where((s) => !hidden.contains(s.name)).toList();
          return LayoutBuilder(builder: (context, constraints) {
            final size = constraints.biggest;
            // Keep the right axis' space reserved even while its series are
            // hidden, so the plot doesn't jump when toggling the legend.
            final layout = _ComboLayout(size, widget.categories, visible, widget.stackedBars, theme,
                reserveSecondary: _hasSecondary);
            return MouseRegion(
              onHover: (e) => _setHover(layout, e.localPosition),
              onExit: (_) => _hoverNotifier.value = null,
              child: GestureDetector(
                onTapUp: (d) {
                  final slot = _setHover(layout, d.localPosition);
                  if (slot != null) widget.onCategoryTap?.call(widget.categories[slot], slot);
                },
                child: ValueListenableBuilder<(int, Offset)?>(
                  valueListenable: _hoverNotifier,
                  builder: (context, hover, _) => Stack(
                    children: [
                      AnimatedBuilder(
                        animation: _controller,
                        builder: (context, _) => CustomPaint(
                          size: size,
                          painter: _ComboChartPainter(
                            layout: layout,
                            theme: theme,
                            xAxisTitle: widget.xAxisTitle,
                            yAxisTitle: widget.yAxisTitle,
                            secondaryYAxisTitle: widget.secondaryYAxisTitle,
                            yTickFormatter: widget.yTickFormatter,
                            secondaryYTickFormatter: widget.secondaryYTickFormatter ?? widget.yTickFormatter,
                            curve: widget.curve,
                            lineWidth: widget.lineWidth,
                            showGrid: widget.showGrid,
                            referenceLines: widget.referenceLines,
                            referenceBands: widget.referenceBands,
                            hoveredSlot: hover?.$1,
                            progress: _controller.value,
                          ),
                        ),
                      ),
                      if (hover != null) _buildTooltip(hover, size, visible, theme),
                    ],
                  ),
                ),
              ),
            );
          });
        },
      ),
    );
  }

  int? _setHover(_ComboLayout layout, Offset pos) {
    final slot = layout.slotAt(pos);
    _hoverNotifier.value = slot == null ? null : (slot, pos);
    return slot;
  }

  Widget _buildLegend(Axis direction) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: _hiddenNotifier,
      builder: (context, hidden, _) => Chart2DLegend(
        direction: direction,
        entries: widget.series.map((s) => LegendEntry(label: s.name, color: s.color)).toList(),
        hidden: hidden,
        onToggle: (name) {
          final next = {...hidden};
          next.contains(name) ? next.remove(name) : next.add(name);
          _hiddenNotifier.value = next;
        },
      ),
    );
  }

  Widget _buildTooltip((int, Offset) hover, Size size, List<ComboSeries> visible, ChartTheme theme) {
    final (slot, pos) = hover;
    final category = widget.categories[slot];
    final values = [for (final s in visible) (s, slot < s.values.length ? s.values[slot] : null)];
    final custom = widget.tooltipBuilder;
    final secondaryFormatter = widget.secondaryYTickFormatter ?? widget.yTickFormatter;
    return positionChartTooltip(
      anchor: pos,
      areaSize: size,
      cardWidth: 170,
      child: custom != null
          ? custom(context, category, values)
          : Container(
              width: 170,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.tooltipBackgroundColor,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 3)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(category,
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12, color: theme.tooltipTextColor, fontFamily: theme.fontFamily)),
                  const SizedBox(height: 4),
                  for (final (s, v) in values)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(s.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: theme.tooltipTextColor.withValues(alpha: 0.75),
                                  fontFamily: theme.fontFamily)),
                        ),
                        Text(v == null ? '–' : (s._onSecondary ? secondaryFormatter(v) : widget.yTickFormatter(v)),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: theme.tooltipTextColor,
                                fontFamily: theme.fontFamily)),
                      ]),
                    ),
                ],
              ),
            ),
    );
  }
}

class _ComboChartPainter extends CustomPainter {
  final _ComboLayout layout;
  final ChartTheme theme;
  final String? xAxisTitle;
  final String? yAxisTitle;
  final String? secondaryYAxisTitle;
  final String Function(double) yTickFormatter;
  final String Function(double) secondaryYTickFormatter;
  final LineChartCurve curve;
  final double lineWidth;
  final bool showGrid;
  final List<ChartReferenceLine> referenceLines;
  final List<ChartReferenceBand> referenceBands;
  final int? hoveredSlot;
  final double progress;

  _ComboChartPainter({
    required this.layout,
    required this.theme,
    required this.xAxisTitle,
    required this.yAxisTitle,
    required this.secondaryYAxisTitle,
    required this.yTickFormatter,
    required this.secondaryYTickFormatter,
    required this.curve,
    required this.lineWidth,
    required this.showGrid,
    required this.referenceLines,
    required this.referenceBands,
    required this.hoveredSlot,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final primary = layout.primary;
    final plot = layout.plotArea;

    // Highlight the hovered category behind everything else.
    if (hoveredSlot != null) {
      final left = plot.left + hoveredSlot! * layout.slotWidth;
      canvas.drawRect(Rect.fromLTWH(left, plot.top, layout.slotWidth, plot.height),
          Paint()..color = theme.crosshairColor.withValues(alpha: 0.08));
    }

    primary.drawGridAndAxes(
      canvas,
      yTicks: Cartesian2DAxes.niceTicks(primary.minY, primary.maxY),
      yFormatter: yTickFormatter,
      xAxisTitle: xAxisTitle,
      yAxisTitle: yAxisTitle,
      showGrid: showGrid,
    );
    final secondary = layout.secondary;
    if (secondary != null) {
      secondary.drawRightAxis(
        canvas,
        yTicks: Cartesian2DAxes.niceTicks(secondary.minY, secondary.maxY),
        yFormatter: secondaryYTickFormatter,
        title: secondaryYAxisTitle,
      );
    }
    primary.drawXTicks(canvas, [for (int i = 0; i < layout.categories.length; i++) (layout.slotCenter(i), layout.categories[i])]);

    final references = ReferencePainter(primary, supportsX: false);
    references.paintBands(canvas, referenceBands);

    canvas.save();
    canvas.clipRect(plot.inflate(6));
    for (final (si, c, rect) in layout.bars(progress)) {
      final color = layout.series[si].color;
      canvas.drawRRect(
        RRect.fromRectAndCorners(rect, topLeft: const Radius.circular(3), topRight: const Radius.circular(3)),
        Paint()..color = c == hoveredSlot ? color : color.withValues(alpha: 0.85),
      );
    }

    // Lines reveal left-to-right.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(plot.left - 6, plot.top - 6, plot.left - 6 + (plot.width + 12) * progress, plot.bottom + 6));
    for (final s in layout.series.where((s) => s.type == ComboSeriesType.line)) {
      final pts = layout.linePoints(s);
      if (pts.isEmpty) continue;
      final path = Path();
      traceCurve(path, [for (final (_, p) in pts) p], curve);
      canvas.drawPath(
        path,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = lineWidth
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
      for (final (c, p) in pts) {
        canvas.drawCircle(p, c == hoveredSlot ? 5 : 3, Paint()..color = s.color);
      }
    }
    canvas.restore();
    canvas.restore();

    references.paintLines(canvas, referenceLines);
  }

  @override
  bool shouldRepaint(covariant _ComboChartPainter oldDelegate) => true;
}
