import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'models.dart';
import 'legend.dart';
import 'cartesian_axes.dart';
import 'theme.dart';
import 'chart_chrome.dart';
import 'zoom.dart';
import 'common.dart';
import 'controller.dart';
import 'reference.dart';
import 'time_axis.dart';
import 'curves.dart';
import 'downsample.dart';

typedef _LineHover = ({String series, ChartPoint point, Offset screenPos});

/// Transient interaction state for [LineChart2D] — hover, an in-progress
/// drag-selection rectangle, and the current zoom window. Held in a single
/// [ValueNotifier] so pointer movement never triggers `setState()`; only
/// the canvas + tooltip subtree rebuilds, not the legend or header.
class _LineInteraction {
  final _LineHover? hover;
  final Rect? dragRectScreen;
  final ChartZoomWindow? zoom;

  const _LineInteraction({this.hover, this.dragRectScreen, this.zoom});

  _LineInteraction copyWith({
    _LineHover? hover,
    bool clearHover = false,
    Rect? dragRectScreen,
    bool clearDragRect = false,
    ChartZoomWindow? zoom,
    bool clearZoom = false,
  }) {
    return _LineInteraction(
      hover: clearHover ? null : (hover ?? this.hover),
      dragRectScreen: clearDragRect ? null : (dragRectScreen ?? this.dragRectScreen),
      zoom: clearZoom ? null : (zoom ?? this.zoom),
    );
  }
}

/// A generic multi-series line / area chart with drag-to-zoom.
///
/// ```dart
/// LineChart2D(
///   title: 'Monthly Revenue',
///   series: [
///     XySeries(name: 'Revenue', color: Colors.blue, data: [
///       ChartPoint(x: 1, y: 100, label: 'Jan'),
///       ChartPoint(x: 2, y: 140, label: 'Feb'),
///     ]),
///   ],
///   curve: LineChartCurve.smooth,
///   xAxisTitle: 'Month',
///   yAxisTitle: 'Revenue',
///   onPointTap: (series, point) => print('$series: ${point?.y}'),
/// )
/// ```
///
/// For dates on the x-axis, build points with [ChartPoint.at] and set
/// `xAxisType: ChartAxisType.time`.
///
/// Drag across the plot to zoom into that x-range (y auto-rescales to fit
/// the visible slice). A reset button appears while zoomed.
class LineChart2D extends StatefulWidget {
  final List<XySeries> series;
  final String? title;
  final String? subtitle;
  final String? xAxisTitle;
  final String? yAxisTitle;
  final String emptyStateMessage;

  /// How x values are interpreted. With [ChartAxisType.time], x is
  /// milliseconds since epoch (see [ChartPoint.at]) and ticks fall on
  /// calendar boundaries.
  final ChartAxisType xAxisType;

  /// Formats x-axis tick values. Ignored for points that set
  /// [ChartPoint.label] — those always show their own label on the x-axis.
  /// Defaults to plain numbers, or dates/times on a time axis.
  final String Function(double value)? xTickFormatter;
  final String Function(double value) yTickFormatter;

  final LineChartCurve curve;

  /// Shade the area under each line.
  final bool filled;

  /// Stack series on top of each other: each series' y is added to the sum
  /// of the series before it at the same x (linearly interpolated where x
  /// values differ). Combine with [filled] for a stacked area chart.
  /// Tooltips and callbacks still report each point's own y.
  final bool stacked;

  final bool showGrid;
  final bool showLegend;
  final ChartLegendPosition legendPosition;
  final bool showPoints;
  final bool showCrosshair;
  final double lineWidth;
  final double pointRadius;

  /// Horizontal/vertical marker lines (targets, thresholds, "today").
  final List<ChartReferenceLine> referenceLines;

  /// Shaded ranges drawn behind the data.
  final List<ChartReferenceBand> referenceBands;

  final bool enableAnimation;
  final Duration animationDuration;

  /// What happens when [series] changes after the first build.
  final ChartUpdateAnimation updateAnimation;

