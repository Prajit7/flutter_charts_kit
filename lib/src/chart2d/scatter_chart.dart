import 'dart:ui' show PointMode;
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
import 'crosshair_sync.dart';

/// Transient interaction state for [ScatterChart2D] — hover, an
/// in-progress drag-selection rectangle, and the current zoom window. Held
/// in a single [ValueNotifier] so pointer movement never triggers
/// `setState()`; only the canvas + tooltip subtree rebuilds.
class _ScatterInteraction {
  final ({String series, ChartPoint point, Offset screenPos})? hover;
  final Rect? dragRectScreen;
  final ChartZoomWindow? zoom;

  const _ScatterInteraction({this.hover, this.dragRectScreen, this.zoom});

  _ScatterInteraction copyWith({
    ({String series, ChartPoint point, Offset screenPos})? hover,
    bool clearHover = false,
    Rect? dragRectScreen,
    bool clearDragRect = false,
    ChartZoomWindow? zoom,
    bool clearZoom = false,
  }) {
    return _ScatterInteraction(
      hover: clearHover ? null : (hover ?? this.hover),
      dragRectScreen: clearDragRect ? null : (dragRectScreen ?? this.dragRectScreen),
      zoom: clearZoom ? null : (zoom ?? this.zoom),
    );
  }
}

/// A generic multi-series scatter plot with drag-to-zoom. Set
/// [ChartPoint.size] on points to render it as a bubble chart instead of
/// fixed-radius points.
///
/// ```dart
/// ScatterChart2D(
///   title: 'Practice vs Score',
///   series: [
///     XySeries(name: 'Cohort A', color: Colors.blue, data: [
///       ChartPoint(x: 5.2, y: 88, label: 'Player 1'),
///       ChartPoint(x: 7.1, y: 92, label: 'Player 2'),
///     ]),
///   ],
///   xAxisTitle: 'Hours practiced',
///   yAxisTitle: 'Score',
/// )
/// ```
///
/// Drag a rectangle over the plot to zoom into it (both axes, by default).
/// A reset button appears while zoomed.
class ScatterChart2D extends StatefulWidget {
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

  /// Linear (default) or logarithmic axes. Log axes show only positive
  /// values — useful when data spans several orders of magnitude.
  final ChartAxisScale xAxisScale;
  final ChartAxisScale yAxisScale;

  /// Defaults to plain numbers, or dates/times on a time axis.
  final String Function(double value)? xTickFormatter;
  final String Function(double value) yTickFormatter;
  final bool showGrid;
  final bool showLegend;
  final ChartLegendPosition legendPosition;
  final bool showCrosshair;
  final double defaultPointRadius;

  /// Horizontal/vertical marker lines (targets, thresholds, "today").
  final List<ChartReferenceLine> referenceLines;

  /// Shaded ranges drawn behind the points.
  final List<ChartReferenceBand> referenceBands;

  /// Callouts pinned to data points.
  final List<ChartAnnotation> annotations;

  /// Print each point's [ChartPoint.label] beside it.
  final bool showPointLabels;

  /// Replaces the default tooltip card.
  final ChartPointTooltipBuilder? tooltipBuilder;

  /// Reset zoom or export an image from outside the chart.
  final ChartController? controller;

  /// Links this chart's crosshair with other charts sharing the same sync.
  final ChartCrosshairSync? crosshairSync;

  final bool enableAnimation;
  final Duration animationDuration;

  /// Drag-to-zoom mode. [ChartZoomMode.xy] (default) zooms both axes to
  /// the dragged rectangle; [ChartZoomMode.x] zooms only x; [ChartZoomMode.none]
  /// disables zoom.
  final ChartZoomMode zoomMode;

  /// Minimum drag distance (px) before a drag counts as a zoom selection.
  final double zoomDragThreshold;

  /// Fired continuously as the pointer moves over/off a point (both mouse
  /// hover and touch). Called with `(null, null)` when nothing is hovered.
  final ChartPointCallback? onPointHover;

  /// Fired once per tap/click on a point. Not called on taps that miss.
  final ChartPointCallback? onPointTap;

