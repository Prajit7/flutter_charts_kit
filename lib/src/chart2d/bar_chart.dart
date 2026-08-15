import 'package:flutter/material.dart';
import 'models.dart';
import 'legend.dart';
import 'cartesian_axes.dart';
import 'theme.dart';
import 'chart_chrome.dart';
import 'zoom.dart';

/// Zoom window for [BarChart2D] — a contiguous range of category indices
/// (from the *original* `categories` list), plus an optional y-range.
class _BarZoomWindow {
  final int startIndex;
  final int endIndexExclusive; // exclusive
  final double? minY;
  final double? maxY;

  const _BarZoomWindow({required this.startIndex, required this.endIndexExclusive, this.minY, this.maxY});

  int get length => endIndexExclusive - startIndex;
}

class _BarInteraction {
  final (int, String, double, Offset)? hover;
  final Rect? dragRectScreen;
  final _BarZoomWindow? zoom;

  const _BarInteraction({this.hover, this.dragRectScreen, this.zoom});

  _BarInteraction copyWith({
    (int, String, double, Offset)? hover,
    bool clearHover = false,
    Rect? dragRectScreen,
    bool clearDragRect = false,
    _BarZoomWindow? zoom,
    bool clearZoom = false,
  }) {
    return _BarInteraction(
      hover: clearHover ? null : (hover ?? this.hover),
      dragRectScreen: clearDragRect ? null : (dragRectScreen ?? this.dragRectScreen),
      zoom: clearZoom ? null : (zoom ?? this.zoom),
    );
  }
}

/// A generic multi-series bar/column chart with drag-to-zoom.
///
/// ```dart
/// BarChart2D(
///   title: 'Sales by Region',
///   categories: ['Jan', 'Feb', 'Mar'],
///   series: [
///     CategorySeries(name: 'Product A', color: Colors.blue, values: [10, 14, 9]),
///     CategorySeries(name: 'Product B', color: Colors.orange, values: [6, 8, 12]),
///   ],
///   onBarTap: (series, category, value) => print('$series/$category: $value'),
/// )
/// ```
///
/// Drag horizontally to zoom into a range of categories (y auto-rescales
/// to fit); with [zoomMode] set to [ChartZoomMode.xy], the vertical extent
/// of the drag also zooms the y-axis. A reset button appears while zoomed.
class BarChart2D extends StatefulWidget {
  final List<String> categories;
  final List<CategorySeries> series;
  final bool stacked;
  final String? title;
  final String? subtitle;
  final String? xAxisTitle;
  final String? yAxisTitle;
  final String emptyStateMessage;
  final String Function(double value) yTickFormatter;
  final bool showGrid;
  final bool showLegend;

  final bool enableAnimation;
  final Duration animationDuration;

  /// Drag-to-zoom mode. [ChartZoomMode.x] (default) zooms the category
  /// range and auto-rescales y; [ChartZoomMode.xy] also zooms y to the
  /// dragged rectangle; [ChartZoomMode.none] disables zoom.
  final ChartZoomMode zoomMode;

  /// Minimum drag distance (px) before a drag counts as a zoom selection.
  final double zoomDragThreshold;

  /// Fired continuously as the pointer moves over/off a bar (mouse hover
  /// and touch). Called with `(null, null, null)` when nothing is hovered.
  final ChartBarCallback? onBarHover;

  /// Fired once per tap/click on a bar. Not called on taps that miss.
  final ChartBarCallback? onBarTap;

  const BarChart2D({
    super.key,
    required this.categories,
    required this.series,
    this.stacked = false,
    this.title,
    this.subtitle,
    this.xAxisTitle,
    this.yAxisTitle,
    this.emptyStateMessage = 'No data to display',
    this.yTickFormatter = _defaultFormatter,
    this.showGrid = true,
    this.showLegend = true,
    this.enableAnimation = true,
    this.animationDuration = const Duration(milliseconds: 550),
    this.zoomMode = ChartZoomMode.x,
    this.zoomDragThreshold = 12,
    this.onBarHover,
    this.onBarTap,
  });