  /// Follow the latest data: when set (and not zoomed), show only the last
  /// [liveWindow] x-units (e.g. `60000` for the last minute on a time axis)
  /// with y fitted to that slice. Pair with
  /// `updateAnimation: ChartUpdateAnimation.none` for streaming.
  final double? liveWindow;

  /// Thin very long series to ~1.5 points per horizontal pixel with the
  /// LTTB algorithm (keeps peaks and dips), so 100k-point series stay fast.
  /// Point markers are skipped for thinned series. Hover still uses every
  /// point.
  final bool downsample;

  /// Drag-to-zoom mode. [ChartZoomMode.x] (default) zooms the x-range and
  /// auto-rescales y; [ChartZoomMode.xy] zooms both axes to the dragged
  /// rectangle; [ChartZoomMode.none] disables zoom.
  final ChartZoomMode zoomMode;

  /// Minimum drag distance (px) before a drag counts as a zoom selection
  /// rather than an accidental nudge.
  final double zoomDragThreshold;

  /// Replaces the default tooltip card.
  final ChartPointTooltipBuilder? tooltipBuilder;

  /// Reset zoom or export an image from outside the chart.
  final ChartController? controller;

  /// Fired continuously as the pointer moves over/off a point (both mouse
  /// hover and touch). Called with `(null, null)` when nothing is hovered.
  final ChartPointCallback? onPointHover;

  /// Fired once per tap/click on a point. Not called on taps that miss.
  final ChartPointCallback? onPointTap;

  const LineChart2D({
    super.key,
    required this.series,
    this.title,
    this.subtitle,
    this.xAxisTitle,
    this.yAxisTitle,
    this.emptyStateMessage = 'No data to display',
    this.xAxisType = ChartAxisType.numeric,
    this.xTickFormatter,
    this.yTickFormatter = Cartesian2DAxes.formatNumber,
    this.curve = LineChartCurve.straight,
    this.filled = false,
    this.stacked = false,
    this.showGrid = true,
    this.showLegend = true,
    this.legendPosition = ChartLegendPosition.bottom,
    this.showPoints = true,
    this.showCrosshair = true,
    this.lineWidth = 2.2,
    this.pointRadius = 3.5,
    this.referenceLines = const [],
    this.referenceBands = const [],
    this.enableAnimation = true,
    this.animationDuration = const Duration(milliseconds: 650),
    this.updateAnimation = ChartUpdateAnimation.morph,
    this.liveWindow,
    this.downsample = true,
    this.zoomMode = ChartZoomMode.x,
    this.zoomDragThreshold = 12,
    this.tooltipBuilder,
    this.controller,
    this.onPointHover,
    this.onPointTap,
  });

  @override
  State<LineChart2D> createState() => _LineChart2DState();
}

/// A series as plotted: its points sorted by x, with the y each point is
/// drawn at (its own y, or the running total when stacked) and the y its
/// filled area starts from (null = the chart's zero baseline).
class _PlotSeries {
  final XySeries source;
  final List<ChartPoint> points;
  final List<double> plotY;
  final List<double>? baseY;

  _PlotSeries(this.source, this.points, this.plotY, this.baseY);
}

/// Sorts each series by x and, when [stacked], replaces y with running
/// totals across series.
List<_PlotSeries> _toPlotSeries(List<XySeries> series, bool stacked) {
  final sorted = [for (final s in series) [...s.data]..sort((a, b) => a.x.compareTo(b.x))];
  if (!stacked) {
    return [
      for (int i = 0; i < series.length; i++) _PlotSeries(series[i], sorted[i], [for (final p in sorted[i]) p.y], null),
    ];
  }
  final result = <_PlotSeries>[];
  for (int i = 0; i < series.length; i++) {
    final base = List<double>.filled(sorted[i].length, 0);
    for (int j = 0; j < i; j++) {
      final contribution = _interpolateSorted(sorted[j], [for (final p in sorted[i]) p.x]);
      for (int k = 0; k < base.length; k++) {
        base[k] += contribution[k];
      }
    }
    result.add(_PlotSeries(
      series[i],
      sorted[i],
      [for (int k = 0; k < sorted[i].length; k++) base[k] + sorted[i][k].y],
      base,
    ));
  }
  return result;
}

