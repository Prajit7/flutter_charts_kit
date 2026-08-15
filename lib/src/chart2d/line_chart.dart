import 'package:flutter/material.dart';
import 'models.dart';
import 'legend.dart';
import 'cartesian_axes.dart';
import 'theme.dart';
import 'chart_chrome.dart';
import 'zoom.dart';

/// Transient interaction state for [LineChart2D] — hover, an in-progress
/// drag-selection rectangle, and the current zoom window. Held in a single
/// [ValueNotifier] so pointer movement never triggers `setState()`; only
/// the canvas + tooltip subtree rebuilds, not the legend or header.
class _LineInteraction {
  final ({String series, ChartPoint point, Offset screenPos})? hover;
  final Rect? dragRectScreen;
  final ChartZoomWindow? zoom;

  const _LineInteraction({this.hover, this.dragRectScreen, this.zoom});

  _LineInteraction copyWith({
    ({String series, ChartPoint point, Offset screenPos})? hover,
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

/// A generic multi-series line chart with drag-to-zoom.
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
///   xAxisTitle: 'Month',
///   yAxisTitle: 'Revenue',
///   onPointTap: (series, point) => print('$series: ${point?.y}'),
/// )
/// ```
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

  /// Formats x-axis tick values. Ignored for points that set [ChartPoint.label]
  /// — those always show their own label on the x-axis instead.
  final String Function(double value) xTickFormatter;
  final String Function(double value) yTickFormatter;

  final bool filled;
  final bool showGrid;
  final bool showLegend;
  final bool showPoints;
  final bool showCrosshair;
  final double lineWidth;
  final double pointRadius;

  final bool enableAnimation;
  final Duration animationDuration;

  /// Drag-to-zoom mode. [ChartZoomMode.x] (default) zooms the x-range and
  /// auto-rescales y; [ChartZoomMode.xy] zooms both axes to the dragged
  /// rectangle; [ChartZoomMode.none] disables zoom.
  final ChartZoomMode zoomMode;

  /// Minimum drag distance (px) before a drag counts as a zoom selection
  /// rather than an accidental nudge.
  final double zoomDragThreshold;

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
    this.xTickFormatter = _defaultFormatter,
    this.yTickFormatter = _defaultFormatter,
    this.filled = false,
    this.showGrid = true,
    this.showLegend = true,
    this.showPoints = true,
    this.showCrosshair = true,
    this.lineWidth = 2.2,
    this.pointRadius = 3.5,
    this.enableAnimation = true,
    this.animationDuration = const Duration(milliseconds: 650),
    this.zoomMode = ChartZoomMode.x,
    this.zoomDragThreshold = 12,
    this.onPointHover,
    this.onPointTap,
  });

  static String _defaultFormatter(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  State<LineChart2D> createState() => _LineChart2DState();
}

class _LineChart2DState extends State<LineChart2D> with SingleTickerProviderStateMixin {
  final ValueNotifier<Set<String>> _hiddenNotifier = ValueNotifier(const {});
  final ValueNotifier<_LineInteraction> _interactionNotifier = ValueNotifier(const _LineInteraction());
  late final AnimationController _controller;

  Offset? _dragStartLocal;

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
  void didUpdateWidget(covariant LineChart2D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.series, widget.series)) {
      if (widget.enableAnimation) _controller.forward(from: 0);
      _interactionNotifier.value = const _LineInteraction(); // data changed — zoom window may be stale
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _hiddenNotifier.dispose();
    _interactionNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);