  static String _defaultFormatter(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  State<BarChart2D> createState() => _BarChart2DState();
}

class _BarChart2DState extends State<BarChart2D> with SingleTickerProviderStateMixin {
  final ValueNotifier<Set<String>> _hiddenNotifier = ValueNotifier(const {});
  final ValueNotifier<_BarInteraction> _interactionNotifier = ValueNotifier(const _BarInteraction());
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
  void didUpdateWidget(covariant BarChart2D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.series, widget.series) || !identical(oldWidget.categories, widget.categories)) {
      if (widget.enableAnimation) _controller.forward(from: 0);
      _interactionNotifier.value = const _BarInteraction();
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

    if (widget.categories.isEmpty || widget.series.isEmpty) {
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
                          child: MouseRegion(
                            onHover: (e) => _updateHover(e.localPosition, size, visibleSeries),
                            onExit: (_) {
                              final current = _interactionNotifier.value;
                              _interactionNotifier.value = current.copyWith(clearHover: true);
                              widget.onBarHover?.call(null, null, null);
                            },
                            child: ValueListenableBuilder<_BarInteraction>(
                              valueListenable: _interactionNotifier,
                              builder: (context, interaction, __) {
                                return Stack(
                                  children: [
                                    AnimatedBuilder(
                                      animation: _controller,
                                      builder: (context, _) => CustomPaint(
                                        size: size,
                                        painter: _BarChartPainter(
                                          categories: widget.categories,
                                          series: visibleSeries,
                                          stacked: widget.stacked,
                                          theme: theme,
                                          xAxisTitle: widget.xAxisTitle,
                                          yAxisTitle: widget.yAxisTitle,
                                          yTickFormatter: widget.yTickFormatter,
                                          showGrid: widget.showGrid,
                                          hover: interaction.hover,
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
                                    if (interaction.hover != null) _buildTooltip(interaction.hover!, size, theme),
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
      // category-range zoom: show a full-height band rather than a sliver
      // that only covers however far the pointer wandered vertically.
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

  void _handlePanEnd(Size size, List<CategorySeries> visibleSeries) {
    final current = _interactionNotifier.value;
    final rect = current.dragRectScreen;
    _dragStartLocal = null;
    if (rect == null) return;

    if (rect.width < widget.zoomDragThreshold) {
      _interactionNotifier.value = current.copyWith(clearDragRect: true);
      return;
    }

    final plotArea = Cartesian2DAxes.computePlotArea(size);
    final visibleIndices = _currentVisibleIndices(current.zoom);
    final geometry = _BarGeometry(
      categories: widget.categories,
      series: visibleSeries,
      stacked: widget.stacked,
      plotArea: plotArea,
      visibleIndices: visibleIndices,
      fixedMinY: current.zoom?.minY,
      fixedMaxY: current.zoom?.maxY,
    );

    // Map screen x back to a "slot" position within the currently visible
    // categories, then to original category indices. startSlot must stay a
    // valid index (0..length-1); endSlotExclusive is a count (1..length) so
    // endSlotExclusive-1 is also always a valid index.
    final slotWidth = plotArea.width / visibleIndices.length;
    final startSlot =
        ((rect.left - plotArea.left) / slotWidth).floor().clamp(0, visibleIndices.length - 1);
    final endSlotExclusive =
        ((rect.right - plotArea.left) / slotWidth).ceil().clamp(1, visibleIndices.length);

    if (endSlotExclusive - startSlot < 1) {
      _interactionNotifier.value = current.copyWith(clearDragRect: true);
      return;
    }

    final newStartIndex = visibleIndices[startSlot];
    final newEndIndexExclusive = visibleIndices[endSlotExclusive - 1] + 1;

    double? newMinY;
    double? newMaxY;
    if (widget.zoomMode == ChartZoomMode.xy) {
      final yRange = geometry.maxY - geometry.minY == 0 ? 1 : geometry.maxY - geometry.minY;
      final yScale = plotArea.height / yRange;
      final yZero = plotArea.bottom + geometry.minY * yScale;
      newMaxY = (yZero - rect.top) / yScale;
      newMinY = (yZero - rect.bottom) / yScale;
    }

    _interactionNotifier.value = current.copyWith(
      zoom: _BarZoomWindow(
        startIndex: newStartIndex,
        endIndexExclusive: newEndIndexExclusive,
        minY: newMinY,
        maxY: newMaxY,
      ),
      clearDragRect: true,
    );
  }

  List<int> _currentVisibleIndices(_BarZoomWindow? zoom) {
    if (zoom == null) return List.generate(widget.categories.length, (i) => i);
    return List.generate(zoom.length, (i) => zoom.startIndex + i);
  }

  // ---------------- hover / tap handling ----------------

  void _handleTap(Offset pos, Size size, List<CategorySeries> visibleSeries) {
    final hit = _hitTest(pos, size, visibleSeries);
    _applyHover(hit);
    if (hit != null) {
      widget.onBarTap?.call(hit.$2, widget.categories[hit.$1], hit.$3);
    }
  }

  void _updateHover(Offset pos, Size size, List<CategorySeries> visibleSeries) {
    final hit = _hitTest(pos, size, visibleSeries);
    _applyHover(hit);
  }

  void _applyHover((int, String, double, Offset)? hit) {
    final current = _interactionNotifier.value;
    final changed = hit?.$1 != current.hover?.$1 || hit?.$2 != current.hover?.$2;
    _interactionNotifier.value = hit == null ? current.copyWith(clearHover: true) : current.copyWith(hover: hit);
    if (changed) {
      widget.onBarHover?.call(hit?.$2, hit == null ? null : widget.categories[hit.$1], hit?.$3);
    }
  }

  (int, String, double, Offset)? _hitTest(Offset pos, Size size, List<CategorySeries> visibleSeries) {
    if (visibleSeries.isEmpty || widget.categories.isEmpty) return null;
    final zoom = _interactionNotifier.value.zoom;
    final geometry = _BarGeometry(
      categories: widget.categories,
      series: visibleSeries,
      stacked: widget.stacked,
      plotArea: Cartesian2DAxes.computePlotArea(size),
      visibleIndices: _currentVisibleIndices(zoom),
      fixedMinY: zoom?.minY,
      fixedMaxY: zoom?.maxY,
    );
    return geometry.hitTest(pos);
  }

  Widget _buildTooltip((int, String, double, Offset) hover, Size size, ChartTheme theme) {
    final (catIndex, seriesName, value, pos) = hover;
    const cardWidth = 150.0;
    double left = pos.dx + 10;
    double top = pos.dy - 50;
    if (left + cardWidth > size.width) left = pos.dx - cardWidth - 10;
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
              Text(seriesName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: theme.tooltipTextColor)),
              Text(widget.categories[catIndex],
                  style: TextStyle(fontSize: 11, color: theme.tooltipTextColor.withOpacity(0.7))),
              Text(widget.yTickFormatter(value), style: TextStyle(fontSize: 13, color: theme.tooltipTextColor)),
            ],
          ),
        ),
      ),
    );
  }
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

/// Shared bar-position math between the painter and hit-testing so they
/// always agree on where each bar actually is. [visibleIndices] are the
/// *original* category indices to render, stretched to fill [plotArea] —
/// this is what makes zooming into a category range work.
class _BarGeometry {
  final List<String> categories;
  final List<CategorySeries> series;
  final bool stacked;
  final Rect plotArea;
  final List<int> visibleIndices;
  final double? fixedMinY;
  final double? fixedMaxY;

  _BarGeometry({
    required this.categories,
    required this.series,
    required this.stacked,
    required this.plotArea,
    required this.visibleIndices,
    this.fixedMinY,
    this.fixedMaxY,
  });

  double get minY {
    if (fixedMinY != null) return fixedMinY!;
    double m = 0;
    for (final s in series) {
      for (final idx in visibleIndices) {
        if (idx < s.values.length && s.values[idx] < m) m = s.values[idx];
      }
    }
    return m;
  }

  double get maxY {
    if (fixedMaxY != null) return fixedMaxY!;
    double m = 0;
    if (stacked) {
      for (final idx in visibleIndices) {
        double sum = 0;
        for (final s in series) {
          if (idx < s.values.length && s.values[idx] > 0) sum += s.values[idx];
        }
        if (sum > m) m = sum;
      }
    } else {
      for (final s in series) {
        for (final idx in visibleIndices) {
          if (idx < s.values.length && s.values[idx] > m) m = s.values[idx];
        }
      }
    }
    return m;
  }

  double _y(double value, double yScale, double yZero) => yZero - value * yScale;

  /// Returns (originalCategoryIndex, seriesIndex, Rect) for every bar, so
  /// painting and hit-testing share identical geometry.
  List<(int, int, Rect)> buildBars() {
    final bars = <(int, int, Rect)>[];
    final catCount = visibleIndices.length;
    if (catCount == 0 || series.isEmpty) return bars;

    final groupWidth = plotArea.width / catCount;
    final yRange = maxY - minY == 0 ? 1 : maxY - minY;
    final yScale = plotArea.height / yRange;
    final yZero = plotArea.bottom + minY * yScale;

    for (int slot = 0; slot < catCount; slot++) {
      final c = visibleIndices[slot];
      final groupLeft = plotArea.left + slot * groupWidth;
      if (stacked) {
        double posStackTop = 0;
        double negStackTop = 0;
        final barWidth = groupWidth * 0.6;
        final barLeft = groupLeft + (groupWidth - barWidth) / 2;
        for (int s = 0; s < series.length; s++) {
          final v = c < series[s].values.length ? series[s].values[c] : 0.0;
          if (v >= 0) {
            final top = _y(posStackTop + v, yScale, yZero);
            final bottom = _y(posStackTop, yScale, yZero);
            bars.add((c, s, Rect.fromLTRB(barLeft, top, barLeft + barWidth, bottom)));
            posStackTop += v;
          } else {
            final top = _y(negStackTop, yScale, yZero);
            final bottom = _y(negStackTop + v, yScale, yZero);
            bars.add((c, s, Rect.fromLTRB(barLeft, top, barLeft + barWidth, bottom)));
            negStackTop += v;
          }
        }
      } else {
        final barWidth = (groupWidth * 0.7) / series.length;
        final groupInnerLeft = groupLeft + (groupWidth * 0.15);
        for (int s = 0; s < series.length; s++) {
          final v = c < series[s].values.length ? series[s].values[c] : 0.0;
          final left = groupInnerLeft + s * barWidth;
          final edge = _y(v, yScale, yZero); // above zero line if v>0, below if v<0
          final top = edge < yZero ? edge : yZero;
          final bottom = edge < yZero ? yZero : edge;
          bars.add((c, s, Rect.fromLTRB(left, top, left + barWidth, bottom)));
        }
      }
    }
    return bars;
  }

  /// Same as [buildBars] but with each bar's height scaled toward the
  /// zero baseline by [progress] — used to animate bars growing in.
  List<(int, int, Rect)> buildAnimatedBars(double progress) {
    if (progress >= 1) return buildBars();
    final yZero = _zeroScreenY();
    return buildBars().map((entry) {
      final (c, s, rect) = entry;
      final top = _lerp(yZero, rect.top, progress);
      final bottom = _lerp(yZero, rect.bottom, progress);
      return (c, s, Rect.fromLTRB(rect.left, top < bottom ? top : bottom, rect.right, top < bottom ? bottom : top));
    }).toList();
  }

  double _zeroScreenY() {
    final yRange = maxY - minY == 0 ? 1 : maxY - minY;
    final yScale = plotArea.height / yRange;
    return plotArea.bottom + minY * yScale;
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  (int, String, double, Offset)? hitTest(Offset pos) {
    for (final (c, s, rect) in buildBars()) {
      if (rect.inflate(1).contains(pos)) {
        return (c, series[s].name, series[s].values[c], Offset(rect.center.dx, rect.top));
      }
    }
    return null;
  }
}

class _BarChartPainter extends CustomPainter {
  final List<String> categories;
  final List<CategorySeries> series;
  final bool stacked;
  final ChartTheme theme;
  final String? xAxisTitle;
  final String? yAxisTitle;
  final String Function(double) yTickFormatter;
  final bool showGrid;
  final (int, String, double, Offset)? hover;
  final _BarZoomWindow? zoom;

  /// 0 (bars flat) to 1 (full height) — drives the entrance animation.
  final double progress;

  _BarChartPainter({
    required this.categories,
    required this.series,
    required this.stacked,
    required this.theme,
    required this.xAxisTitle,
    required this.yAxisTitle,
    required this.yTickFormatter,
    required this.showGrid,
    required this.hover,
    required this.progress,
    required this.zoom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (categories.isEmpty || series.isEmpty) return;

    final visibleIndices = zoom == null
        ? List.generate(categories.length, (i) => i)
        : List.generate(zoom!.length, (i) => zoom!.startIndex + i);

    final plotArea = Cartesian2DAxes.computePlotArea(size);
    final geometry = _BarGeometry(
      categories: categories,
      series: series,
      stacked: stacked,
      plotArea: plotArea,
      visibleIndices: visibleIndices,
      fixedMinY: zoom?.minY,
      fixedMaxY: zoom?.maxY,
    );
    final minY = geometry.minY;
    final maxY = geometry.maxY;

    final axes = Cartesian2DAxes(plotArea: plotArea, minX: 0, maxX: 1, minY: minY, maxY: maxY, theme: theme);
    final yTicks = Cartesian2DAxes.niceTicks(minY, maxY);

    axes.drawGridAndAxes(
      canvas,
      yTicks: yTicks,
      yFormatter: yTickFormatter,
      xAxisTitle: xAxisTitle,
      yAxisTitle: yAxisTitle,
      showGrid: showGrid,
    );

    final groupWidth = plotArea.width / visibleIndices.length;
    for (int slot = 0; slot < visibleIndices.length; slot++) {
      axes.drawXTick(canvas, plotArea.left + (slot + 0.5) * groupWidth, categories[visibleIndices[slot]]);
    }

    for (final (c, s, rect) in geometry.buildAnimatedBars(progress)) {
      final isHovered = hover != null && hover!.$1 == c && hover!.$2 == series[s].name;
      final paint = Paint()..color = isHovered ? series[s].color : series[s].color.withOpacity(0.9);
      final r = RRect.fromRectAndCorners(rect, topLeft: const Radius.circular(3), topRight: const Radius.circular(3));
      canvas.drawRRect(r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) => true;
}