/// y of the polyline through [sorted] at each of [xs] (also sorted); 0
/// outside its x-range. One merged pass — linear, not quadratic.
List<double> _interpolateSorted(List<ChartPoint> sorted, List<double> xs) {
  final out = List<double>.filled(xs.length, 0);
  if (sorted.isEmpty) return out;
  int j = 0;
  for (int k = 0; k < xs.length; k++) {
    final x = xs[k];
    if (x < sorted.first.x || x > sorted.last.x) continue;
    while (j < sorted.length - 2 && sorted[j + 1].x < x) {
      j++;
    }
    final a = sorted[j], b = sorted[math.min(j + 1, sorted.length - 1)];
    out[k] = b.x == a.x ? b.y : a.y + (b.y - a.y) * ((x - a.x) / (b.x - a.x)).clamp(0.0, 1.0);
  }
  return out;
}

/// [to] with each value moved fraction [t] of the way from [from] — for
/// series that kept their name and point count; others are taken as-is.
List<_PlotSeries> _lerpSeries(List<_PlotSeries> from, List<_PlotSeries> to, double t) {
  if (t >= 1) return to;
  final byName = {for (final s in from) s.source.name: s};
  double lerp(double a, double b) => a + (b - a) * t;
  return [
    for (final s in to)
      switch (byName[s.source.name]) {
        final f? when f.points.length == s.points.length => _PlotSeries(
            s.source,
            s.points,
            [for (int i = 0; i < s.plotY.length; i++) lerp(f.plotY[i], s.plotY[i])],
            s.baseY == null ? null : [for (int i = 0; i < s.baseY!.length; i++) lerp(f.baseY?[i] ?? 0, s.baseY![i])],
          ),
        _ => s,
      },
  ];
}

