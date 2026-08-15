import 'package:flutter/material.dart';
import 'models.dart';
import 'legend.dart';
import 'cartesian_axes.dart';
import 'theme.dart';
import 'chart_chrome.dart';
import 'zoom.dart';

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
  final String Function(double value) xTickFormatter;
  final String Function(double value) yTickFormatter;
  final bool showGrid;
  final bool showLegend;
  final bool showCrosshair;
  final double defaultPointRadius;

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
    this.xTickFormatter = _defaultFormatter,
    this.yTickFormatter = _defaultFormatter,
    this.showGrid = true,
    this.showLegend = true,
    this.showCrosshair = true,
    this.defaultPointRadius = 5,
    this.enableAnimation = true,
    this.animationDuration = const Duration(milliseconds: 500),
    this.zoomMode = ChartZoomMode.xy,
    this.zoomDragThreshold = 12,
    this.onPointHover,
    this.onPointTap,
  });

  static String _defaultFormatter(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  State<ScatterChart2D> createState() => _ScatterChart2DState();
}

class _ScatterChart2DState extends State<ScatterChart2D> with SingleTickerProviderStateMixin {
  final ValueNotifier<Set<String>> _hiddenNotifier = ValueNotifier(const {});
  final ValueNotifier<_ScatterInteraction> _interactionNotifier =
      ValueNotifier(const _ScatterInteraction());
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
  void didUpdateWidget(covariant ScatterChart2D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.series, widget.series)) {
      if (widget.enableAnimation) _controller.forward(from: 0);
      _interactionNotifier.value = const _ScatterInteraction();
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
                            child: ValueListenableBuilder<_ScatterInteraction>(
                              valueListenable: _interactionNotifier,
                              builder: (context, interaction, __) {
                                return Stack(
                                  children: [
                                    AnimatedBuilder(
                                      animation: _controller,
                                      builder: (context, _) => CustomPaint(
                                        size: size,
                                        painter: _ScatterChartPainter(
                                          series: visibleSeries,
                                          theme: theme,
                                          xAxisTitle: widget.xAxisTitle,
                                          yAxisTitle: widget.yAxisTitle,
                                          xTickFormatter: widget.xTickFormatter,
                                          yTickFormatter: widget.yTickFormatter,
                                          showGrid: widget.showGrid,
                                          defaultRadius: widget.defaultPointRadius,
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
      // x-only zoom: show a full-height band rather than a sliver that
      // only covers however far the pointer wandered vertically.
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

    if (rect.width < widget.zoomDragThreshold && rect.height < widget.zoomDragThreshold) {
      _interactionNotifier.value = current.copyWith(clearDragRect: true);
      return;
    }

    final plotArea = Cartesian2DAxes.computePlotArea(size);
    final bounds = _effectiveScatterBounds(visibleSeries, current.zoom);
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
    final bounds = _effectiveScatterBounds(visibleSeries, _interactionNotifier.value.zoom);
    final axes = Cartesian2DAxes(
      plotArea: plotArea,
      minX: bounds.minX,
      maxX: bounds.maxX,
      minY: bounds.minY,
      maxY: bounds.maxY,
    );

    String? bestSeries;
    ChartPoint? bestPoint;
    double bestDist = 22;
    for (final s in visibleSeries) {
      for (final p in s.data) {
        final r = p.size ?? widget.defaultPointRadius;
        final sp = Offset(axes.toScreenX(p.x), axes.toScreenY(p.y));
        final d = (sp - pos).distance;
        if (d < bestDist + r) {
          if (d < bestDist) {
            bestDist = d;
          }
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
              Text(hover.series, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: theme.tooltipTextColor)),
              Text(
                hover.point.label ?? '(${widget.xTickFormatter(hover.point.x)}, ${widget.yTickFormatter(hover.point.y)})',
                style: TextStyle(fontSize: 11, color: theme.tooltipTextColor.withOpacity(0.7)),
              ),
              if (hover.point.label != null)
                Text(
                  '(${widget.xTickFormatter(hover.point.x)}, ${widget.yTickFormatter(hover.point.y)})',
                  style: TextStyle(fontSize: 12, color: theme.tooltipTextColor),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Computes the data-space bounds to display: the current [zoom] window
/// (if any), else the full extent of [series] padded 8% on each axis so
/// points aren't clipped at the edges.
({double minX, double maxX, double minY, double maxY}) _effectiveScatterBounds(
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
    minX = xMin ?? 0;
    maxX = xMax ?? 1;
    minY = 0;
    maxY = 1;
  }
  final xPad = (maxX - minX) * 0.08;
  final yPad = (maxY - minY) * 0.08;
  return (
    minX: xMin ?? (minX - xPad),
    maxX: xMax ?? (maxX + xPad),
    minY: minY - yPad,
    maxY: maxY + yPad,
  );
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

class _ScatterChartPainter extends CustomPainter {
  final List<XySeries> series;
  final ChartTheme theme;
  final String? xAxisTitle;
  final String? yAxisTitle;
  final String Function(double) xTickFormatter;
  final String Function(double) yTickFormatter;
  final bool showGrid;
  final double defaultRadius;
  final (String, ChartPoint)? hoverKey;
  final Offset? crosshairPoint;
  final ChartZoomWindow? zoom;

  /// 0 (invisible) to 1 (full size) — drives the pop-in entrance animation.
  final double progress;

  _ScatterChartPainter({
    required this.series,
    required this.theme,
    required this.xAxisTitle,
    required this.yAxisTitle,
    required this.xTickFormatter,
    required this.yTickFormatter,
    required this.showGrid,
    required this.defaultRadius,
    required this.hoverKey,
    required this.crosshairPoint,
    required this.progress,
    required this.zoom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;

    final bounds = _effectiveScatterBounds(series, zoom);
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
    final xTicks = Cartesian2DAxes.niceTicks(bounds.minX, bounds.maxX);

    axes.drawGridAndAxes(
      canvas,
      yTicks: yTicks,
      yFormatter: yTickFormatter,
      xAxisTitle: xAxisTitle,
      yAxisTitle: yAxisTitle,
      showGrid: showGrid,
    );
    for (final xv in xTicks) {
      axes.drawXTick(canvas, axes.toScreenX(xv), xTickFormatter(xv));
    }

    for (final s in series) {
      for (final p in s.data) {
        if (p.x < bounds.minX || p.x > bounds.maxX || p.y < bounds.minY || p.y > bounds.maxY) {
          continue;
        }
        final sp = Offset(axes.toScreenX(p.x), axes.toScreenY(p.y));
        final r = (p.size ?? defaultRadius) * progress;
        final isHovered = hoverKey != null && hoverKey!.$1 == s.name && hoverKey!.$2 == p;
        canvas.drawCircle(sp, r, Paint()..color = s.color.withOpacity((isHovered ? 1 : 0.75) * progress));
        if (isHovered) {
          canvas.drawCircle(
            sp,
            r + 3,
            Paint()
              ..color = s.color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        }
      }
    }

    if (crosshairPoint != null) {
      axes.drawCrosshair(canvas, crosshairPoint!);
    }
  }

  @override
  bool shouldRepaint(covariant _ScatterChartPainter oldDelegate) => true;
}