    if (widget.series.isEmpty || widget.series.every((s) => s.data.isEmpty)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChartHeader(title: widget.title, subtitle: widget.subtitle),
          Expanded(child: ChartEmptyState(message: widget.emptyStateMessage)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChartHeader(title: widget.title, subtitle: widget.subtitle),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight - (widget.showLegend ? 32 : 0));
              return ValueListenableBuilder<Set<String>>(
                valueListenable: _hiddenNotifier,
                builder: (context, hidden, _) {
                  final visibleSeries = widget.series.where((s) => !hidden.contains(s.name)).toList();
                  return Column(
                    children: [
                      Expanded(
                        child: MouseRegion(
                          onHover: (e) => _updateHover(e.localPosition, size, visibleSeries),
                          onExit: (_) {
                            final current = _interactionNotifier.value;
                            _interactionNotifier.value = current.copyWith(clearHover: true);
                            widget.onPointHover?.call(null, null);
                          },
                          child: GestureDetector(
                            onTapUp: (d) => _handleTap(d.localPosition, size, visibleSeries),
                            onPanStart: widget.zoomMode == ChartZoomMode.none
                                ? null
                                : (d) => _handlePanStart(d.localPosition, size),
                            onPanUpdate: widget.zoomMode == ChartZoomMode.none
                                ? null
                                : (d) => _handlePanUpdate(d.localPosition, size),
                            onPanEnd: widget.zoomMode == ChartZoomMode.none
                                ? null
                                : (_) => _handlePanEnd(size, visibleSeries),
                            child: ValueListenableBuilder<_LineInteraction>(
                              valueListenable: _interactionNotifier,
                              builder: (context, interaction, __) {
                                return Stack(
                                  children: [
                                    AnimatedBuilder(
                                      animation: _controller,
                                      builder: (context, _) => CustomPaint(
                                        size: size,
                                        painter: _LineChartPainter(
                                          series: visibleSeries,
                                          theme: theme,
                                          xAxisTitle: widget.xAxisTitle,
                                          yAxisTitle: widget.yAxisTitle,
                                          xTickFormatter: widget.xTickFormatter,
                                          yTickFormatter: widget.yTickFormatter,
                                          filled: widget.filled,
                                          showGrid: widget.showGrid,
                                          showPoints: widget.showPoints,
                                          lineWidth: widget.lineWidth,
                                          pointRadius: widget.pointRadius,
                                          hoverKey: interaction.hover == null
                                              ? null
                                              : (interaction.hover!.series, interaction.hover!.point),
                                          crosshairPoint:
                                              widget.showCrosshair ? interaction.hover?.screenPos : null,
                                          progress: _controller.value,
                                          zoom: interaction.zoom,
                                        ),
                                      ),
                                    ),
                                    if (interaction.dragRectScreen != null)
                                      Positioned.fromRect(
                                        rect: interaction.dragRectScreen!,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: theme.crosshairColor.withOpacity(0.15),
                                            border: Border.all(color: theme.crosshairColor, width: 1),
                                          ),
                                        ),
                                      ),
                                    if (interaction.zoom != null)
                                      Positioned(
                                        right: 8,
                                        top: 8,
                                        child: _ResetZoomButton(
                                          onTap: () {
                                            final current = _interactionNotifier.value;
                                            _interactionNotifier.value = current.copyWith(clearZoom: true);
                                          },
                                        ),
                                      ),
                                    if (interaction.hover != null)
                                      _buildTooltip(interaction.hover!, size, theme),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      if (widget.showLegend)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Chart2DLegend(
                            entries: widget.series.map((s) => LegendEntry(label: s.name, color: s.color)).toList(),
                            hidden: hidden,
                            onToggle: (name) {
                              final next = {...hidden};
                              next.contains(name) ? next.remove(name) : next.add(name);
                              _hiddenNotifier.value = next;
                              _interactionNotifier.value = _interactionNotifier.value.copyWith(clearHover: true);
                            },
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------------- zoom drag handling ----------------

  void _handlePanStart(Offset pos, Size size) {
    final plotArea = Cartesian2DAxes.computePlotArea(size);
    if (!plotArea.contains(pos)) return;
    _dragStartLocal = pos;
  }

  void _handlePanUpdate(Offset pos, Size size) {
    if (_dragStartLocal == null) return;
    final plotArea = Cartesian2DAxes.computePlotArea(size);
    final clamped = Offset(
      pos.dx.clamp(plotArea.left, plotArea.right),
      pos.dy.clamp(plotArea.top, plotArea.bottom),
    );
    Rect rect;
    if (widget.zoomMode == ChartZoomMode.xy) {
      rect = Rect.fromPoints(_dragStartLocal!, clamped);
    } else {
      // x-only zoom: show a full-height band (like Highcharts) rather than
      // a sliver that only covers however far the pointer wandered
      // vertically — the y-extent of the drag isn't used for x-zoom anyway.
      rect = Rect.fromLTRB(
        _dragStartLocal!.dx < clamped.dx ? _dragStartLocal!.dx : clamped.dx,
        plotArea.top,
        _dragStartLocal!.dx < clamped.dx ? clamped.dx : _dragStartLocal!.dx,
        plotArea.bottom,
      );
    }
    final current = _interactionNotifier.value;
    _interactionNotifier.value = current.copyWith(dragRectScreen: rect, clearHover: true);
  }

  void _handlePanEnd(Size size, List<XySeries> visibleSeries) {
    final current = _interactionNotifier.value;
    final rect = current.dragRectScreen;
    _dragStartLocal = null;
    if (rect == null) return;

    if (rect.width < widget.zoomDragThreshold) {
      // too small to count as an intentional zoom — just clear the box
      _interactionNotifier.value = current.copyWith(clearDragRect: true);
      return;
    }

    final plotArea = Cartesian2DAxes.computePlotArea(size);
    final bounds = _effectiveBounds(visibleSeries, current.zoom);
    final axes = Cartesian2DAxes(
      plotArea: plotArea,
      minX: bounds.minX,
      maxX: bounds.maxX,
      minY: bounds.minY,
      maxY: bounds.maxY,
    );

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
    if (changed) {
      widget.onPointHover?.call(hit?.series, hit?.point);
    }
  }

  ({String series, ChartPoint point, Offset screenPos})? _hitTest(
      Offset pos, Size size, List<XySeries> visibleSeries) {
    if (visibleSeries.isEmpty) return null;
    final plotArea = Cartesian2DAxes.computePlotArea(size);
    final bounds = _effectiveBounds(visibleSeries, _interactionNotifier.value.zoom);
    final axes = Cartesian2DAxes(
      plotArea: plotArea,
      minX: bounds.minX,
      maxX: bounds.maxX,
      minY: bounds.minY,
      maxY: bounds.maxY,
    );

    String? bestSeries;
    ChartPoint? bestPoint;
    double bestDist = 26; // px hit radius
    for (final s in visibleSeries) {
      for (final p in s.data) {
        final sp = Offset(axes.toScreenX(p.x), axes.toScreenY(p.y));
        final d = (sp - pos).distance;
        if (d < bestDist) {
          bestDist = d;
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
    const cardWidth = 150.0;
    double left = hover.screenPos.dx + 12;
    double top = hover.screenPos.dy - 50;
    if (left + cardWidth > size.width) left = hover.screenPos.dx - cardWidth - 12;
    if (top < 0) top = 4;

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          width: cardWidth,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.tooltipBackgroundColor,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 10, offset: const Offset(0, 3))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(hover.series,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: theme.tooltipTextColor)),
              Text(
                hover.point.label ?? widget.xTickFormatter(hover.point.x),
                style: TextStyle(fontSize: 11, color: theme.tooltipTextColor.withOpacity(0.7)),
              ),
              Text(widget.yTickFormatter(hover.point.y),
                  style: TextStyle(fontSize: 13, color: theme.tooltipTextColor)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Computes the data-space bounds a chart should display: either the
/// current [zoom] window, or the full extent of [series] if not zoomed.
/// When only x is zoomed (`zoom.minY == null`), y auto-rescales to fit
/// just the points inside that x-range — matching Highcharts' behavior.
({double minX, double maxX, double minY, double maxY}) _effectiveBounds(
  List<XySeries> series,
  ChartZoomWindow? zoom,
) {
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
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
  }
  if (minX.isInfinite) {
    // nothing fell inside the zoom window — fall back to the window itself
    minX = xMin ?? 0;
    maxX = xMax ?? 1;
    minY = 0;
    maxY = 1;
  } else if (zoom == null) {
    // Only anchor at zero for the default, unzoomed view.
    if (minY > 0) minY = 0;
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

class _ResetZoomButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ResetZoomButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(Icons.zoom_out_map, size: 18),
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<XySeries> series;
  final ChartTheme theme;
  final String? xAxisTitle;
  final String? yAxisTitle;
  final String Function(double) xTickFormatter;
  final String Function(double) yTickFormatter;
  final bool filled;
  final bool showGrid;
  final bool showPoints;
  final double lineWidth;
  final double pointRadius;
  final (String, ChartPoint)? hoverKey;
  final Offset? crosshairPoint;
  final ChartZoomWindow? zoom;

  /// 0 (nothing drawn) to 1 (fully drawn) — drives the entrance animation.
  final double progress;

  _LineChartPainter({
    required this.series,
    required this.theme,
    required this.xAxisTitle,
    required this.yAxisTitle,
    required this.xTickFormatter,
    required this.yTickFormatter,
    required this.filled,
    required this.showGrid,
    required this.showPoints,
    required this.lineWidth,
    required this.pointRadius,
    required this.hoverKey,
    required this.crosshairPoint,
    required this.progress,
    required this.zoom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;

    final bounds = _effectiveBounds(series, zoom);
    final plotArea = Cartesian2DAxes.computePlotArea(size);
    final axes = Cartesian2DAxes(
      plotArea: plotArea,
      minX: bounds.minX,
      maxX: bounds.maxX,
      minY: bounds.minY,
      maxY: bounds.maxY,
      theme: theme,
    );
    final yTicks = Cartesian2DAxes.niceTicks(bounds.minY, bounds.maxY);

    axes.drawGridAndAxes(
      canvas,
      yTicks: yTicks,
      yFormatter: yTickFormatter,
      xAxisTitle: xAxisTitle,
      yAxisTitle: yAxisTitle,
      showGrid: showGrid,
    );

    // Only draw/tick points that fall within the current window.
    List<ChartPoint> visiblePoints(XySeries s) {
      return s.data.where((p) {
        if (p.x < bounds.minX || p.x > bounds.maxX) return false;
        if (zoom?.minY != null && p.y < zoom!.minY!) return false;
        if (zoom?.maxY != null && p.y > zoom!.maxY!) return false;
        return true;
      }).toList();
    }

    // x ticks: use labels from the series with the most visible points
    final candidates = series.map(visiblePoints).where((l) => l.isNotEmpty).toList();
    if (candidates.isNotEmpty) {
      final labelPoints = candidates.reduce((a, b) => a.length >= b.length ? a : b);
      final stride = labelPoints.length > 8 ? (labelPoints.length / 6).ceil() : 1;
      for (int i = 0; i < labelPoints.length; i += stride) {
        final p = labelPoints[i];
        axes.drawXTick(canvas, axes.toScreenX(p.x), p.label ?? xTickFormatter(p.x));
      }
    }

    for (final s in series) {
      final pts = visiblePoints(s);
      if (pts.isEmpty) continue;
      final sorted = [...pts]..sort((a, b) => a.x.compareTo(b.x));

      final line = Path();
      for (int i = 0; i < sorted.length; i++) {
        final sp = Offset(axes.toScreenX(sorted[i].x), axes.toScreenY(sorted[i].y));
        i == 0 ? line.moveTo(sp.dx, sp.dy) : line.lineTo(sp.dx, sp.dy);
      }

      // Draw-in animation: reveal the line left-to-right by clipping each
      // path segment to `progress` of its total length.
      final animatedLine = _truncatePath(line, progress);

      if (filled) {
        final area = Path();
        area.moveTo(axes.toScreenX(sorted.first.x), axes.toScreenY(0));
        double lastX = axes.toScreenX(sorted.first.x);
        for (final m in animatedLine.computeMetrics()) {
          final tangent = m.getTangentForOffset(m.length);
          if (tangent != null) lastX = tangent.position.dx;
        }
        area.addPath(animatedLine, Offset.zero);
        area.lineTo(lastX, axes.toScreenY(0));
        area.close();
        canvas.drawPath(area, Paint()..color = s.color.withOpacity(0.15));
      }

      canvas.drawPath(
        animatedLine,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = lineWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );

      if (showPoints) {
        for (final p in sorted) {
          final sp = Offset(axes.toScreenX(p.x), axes.toScreenY(p.y));
          final isHovered = hoverKey != null && hoverKey!.$1 == s.name && hoverKey!.$2 == p;
          final r = (isHovered ? pointRadius + 2 : pointRadius) * progress;
          canvas.drawCircle(sp, r, Paint()..color = s.color.withOpacity(progress));
          if (isHovered) {
            canvas.drawCircle(
              sp,
              pointRadius + 4,
              Paint()
                ..color = s.color
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5,
            );
          }
        }
      }
    }

    if (crosshairPoint != null) {
      axes.drawCrosshair(canvas, crosshairPoint!);
    }
  }

  Path _truncatePath(Path source, double t) {
    if (t >= 1) return source;
    if (t <= 0) return Path();
    final result = Path();
    for (final metric in source.computeMetrics()) {
      result.addPath(metric.extractPath(0, metric.length * t), Offset.zero);
    }
    return result;
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) => true;
}