class _LineChart2DState extends State<LineChart2D>
    with TickerProviderStateMixin, ChartControllerMixin<LineChart2D> {
  final ValueNotifier<Set<String>> _hiddenNotifier = ValueNotifier(const {});
  final ValueNotifier<_LineInteraction> _interactionNotifier = ValueNotifier(const _LineInteraction());
  late final AnimationController _controller;

  /// Drives [ChartUpdateAnimation.morph] from [_morphFrom] to the new data.
  late final AnimationController _morph;
  List<_PlotSeries>? _morphFrom;

  /// What the last build plotted — the starting point for the next morph.
  List<_PlotSeries> _lastPlotted = const [];

  final _dragZoom = ChartDragZoom();

  @override
  ChartController? controllerOf(LineChart2D widget) => widget.controller;

  @override
  void resetZoom() => _interactionNotifier.value = _interactionNotifier.value.copyWith(clearZoom: true);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.animationDuration);
    if (widget.enableAnimation) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
    _morph = AnimationController(vsync: this, duration: widget.animationDuration, value: 1);
    _interactionNotifier.addListener(() => reportZoomed(_interactionNotifier.value.zoom != null));
  }

  @override
  void didUpdateWidget(covariant LineChart2D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.series, widget.series) || oldWidget.stacked != widget.stacked) {
      switch (widget.updateAnimation) {
        case ChartUpdateAnimation.replay:
          if (widget.enableAnimation) _controller.forward(from: 0);
          _interactionNotifier.value = const _LineInteraction(); // zoom window may be stale
        case ChartUpdateAnimation.morph:
          if (widget.enableAnimation && oldWidget.stacked == widget.stacked) {
            _morphFrom = _lastPlotted;
            _morph.forward(from: 0);
          }
          _interactionNotifier.value = _interactionNotifier.value.copyWith(clearHover: true);
        case ChartUpdateAnimation.none:
          _interactionNotifier.value = _interactionNotifier.value.copyWith(clearHover: true);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _morph.dispose();
    _hiddenNotifier.dispose();
    _interactionNotifier.dispose();
    super.dispose();
  }

  String _formatX(double x) {
    final custom = widget.xTickFormatter;
    if (custom != null) return custom(x);
    return widget.xAxisType == ChartAxisType.time
        ? formatTime(DateTime.fromMillisecondsSinceEpoch(x.round()))
        : Cartesian2DAxes.formatNumber(x);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);

    if (widget.series.isEmpty || widget.series.every((s) => s.data.isEmpty)) {
      return ChartFrame(
        boundaryKey: chartBoundaryKey,
        title: widget.title,
        subtitle: widget.subtitle,
        plot: ChartEmptyState(message: widget.emptyStateMessage),
      );
    }

    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Line chart', widget.title, [for (final s in widget.series) summarizeValues(s.name, s.data.map((p) => p.y), widget.yTickFormatter)]),
      title: widget.title,
      subtitle: widget.subtitle,
      legendPosition: widget.legendPosition,
      legendBuilder: widget.showLegend ? _buildLegend : null,
      plot: ValueListenableBuilder<Set<String>>(
        valueListenable: _hiddenNotifier,
        builder: (context, hidden, _) {
          final visible = _toPlotSeries(widget.series.where((s) => !hidden.contains(s.name)).toList(), widget.stacked);
          _lastPlotted = visible;
          return LayoutBuilder(
            builder: (context, constraints) {
              // Measure the plot area itself: the legend can wrap to several
              // rows, so its size is not a fixed constant.
              final size = constraints.biggest;
              final zoomEnabled = widget.zoomMode != ChartZoomMode.none;
              return MouseRegion(
                onHover: (e) => _applyHover(_hitTest(e.localPosition, size, visible)),
                onExit: (_) {
                  _interactionNotifier.value = _interactionNotifier.value.copyWith(clearHover: true);
                  widget.onPointHover?.call(null, null);
                },
                child: GestureDetector(
                  onTapUp: (d) => _handleTap(d.localPosition, size, visible),
                  onPanStart: zoomEnabled ? (d) => _dragZoom.start(d.localPosition, Cartesian2DAxes.computePlotArea(size)) : null,
                  onPanUpdate: zoomEnabled ? (d) => _handlePanUpdate(d.localPosition, size) : null,
                  onPanEnd: zoomEnabled ? (_) => _handlePanEnd(size, visible) : null,
                  child: ValueListenableBuilder<_LineInteraction>(
                    valueListenable: _interactionNotifier,
                    builder: (context, interaction, __) {
                      return Stack(
                        children: [
                          // The data layer only repaints when the data, zoom or
                          // animation change — hovering repaints just the overlay.
                          RepaintBoundary(
                            child: AnimatedBuilder(
                            animation: Listenable.merge([_controller, _morph]),
                            builder: (context, _) => CustomPaint(
                              size: size,
                              painter: _LineChartPainter(
                                series: visible,
                                theme: theme,
                                xAxisTitle: widget.xAxisTitle,
                                yAxisTitle: widget.yAxisTitle,
                                xAxisType: widget.xAxisType,
                                xTickFormatter: widget.xTickFormatter,
                                yTickFormatter: widget.yTickFormatter,
                                curve: widget.curve,
                                filled: widget.filled,
                                stacked: widget.stacked,
                                showGrid: widget.showGrid,
                                showPoints: widget.showPoints,
                                lineWidth: widget.lineWidth,
                                pointRadius: widget.pointRadius,
                                referenceLines: widget.referenceLines,
                                referenceBands: widget.referenceBands,
                                progress: _controller.value,
                                zoom: interaction.zoom,
                                liveWindow: widget.liveWindow,
                                downsample: widget.downsample,
                                morphFrom: _morph.isAnimating ? _morphFrom : null,
                                morphT: Curves.easeInOutCubic.transform(_morph.value),
                              ),
                            ),
                          ),
                          ),
                          if (interaction.hover != null)
                            IgnorePointer(
                              child: CustomPaint(
                                size: size,
                                painter: _LineHoverPainter(
                                  hover: interaction.hover!,
                                  color: widget.series.firstWhere((s) => s.name == interaction.hover!.series).color,
                                  pointRadius: widget.pointRadius,
                                  crosshair: widget.showCrosshair,
                                  theme: theme,
                                ),
                              ),
                            ),
                          if (interaction.dragRectScreen != null)
                            ChartSelectionOverlay(rect: interaction.dragRectScreen!, theme: theme),
                          if (interaction.zoom != null)
                            Positioned(right: 8, top: 8, child: ChartResetZoomButton(theme: theme, onTap: resetZoom)),
                          if (interaction.hover != null) _buildTooltip(interaction.hover!, size, theme),
                        ],
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
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
          _interactionNotifier.value = _interactionNotifier.value.copyWith(clearHover: true);
        },
      ),
    );
  }

  // ---------------- zoom drag handling ----------------

  void _handlePanUpdate(Offset pos, Size size) {
    final rect = _dragZoom.update(pos, Cartesian2DAxes.computePlotArea(size), widget.zoomMode);
    if (rect == null) return;
    _interactionNotifier.value = _interactionNotifier.value.copyWith(dragRectScreen: rect, clearHover: true);
  }

  void _handlePanEnd(Size size, List<_PlotSeries> visible) {
    final current = _interactionNotifier.value;
    final rect = current.dragRectScreen;
    _dragZoom.end();
    if (rect == null) return;

    if (ChartDragZoom.isTooSmall(rect, widget.zoomMode, widget.zoomDragThreshold)) {
      _interactionNotifier.value = current.copyWith(clearDragRect: true);
      return;
    }

    final axes = _axesFor(size, visible, current.zoom);
    final newMinX = axes.toDataX(rect.left);
    final newMaxX = axes.toDataX(rect.right);
    final newZoom = widget.zoomMode == ChartZoomMode.xy
        ? ChartZoomWindow(minX: newMinX, maxX: newMaxX, minY: axes.toDataY(rect.bottom), maxY: axes.toDataY(rect.top))
        : ChartZoomWindow(minX: newMinX, maxX: newMaxX);

    _interactionNotifier.value = current.copyWith(zoom: newZoom, clearDragRect: true);
  }

  Cartesian2DAxes _axesFor(Size size, List<_PlotSeries> visible, ChartZoomWindow? zoom) {
    final bounds = _effectiveBounds(visible, zoom, liveWindow: widget.liveWindow);
    return Cartesian2DAxes(
      plotArea: Cartesian2DAxes.computePlotArea(size),
      minX: bounds.minX,
      maxX: bounds.maxX,
      minY: bounds.minY,
      maxY: bounds.maxY,
    );
  }

  // ---------------- hover / tap handling ----------------

  void _handleTap(Offset pos, Size size, List<_PlotSeries> visible) {
    final hit = _hitTest(pos, size, visible);
    _applyHover(hit);
    if (hit != null) widget.onPointTap?.call(hit.series, hit.point);
  }

  void _applyHover(_LineHover? hit) {
    final current = _interactionNotifier.value;
    final changed = hit?.series != current.hover?.series || hit?.point != current.hover?.point;
    _interactionNotifier.value = hit == null ? current.copyWith(clearHover: true) : current.copyWith(hover: hit);
    if (changed) widget.onPointHover?.call(hit?.series, hit?.point);
  }

  _LineHover? _hitTest(Offset pos, Size size, List<_PlotSeries> visible) {
    if (visible.isEmpty) return null;
    final axes = _axesFor(size, visible, _interactionNotifier.value.zoom);

    _LineHover? best;
    double bestDist = 26; // px hit radius
    for (final s in visible) {
      for (int i = 0; i < s.points.length; i++) {
        final x = s.points[i].x, y = s.plotY[i];
        // points outside the zoom window aren't drawn, so they can't be hit
        if (x < axes.minX || x > axes.maxX || y < axes.minY || y > axes.maxY) continue;
        final sp = Offset(axes.toScreenX(x), axes.toScreenY(y));
        final d = (sp - pos).distance;
        if (d < bestDist) {
          bestDist = d;
          best = (series: s.source.name, point: s.points[i], screenPos: sp);
        }
      }
    }
    return best;
  }

  Widget _buildTooltip(_LineHover hover, Size size, ChartTheme theme) {
    final custom = widget.tooltipBuilder;
    return positionChartTooltip(
      anchor: hover.screenPos,
      areaSize: size,
      child: custom != null
          ? custom(context, hover.series, hover.point)
          : ChartTooltipCard(
              theme: theme,
              width: 150,
              title: hover.series,
              subtitle: hover.point.label ?? _formatX(hover.point.x),
              value: widget.yTickFormatter(hover.point.y),
            ),
    );
  }
}

/// Computes the data-space bounds a chart should display: either the
/// current [zoom] window, or the full extent of [series] if not zoomed.
/// When only x is zoomed (`zoom.minY == null`), y auto-rescales to fit
/// just the points inside that x-range — matching Highcharts' behavior.
///
/// With a [liveWindow] and no zoom, shows the last [liveWindow] x-units of
/// data, fitted like an x-zoom.
({double minX, double maxX, double minY, double maxY}) _effectiveBounds(
  List<_PlotSeries> series,
  ChartZoomWindow? zoom, {
  double? liveWindow,
}) {
  if (zoom == null && liveWindow != null) {
    double latest = -double.infinity;
    for (final s in series) {
      if (s.points.isNotEmpty) latest = math.max(latest, s.points.last.x);
    }
    if (latest.isFinite) zoom = ChartZoomWindow(minX: latest - liveWindow, maxX: latest);
  }
  if (zoom != null && zoom.minY != null && zoom.maxY != null) {
    return (minX: zoom.minX, maxX: zoom.maxX, minY: zoom.minY!, maxY: zoom.maxY!);
  }

  final xMin = zoom?.minX;
  final xMax = zoom?.maxX;
  double minX = double.infinity, maxX = -double.infinity;
  double minY = double.infinity, maxY = -double.infinity;
  for (final s in series) {
    for (int i = 0; i < s.points.length; i++) {
      final x = s.points[i].x;
      if (xMin != null && x < xMin) continue;
      if (xMax != null && x > xMax) continue;
      final y = s.plotY[i];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      // a stacked area's floor must stay in view too
      final base = s.baseY?[i];
      if (base != null && base < minY) minY = base;
    }
  }
  if (minX.isInfinite) {
    // nothing fell inside the zoom window — fall back to the window itself
    minX = xMin ?? 0;
    maxX = xMax ?? 1;
    minY = 0;
    maxY = 1;
  } else if (zoom == null) {
    // Only anchor at zero for the default, unzoomed view, and round out to
    // nice tick values so the top gridline sits on the plot's edge.
    if (minY > 0) minY = 0;
    (minY, maxY) = Cartesian2DAxes.niceExtent(minY, maxY);
  } else {
    // Zoomed: tightly fit y to just the visible slice (with a little
    // padding) instead of always including zero — otherwise a zoom into a
    // narrow x-range whose values sit well above zero barely looks zoomed
    // in at all, since the y-axis stays dominated by that zero baseline.
    final range = maxY - minY;
    final fallbackPad = maxY.abs() * 0.1;
    final yPad = range == 0 ? (fallbackPad == 0 ? 1.0 : fallbackPad) : range * 0.1;
    minY -= yPad;
    maxY += yPad;
  }
  return (minX: xMin ?? minX, maxX: xMax ?? maxX, minY: minY, maxY: maxY);
}

class _LineChartPainter extends CustomPainter {
  final List<_PlotSeries> series;
  final ChartTheme theme;
  final String? xAxisTitle;
  final String? yAxisTitle;
  final ChartAxisType xAxisType;
  final String Function(double)? xTickFormatter;
  final String Function(double) yTickFormatter;
  final LineChartCurve curve;
  final bool filled;
  final bool stacked;
  final bool showGrid;
  final bool showPoints;
  final double lineWidth;
  final double pointRadius;
  final List<ChartReferenceLine> referenceLines;
  final List<ChartReferenceBand> referenceBands;
  final ChartZoomWindow? zoom;
  final double? liveWindow;
  final bool downsample;

  /// When non-null, the series being morphed away from, [morphT] (0–1) of
  /// the way toward [series].
  final List<_PlotSeries>? morphFrom;
  final double morphT;

  /// 0 (nothing drawn) to 1 (fully drawn) — drives the entrance animation.
  final double progress;

  _LineChartPainter({
    required this.series,
    required this.theme,
    required this.xAxisTitle,
    required this.yAxisTitle,
    required this.xAxisType,
    required this.xTickFormatter,
    required this.yTickFormatter,
    required this.curve,
    required this.filled,
    required this.stacked,
    required this.showGrid,
    required this.showPoints,
    required this.lineWidth,
    required this.pointRadius,
    required this.referenceLines,
    required this.referenceBands,
    required this.progress,
    required this.zoom,
    required this.liveWindow,
    required this.downsample,
    required this.morphFrom,
    required this.morphT,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;

    final from = morphFrom;
    final plotted = from == null ? series : _lerpSeries(from, series, morphT);
    var bounds = _effectiveBounds(series, zoom, liveWindow: liveWindow);
    if (from != null && from.isNotEmpty) {
      // Glide the axes too, so values don't jump against a snapping scale.
      final a = _effectiveBounds(from, zoom, liveWindow: liveWindow);
      double lerp(double x, double y) => x + (y - x) * morphT;
      bounds = (minX: bounds.minX, maxX: bounds.maxX, minY: lerp(a.minY, bounds.minY), maxY: lerp(a.maxY, bounds.maxY));
    }
    final plotArea = Cartesian2DAxes.computePlotArea(size);
    final axes = Cartesian2DAxes(
      plotArea: plotArea,
      minX: bounds.minX,
      maxX: bounds.maxX,
      minY: bounds.minY,
      maxY: bounds.maxY,
      theme: theme,
    );

    axes.drawGridAndAxes(
      canvas,
      yTicks: Cartesian2DAxes.niceTicks(bounds.minY, bounds.maxY),
      yFormatter: yTickFormatter,
      xAxisTitle: xAxisTitle,
      yAxisTitle: yAxisTitle,
      showGrid: showGrid,
    );
    _drawXTicks(canvas, axes, bounds);

    final references = ReferencePainter(axes);
    references.paintBands(canvas, referenceBands);

    // Indices of each series' points inside the current window.
    List<int> visibleIndices(_PlotSeries s) => [
          for (int i = 0; i < s.points.length; i++)
            if (s.points[i].x >= bounds.minX &&
                s.points[i].x <= bounds.maxX &&
                (zoom?.minY == null || s.plotY[i] >= zoom!.minY!) &&
                (zoom?.maxY == null || s.plotY[i] <= zoom!.maxY!))
              i,
        ];

    // Entrance animation: reveal everything left-to-right.
    canvas.save();
    final reveal = plotArea.inflate(pointRadius + 4);
    canvas.clipRect(Rect.fromLTRB(reveal.left, reveal.top, reveal.left + reveal.width * progress, reveal.bottom));

    final zeroY = axes.toScreenY(0.0.clamp(bounds.minY, bounds.maxY));
    final maxPoints = math.max(3, (plotArea.width * 1.5).round());
    for (final s in plotted) {
      var idx = visibleIndices(s);
      if (idx.isEmpty) continue;
      final thinned = downsample && idx.length > maxPoints;
      if (thinned) {
        final all = idx;
        idx = [for (final k in lttbIndices(all.length, (k) => s.points[all[k]].x, (k) => s.plotY[all[k]], maxPoints)) all[k]];
      }
      final pts = [for (final i in idx) Offset(axes.toScreenX(s.points[i].x), axes.toScreenY(s.plotY[i]))];

      if (filled) {
        final area = Path();
        traceCurve(area, pts, curve);
        final base = s.baseY;
        if (base != null) {
          // Stacked: close along the series below, traced right-to-left.
          final floor = [for (final i in idx.reversed) Offset(axes.toScreenX(s.points[i].x), axes.toScreenY(base[i]))];
          traceCurve(area, floor, curve, connect: true);
        } else {
          // Fill down to zero, or to the plot edge when zero is out of view.
          area.lineTo(pts.last.dx, zeroY);
          area.lineTo(pts.first.dx, zeroY);
        }
        area.close();
        canvas.drawPath(area, Paint()..color = s.source.color.withValues(alpha: stacked ? 0.35 : 0.15));
      }

      final line = Path();
      traceCurve(line, pts, curve);
      canvas.drawPath(
        line,
        Paint()
          ..color = s.source.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = lineWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );

      // Markers would be a solid smear on a thinned (very dense) series.
      if (showPoints && !thinned) {
        final dot = Paint()..color = s.source.color;
        for (final sp in pts) {
          canvas.drawCircle(sp, pointRadius, dot);
        }
      }
    }
    canvas.restore();

    references.paintLines(canvas, referenceLines);
  }

  /// x ticks: point labels if the data carries them (e.g. pre-formatted
  /// dates), calendar ticks on a time axis, nice numbers otherwise.
  void _drawXTicks(Canvas canvas, Cartesian2DAxes axes, ({double minX, double maxX, double minY, double maxY}) bounds) {
    // Label points of the series with the most visible points.
    List<ChartPoint> inView(_PlotSeries s) => s.points.where((p) => p.x >= bounds.minX && p.x <= bounds.maxX).toList();
    final candidates = series.map(inView).where((l) => l.isNotEmpty).toList();
    if (candidates.isEmpty) return;
    final labelPoints = candidates.reduce((a, b) => a.length >= b.length ? a : b);
    final fmt = xTickFormatter ?? Cartesian2DAxes.formatNumber;

    if (labelPoints.any((p) => p.label != null)) {
      axes.drawXTicks(canvas, [for (final p in labelPoints) (axes.toScreenX(p.x), p.label ?? fmt(p.x))]);
    } else if (xAxisType == ChartAxisType.time) {
      final maxTicks = math.max(2, (axes.plotArea.width / 64).floor());
      axes.drawXTicks(canvas, [
        for (final (x, label) in timeTicks(bounds.minX, bounds.maxX, maxTicks: maxTicks))
          (axes.toScreenX(x), xTickFormatter?.call(x) ?? label),
      ]);
    } else {
      axes.drawXTicks(canvas, [
        for (final xv in Cartesian2DAxes.niceTicks(bounds.minX, bounds.maxX)) (axes.toScreenX(xv), fmt(xv)),
      ]);
    }
  }

  /// Hover rebuilds this painter with identical inputs; only real changes
  /// (data, zoom, animation, styling) repaint the — possibly huge — data layer.
  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      !identical(old.series, series) ||
      !identical(old.morphFrom, morphFrom) ||
      old.morphT != morphT ||
      old.progress != progress ||
      !identical(old.zoom, zoom) ||
      old.liveWindow != liveWindow ||
      old.downsample != downsample ||
      old.theme != theme ||
      old.curve != curve ||
      old.filled != filled ||
      old.stacked != stacked ||
      old.showGrid != showGrid ||
      old.showPoints != showPoints ||
      old.lineWidth != lineWidth ||
      old.pointRadius != pointRadius ||
      old.xAxisType != xAxisType ||
      old.xAxisTitle != xAxisTitle ||
      old.yAxisTitle != yAxisTitle ||
      old.xTickFormatter != xTickFormatter ||
      old.yTickFormatter != yTickFormatter ||
      !identical(old.referenceLines, referenceLines) ||
      !identical(old.referenceBands, referenceBands);
}

/// The hovered point's highlight and crosshair, painted above the data layer.
class _LineHoverPainter extends CustomPainter {
  final _LineHover hover;
  final Color color;
  final double pointRadius;
  final bool crosshair;
  final ChartTheme theme;

  _LineHoverPainter({required this.hover, required this.color, required this.pointRadius, required this.crosshair, required this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    final p = hover.screenPos;
    if (crosshair) {
      Cartesian2DAxes(plotArea: Cartesian2DAxes.computePlotArea(size), minX: 0, maxX: 1, minY: 0, maxY: 1, theme: theme)
          .drawCrosshair(canvas, p);
    }
    canvas.drawCircle(p, pointRadius + 2, Paint()..color = color);
    canvas.drawCircle(
      p,
      pointRadius + 4,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _LineHoverPainter old) =>
      old.hover != hover || old.color != color || old.theme != theme || old.crosshair != crosshair;
}