  const ScatterChart2D({
    super.key,
    required this.series,
    this.title,
    this.subtitle,
    this.xAxisTitle,
    this.yAxisTitle,
    this.emptyStateMessage = 'No data to display',
    this.xAxisType = ChartAxisType.numeric,
    this.xAxisScale = ChartAxisScale.linear,
    this.yAxisScale = ChartAxisScale.linear,
    this.xTickFormatter,
    this.yTickFormatter = Cartesian2DAxes.formatNumber,
    this.showGrid = true,
    this.showLegend = true,
    this.legendPosition = ChartLegendPosition.bottom,
    this.showCrosshair = true,
    this.defaultPointRadius = 5,
    this.referenceLines = const [],
    this.referenceBands = const [],
    this.annotations = const [],
    this.showPointLabels = false,
    this.tooltipBuilder,
    this.controller,
    this.crosshairSync,
    this.enableAnimation = true,
    this.animationDuration = const Duration(milliseconds: 500),
    this.zoomMode = ChartZoomMode.xy,
    this.zoomDragThreshold = 12,
    this.onPointHover,
    this.onPointTap,
  });

  @override
  State<ScatterChart2D> createState() => _ScatterChart2DState();
}

class _ScatterChart2DState extends State<ScatterChart2D>
    with SingleTickerProviderStateMixin, ChartControllerMixin<ScatterChart2D> {
  final ValueNotifier<Set<String>> _hiddenNotifier = ValueNotifier(const {});
  final ValueNotifier<_ScatterInteraction> _interactionNotifier =
      ValueNotifier(const _ScatterInteraction());
  late final AnimationController _controller;

  final _dragZoom = ChartDragZoom();

  @override
  ChartController? controllerOf(ScatterChart2D widget) => widget.controller;

  @override
  void resetZoom() => _interactionNotifier.value = _interactionNotifier.value.copyWith(clearZoom: true);

  String _formatX(double x) {
    final custom = widget.xTickFormatter;
    if (custom != null) return custom(x);
    return widget.xAxisType == ChartAxisType.time
        ? formatTime(DateTime.fromMillisecondsSinceEpoch(x.round()))
        : Cartesian2DAxes.formatNumber(x);
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.animationDuration);
    if (widget.enableAnimation) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
    _interactionNotifier.addListener(() => reportZoomed(_interactionNotifier.value.zoom != null));
  }

  @override
  void didUpdateWidget(covariant ScatterChart2D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.series, widget.series)) {
      if (widget.enableAnimation) _controller.forward(from: 0);
      _interactionNotifier.value = const _ScatterInteraction();
    }
  }

  @override
  void dispose() {
    widget.crosshairSync?.clear(this);
    _controller.dispose();
    _hiddenNotifier.dispose();
    _interactionNotifier.dispose();
    super.dispose();
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

    final zoomEnabled = widget.zoomMode != ChartZoomMode.none;
    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Scatter chart', widget.title, [for (final s in widget.series) '${s.name}: ${s.data.length} points']),
      title: widget.title,
      subtitle: widget.subtitle,
      legendPosition: widget.legendPosition,
      legendBuilder: widget.showLegend ? _buildLegend : null,
      plot: ValueListenableBuilder<Set<String>>(
        valueListenable: _hiddenNotifier,
        builder: (context, hidden, _) {
          final visibleSeries = widget.series.where((s) => !hidden.contains(s.name)).toList();
          return LayoutBuilder(
            builder: (context, constraints) {
              // Measure the plot area itself: the legend can wrap to several
              // rows, so its size is not a fixed constant.
              final size = constraints.biggest;
              return MouseRegion(
                onHover: (e) => _updateHover(e.localPosition, size, visibleSeries),
                onExit: (_) {
                  _interactionNotifier.value = _interactionNotifier.value.copyWith(clearHover: true);
                  widget.onPointHover?.call(null, null);
                  widget.crosshairSync?.clear(this);
                },
                child: GestureDetector(
                  onTapUp: (d) => _handleTap(d.localPosition, size, visibleSeries),
                  onPanStart: zoomEnabled ? (d) => _handlePanStart(d.localPosition, size) : null,
                  onPanUpdate: zoomEnabled ? (d) => _handlePanUpdate(d.localPosition, size) : null,
                  onPanEnd: zoomEnabled ? (_) => _handlePanEnd(size, visibleSeries) : null,
                  child: ValueListenableBuilder<_ScatterInteraction>(
                    valueListenable: _interactionNotifier,
                    builder: (context, interaction, __) {
                      return Stack(
                        children: [
                          // Data layer repaints only on data/zoom/animation changes;
                          // hover draws on the overlay below it.
                          RepaintBoundary(
                            child: AnimatedBuilder(
                            animation: _controller,
                            builder: (context, _) => CustomPaint(
                              size: size,
                              painter: _ScatterChartPainter(
                                series: visibleSeries,
                                theme: theme,
                                xAxisTitle: widget.xAxisTitle,
                                yAxisTitle: widget.yAxisTitle,
                                xAxisType: widget.xAxisType,
                                logX: _logX,
                                logY: _logY,
                                xTickFormatter: widget.xTickFormatter,
                                yTickFormatter: widget.yTickFormatter,
                                showGrid: widget.showGrid,
                                defaultRadius: widget.defaultPointRadius,
                                referenceLines: widget.referenceLines,
                                referenceBands: widget.referenceBands,
                                annotations: widget.annotations,
                                showPointLabels: widget.showPointLabels,
                                progress: _controller.value,
                                zoom: interaction.zoom,
                              ),
                            ),
                          ),
                          ),
                          if (interaction.hover != null)
                            IgnorePointer(
                              child: CustomPaint(
                                size: size,
                                painter: _ScatterHoverPainter(
                                  hover: interaction.hover!,
                                  color: widget.series.firstWhere((s) => s.name == interaction.hover!.series).color,
                                  radius: interaction.hover!.point.size ?? widget.defaultPointRadius,
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
                          if (widget.crosshairSync != null && interaction.hover == null)
                            IgnorePointer(
                              child: ListenableBuilder(
                                listenable: widget.crosshairSync!,
                                builder: (context, _) {
                                  final x = widget.crosshairSync!.xFor(this);
                                  if (x == null) return const SizedBox.shrink();
                                  return CustomPaint(
                                    size: size,
                                    painter: SyncCrosshairPainter(
                                        axes: _axesFor(size, visibleSeries, interaction.zoom), x: x, theme: theme),
                                  );
                                },
                              ),
                            ),
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

  void _handlePanStart(Offset pos, Size size) {
    _dragZoom.start(pos, Cartesian2DAxes.computePlotArea(size));
  }

  void _handlePanUpdate(Offset pos, Size size) {
    final rect = _dragZoom.update(pos, Cartesian2DAxes.computePlotArea(size), widget.zoomMode);
    if (rect == null) return;
    final current = _interactionNotifier.value;
    _interactionNotifier.value = current.copyWith(dragRectScreen: rect, clearHover: true);
  }

  void _handlePanEnd(Size size, List<XySeries> visibleSeries) {
    final current = _interactionNotifier.value;
    final rect = current.dragRectScreen;
    _dragZoom.end();
    if (rect == null) return;

    if (ChartDragZoom.isTooSmall(rect, widget.zoomMode, widget.zoomDragThreshold)) {
      _interactionNotifier.value = current.copyWith(clearDragRect: true);
      return;
    }

    final axes = _axesFor(size, visibleSeries, current.zoom);

    final newMinX = axes.toDataX(rect.left);
    final newMaxX = axes.toDataX(rect.right);
    ChartZoomWindow newZoom;
    if (widget.zoomMode == ChartZoomMode.xy) {
      final newMaxY = axes.toDataY(rect.top);
      final newMinY = axes.toDataY(rect.bottom);
      newZoom = ChartZoomWindow(minX: newMinX, maxX: newMaxX, minY: newMinY, maxY: newMaxY);
    } else {
      newZoom = ChartZoomWindow(minX: newMinX, maxX: newMaxX);
    }

    _interactionNotifier.value = current.copyWith(zoom: newZoom, clearDragRect: true);
  }

  // ---------------- hover / tap handling ----------------

  void _handleTap(Offset pos, Size size, List<XySeries> visibleSeries) {
    final hit = _hitTest(pos, size, visibleSeries);
    _applyHover(hit);
    if (hit != null) {
      widget.onPointTap?.call(hit.series, hit.point);
    }
  }

  void _updateHover(Offset pos, Size size, List<XySeries> visibleSeries) {
    final hit = _hitTest(pos, size, visibleSeries);
    _applyHover(hit);
  }

  void _applyHover(({String series, ChartPoint point, Offset screenPos})? hit) {
    final current = _interactionNotifier.value;
    final changed = hit?.series != current.hover?.series || hit?.point != current.hover?.point;
    _interactionNotifier.value = hit == null ? current.copyWith(clearHover: true) : current.copyWith(hover: hit);
    final sync = widget.crosshairSync;
    if (sync != null) hit == null ? sync.clear(this) : sync.update(this, hit.point.x);
    if (changed) {
      widget.onPointHover?.call(hit?.series, hit?.point);
    }
  }

  bool get _logX => widget.xAxisScale == ChartAxisScale.logarithmic;
  bool get _logY => widget.yAxisScale == ChartAxisScale.logarithmic;

  Cartesian2DAxes _axesFor(Size size, List<XySeries> visible, ChartZoomWindow? zoom) {
    final b = _effectiveScatterBounds(visible, zoom, logX: _logX, logY: _logY);
    return Cartesian2DAxes(
      plotArea: Cartesian2DAxes.computePlotArea(size),
      minX: b.minX,
      maxX: b.maxX,
      minY: b.minY,
      maxY: b.maxY,
      logX: _logX,
      logY: _logY,
    );
  }

  ({String series, ChartPoint point, Offset screenPos})? _hitTest(
      Offset pos, Size size, List<XySeries> visibleSeries) {
    if (visibleSeries.isEmpty) return null;
    final axes = _axesFor(size, visibleSeries, _interactionNotifier.value.zoom);
    final bounds = (minX: axes.minX, maxX: axes.maxX, minY: axes.minY, maxY: axes.maxY);

    // Pick the point whose edge is nearest the pointer (so big bubbles are
    // easy to hit), within a fixed slop.
    String? bestSeries;
    ChartPoint? bestPoint;
    double bestEdgeDist = 22;
    for (final s in visibleSeries) {
      for (final p in s.data) {
        // points outside the zoom window aren't drawn, so they can't be hit
        if (p.x < bounds.minX || p.x > bounds.maxX || p.y < bounds.minY || p.y > bounds.maxY) continue;
        final r = p.size ?? widget.defaultPointRadius;
        final sp = Offset(axes.toScreenX(p.x), axes.toScreenY(p.y));
        final edgeDist = (sp - pos).distance - r;
        if (edgeDist < bestEdgeDist) {
          bestEdgeDist = edgeDist;
          bestSeries = s.name;
          bestPoint = p;
        }
      }
    }

    if (bestSeries != null && bestPoint != null) {
      final sp = Offset(axes.toScreenX(bestPoint.x), axes.toScreenY(bestPoint.y));
      return (series: bestSeries, point: bestPoint, screenPos: sp);
    }
    return null;
  }

  Widget _buildTooltip(({String series, ChartPoint point, Offset screenPos}) hover, Size size, ChartTheme theme) {
    final coords = '(${_formatX(hover.point.x)}, ${widget.yTickFormatter(hover.point.y)})';
    final custom = widget.tooltipBuilder;
    return positionChartTooltip(
      anchor: hover.screenPos,
      areaSize: size,
      child: custom != null ? custom(context, hover.series, hover.point) : ChartTooltipCard(
        theme: theme,
        width: 150,
        title: hover.series,
        subtitle: hover.point.label ?? coords,
        value: hover.point.label != null ? coords : null,
      ),
    );
  }
}

/// Computes the data-space bounds to display: the current [zoom] window
/// (if any), else the full extent of [series] padded 8% on each axis so
/// points aren't clipped at the edges.
///
/// On a log axis ([logX]/[logY]) values ≤ 0 are ignored and the padding is
/// a ratio rather than a difference.
({double minX, double maxX, double minY, double maxY}) _effectiveScatterBounds(
  List<XySeries> series,
  ChartZoomWindow? zoom, {
  bool logX = false,
  bool logY = false,
}) {
  if (zoom != null && zoom.minY != null && zoom.maxY != null) {
    return (minX: zoom.minX, maxX: zoom.maxX, minY: zoom.minY!, maxY: zoom.maxY!);
  }

  final xMin = zoom?.minX;
  final xMax = zoom?.maxX;
  double minX = double.infinity, maxX = -double.infinity;
  double minY = double.infinity, maxY = -double.infinity;
  for (final s in series) {
    for (final p in s.data) {
      if (xMin != null && p.x < xMin) continue;
      if (xMax != null && p.x > xMax) continue;
      if ((logX && p.x <= 0) || (logY && p.y <= 0)) continue;
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
  }
  if (minX.isInfinite) {
    minX = xMin ?? (logX ? 1 : 0);
    maxX = xMax ?? (logX ? 10 : 1);
    minY = logY ? 1 : 0;
    maxY = logY ? 10 : 1;
  }
  (double, double) pad(double lo, double hi, bool log) {
    if (!log) return (lo - (hi - lo) * 0.08, hi + (hi - lo) * 0.08);
    final f = hi == lo ? 2.0 : math.pow(hi / lo, 0.08).toDouble();
    return (lo / f, hi * f);
  }

  final (x0, x1) = pad(minX, maxX, logX);
  final (y0, y1) = pad(minY, maxY, logY);
  return (minX: xMin ?? x0, maxX: xMax ?? x1, minY: y0, maxY: y1);
}

class _ScatterChartPainter extends CustomPainter {
  final List<XySeries> series;
  final ChartTheme theme;
  final String? xAxisTitle;
  final String? yAxisTitle;
  final ChartAxisType xAxisType;
  final bool logX;
  final bool logY;
  final String Function(double)? xTickFormatter;
  final String Function(double) yTickFormatter;
  final bool showGrid;
  final double defaultRadius;
  final List<ChartReferenceLine> referenceLines;
  final List<ChartReferenceBand> referenceBands;
  final List<ChartAnnotation> annotations;
  final bool showPointLabels;
  final ChartZoomWindow? zoom;

  /// 0 (invisible) to 1 (full size) — drives the pop-in entrance animation.
  final double progress;

  _ScatterChartPainter({
    required this.series,
    required this.theme,
    required this.xAxisTitle,
    required this.yAxisTitle,
    required this.xAxisType,
    required this.logX,
    required this.logY,
    required this.xTickFormatter,
    required this.yTickFormatter,
    required this.showGrid,
    required this.defaultRadius,
    required this.referenceLines,
    required this.referenceBands,
    required this.annotations,
    required this.showPointLabels,
    required this.progress,
    required this.zoom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;

    final bounds = _effectiveScatterBounds(series, zoom, logX: logX, logY: logY);
    final plotArea = Cartesian2DAxes.computePlotArea(size);
    final axes = Cartesian2DAxes(
      plotArea: plotArea,
      minX: bounds.minX,
      maxX: bounds.maxX,
      minY: bounds.minY,
      maxY: bounds.maxY,
      theme: theme,
      logX: logX,
      logY: logY,
    );
    final yTicks = axes.yTicks;

    axes.drawGridAndAxes(
      canvas,
      yTicks: yTicks,
      yFormatter: yTickFormatter,
      xAxisTitle: xAxisTitle,
      yAxisTitle: yAxisTitle,
      showGrid: showGrid,
    );
    if (xAxisType == ChartAxisType.time) {
      final maxTicks = math.max(2, (plotArea.width / 64).floor());
      axes.drawXTicks(canvas, [
        for (final (x, label) in timeTicks(bounds.minX, bounds.maxX, maxTicks: maxTicks))
          (axes.toScreenX(x), xTickFormatter?.call(x) ?? label),
      ]);
    } else {
      final fmt = xTickFormatter ?? Cartesian2DAxes.formatNumber;
      axes.drawXTicks(canvas, [
        for (final xv in axes.xTicks) (axes.toScreenX(xv), fmt(xv)),
      ]);
    }

    final references = ReferencePainter(axes);
    references.paintBands(canvas, referenceBands);

    canvas.save();
    canvas.clipRect(axes.plotArea.inflate(defaultRadius));
    for (final s in series) {
      final paint = Paint()..color = s.color.withValues(alpha: 0.75 * progress);
      // Default-size points go to the GPU in one batch per series (round
      // point caps draw them as circles); sized bubbles are drawn singly.
      final batch = <double>[];
      for (final p in s.data) {
        if (p.x < bounds.minX || p.x > bounds.maxX || p.y < bounds.minY || p.y > bounds.maxY) continue;
        final sx = axes.toScreenX(p.x), sy = axes.toScreenY(p.y);
        if (p.size == null) {
          batch
            ..add(sx)
            ..add(sy);
        } else {
          canvas.drawCircle(Offset(sx, sy), p.size! * progress, paint);
        }
      }
      if (batch.isNotEmpty && progress > 0) {
        canvas.drawRawPoints(
          PointMode.points,
          Float32List.fromList(batch),
          Paint()
            ..color = paint.color
            ..strokeWidth = defaultRadius * 2 * progress
            ..strokeCap = StrokeCap.round,
        );
      }
    }
    canvas.restore();

    if (showPointLabels && progress >= 1) {
      for (final s in series) {
        for (final p in s.data) {
          if (p.label == null || p.x < bounds.minX || p.x > bounds.maxX || p.y < bounds.minY || p.y > bounds.maxY) continue;
          final r = p.size ?? defaultRadius;
          final size = axes.measureLabel(p.label!);
          axes.drawLabel(canvas, p.label!, Offset(axes.toScreenX(p.x) + r + 3, axes.toScreenY(p.y) - size.height / 2));
        }
      }
    }

    references.paintLines(canvas, referenceLines);
    paintAnnotations(canvas, annotations, (a) {
      if (a.x < bounds.minX || a.x > bounds.maxX || a.y < bounds.minY || a.y > bounds.maxY) return null;
      return Offset(axes.toScreenX(a.x), axes.toScreenY(a.y));
    }, plotArea, theme);
  }

  /// Hover rebuilds this painter with identical inputs; only real changes
  /// repaint the — possibly huge — data layer.
  @override
  bool shouldRepaint(covariant _ScatterChartPainter old) =>
      !identical(old.series, series) ||
      old.progress != progress ||
      !identical(old.zoom, zoom) ||
      old.theme != theme ||
      old.showGrid != showGrid ||
      old.defaultRadius != defaultRadius ||
      old.xAxisType != xAxisType ||
      old.logX != logX ||
      old.logY != logY ||
      old.xAxisTitle != xAxisTitle ||
      old.yAxisTitle != yAxisTitle ||
      old.xTickFormatter != xTickFormatter ||
      old.yTickFormatter != yTickFormatter ||
      !identical(old.referenceLines, referenceLines) ||
      !identical(old.referenceBands, referenceBands) ||
      !identical(old.annotations, annotations) ||
      old.showPointLabels != showPointLabels;
}

/// The hovered point's highlight and crosshair, painted above the data layer.
class _ScatterHoverPainter extends CustomPainter {
  final ({String series, ChartPoint point, Offset screenPos}) hover;
  final Color color;
  final double radius;
  final bool crosshair;
  final ChartTheme theme;

  _ScatterHoverPainter({required this.hover, required this.color, required this.radius, required this.crosshair, required this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    final p = hover.screenPos;
    if (crosshair) {
      Cartesian2DAxes(plotArea: Cartesian2DAxes.computePlotArea(size), minX: 0, maxX: 1, minY: 0, maxY: 1, theme: theme)
          .drawCrosshair(canvas, p);
    }
    canvas.drawCircle(p, radius, Paint()..color = color);
    canvas.drawCircle(
      p,
      radius + 3,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _ScatterHoverPainter old) =>
      old.hover != hover || old.color != color || old.radius != radius || old.theme != theme;
}
