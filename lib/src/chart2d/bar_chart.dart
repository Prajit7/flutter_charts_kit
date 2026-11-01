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

/// (original category index, series name, value, tooltip anchor)
typedef _BarHit = (int, String, double, Offset);

class _BarInteraction {
  final _BarHit? hover;
  final Rect? dragRectScreen;
  final _BarZoomWindow? zoom;

  const _BarInteraction({this.hover, this.dragRectScreen, this.zoom});

  _BarInteraction copyWith({
    _BarHit? hover,
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
///     CategorySeries(name: 'Product B', color: Colors.orange, values: [7, 11, 13]),
///   ],
///   stacked: false,
///   showValueLabels: true,
///   onBarTap: (series, category, value) => print('$series/$category: $value'),
/// )
/// ```
///
/// Drag horizontally to zoom into a range of categories (y auto-rescales
/// to fit); with [zoomMode] set to [ChartZoomMode.xy], the vertical extent
/// of the drag also zooms the y-axis. A reset button appears while zoomed.
/// Set [horizontal] for a bar chart with categories down the left side
/// (drag-to-zoom is not available in that layout).
class BarChart2D extends StatefulWidget {
  final List<String> categories;
  final List<CategorySeries> series;
  final bool stacked;

  /// Lay bars out horizontally: categories down the left, values along the
  /// bottom. Good for long category names or many categories.
  final bool horizontal;

  final String? title;
  final String? subtitle;

  /// Title for the category axis (bottom, or left when [horizontal]).
  final String? xAxisTitle;

  /// Title for the value axis (left, or bottom when [horizontal]).
  final String? yAxisTitle;
  final String emptyStateMessage;
  final String Function(double value) yTickFormatter;
  final bool showGrid;
  final bool showLegend;
  final ChartLegendPosition legendPosition;

  /// Print each bar's value at its end (or inside each segment when
  /// [stacked], where it fits).
  final bool showValueLabels;

  /// Formats [showValueLabels] text. Defaults to [yTickFormatter].
  final String Function(double value)? valueLabelFormatter;

  /// Value-axis marker lines (targets, averages). Lines on the x-axis are
  /// ignored — categories have no numeric position.
  final List<ChartReferenceLine> referenceLines;

  /// Value-axis shaded ranges, drawn behind the bars.
  final List<ChartReferenceBand> referenceBands;

  final bool enableAnimation;
  final Duration animationDuration;

  /// What happens when [series] or [categories] change after the first
  /// build. [ChartUpdateAnimation.morph] grows/shrinks each bar to its new
  /// value when the categories are unchanged.
  final ChartUpdateAnimation updateAnimation;

  /// Drag-to-zoom mode. [ChartZoomMode.x] (default) zooms the category
  /// range and auto-rescales y; [ChartZoomMode.xy] also zooms y to the
  /// dragged rectangle; [ChartZoomMode.none] disables zoom.
  final ChartZoomMode zoomMode;

  /// Minimum drag distance (px) before a drag counts as a zoom selection.
  final double zoomDragThreshold;

  /// Replaces the default tooltip card.
  final ChartBarTooltipBuilder? tooltipBuilder;

  /// Reset zoom or export an image from outside the chart.
  final ChartController? controller;

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
    this.horizontal = false,
    this.title,
    this.subtitle,
    this.xAxisTitle,
    this.yAxisTitle,
    this.emptyStateMessage = 'No data to display',
    this.yTickFormatter = Cartesian2DAxes.formatNumber,
    this.showGrid = true,
    this.showLegend = true,
    this.legendPosition = ChartLegendPosition.bottom,
    this.showValueLabels = false,
    this.valueLabelFormatter,
    this.referenceLines = const [],
    this.referenceBands = const [],
    this.enableAnimation = true,
    this.animationDuration = const Duration(milliseconds: 550),
    this.updateAnimation = ChartUpdateAnimation.morph,
    this.zoomMode = ChartZoomMode.x,
    this.zoomDragThreshold = 12,
    this.tooltipBuilder,
    this.controller,
    this.onBarHover,
    this.onBarTap,
  });

  @override
  State<BarChart2D> createState() => _BarChart2DState();
}

/// Left padding for a horizontal bar chart: wide enough for the longest
/// category label, but never more than a third of the chart.
double _categoryLabelPad(List<String> categories, ChartTheme theme, double width) {
  double widest = 0;
  for (final c in categories) {
    final tp = TextPainter(
      text: TextSpan(
          text: c, style: TextStyle(fontSize: theme.tickFontSize, fontWeight: FontWeight.w600, fontFamily: theme.fontFamily)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    widest = math.max(widest, tp.width);
  }
  return (widest + 14).clamp(48.0, math.max(48.0, width / 3));
}

Rect _barPlotArea(Size size, bool horizontal, List<String> categories, ChartTheme theme) => horizontal
    ? Cartesian2DAxes.computePlotArea(size, leftPad: _categoryLabelPad(categories, theme, size.width))
    : Cartesian2DAxes.computePlotArea(size);

class _BarChart2DState extends State<BarChart2D>
    with TickerProviderStateMixin, ChartControllerMixin<BarChart2D> {
  final ValueNotifier<Set<String>> _hiddenNotifier = ValueNotifier(const {});
  final ValueNotifier<_BarInteraction> _interactionNotifier = ValueNotifier(const _BarInteraction());
  late final AnimationController _controller;

  /// Drives [ChartUpdateAnimation.morph] from [_morphFrom] to the new values.
  late final AnimationController _morph;
  List<CategorySeries>? _morphFrom;
  List<CategorySeries> _lastVisible = const [];

  final _dragZoom = ChartDragZoom();

  @override
  ChartController? controllerOf(BarChart2D widget) => widget.controller;

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
  void didUpdateWidget(covariant BarChart2D oldWidget) {
    super.didUpdateWidget(oldWidget);
    final categoriesChanged = !listEquals(oldWidget.categories, widget.categories) || oldWidget.horizontal != widget.horizontal;
    if (!categoriesChanged && listEquals(oldWidget.series, widget.series)) return;
    // A different set of categories invalidates any zoom window (it holds
    // category indices), and there's nothing sensible to morph from.
    final mode = categoriesChanged ? ChartUpdateAnimation.replay : widget.updateAnimation;
    switch (mode) {
      case ChartUpdateAnimation.replay:
        if (widget.enableAnimation) _controller.forward(from: 0);
        _interactionNotifier.value = const _BarInteraction();
      case ChartUpdateAnimation.morph:
        if (widget.enableAnimation) {
          _morphFrom = _lastVisible;
          _morph.forward(from: 0);
        }
        _interactionNotifier.value = _interactionNotifier.value.copyWith(clearHover: true);
      case ChartUpdateAnimation.none:
        _interactionNotifier.value = _interactionNotifier.value.copyWith(clearHover: true);
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

  _BarGeometry _geometryFor(Size size, List<CategorySeries> visibleSeries, ChartTheme theme, _BarZoomWindow? zoom) {
    return _BarGeometry(
      categories: widget.categories,
      series: visibleSeries,
      stacked: widget.stacked,
      horizontal: widget.horizontal,
      plotArea: _barPlotArea(size, widget.horizontal, widget.categories, theme),
      visibleIndices: _currentVisibleIndices(zoom),
      fixedMinY: zoom?.minY,
      fixedMaxY: zoom?.maxY,
    );
  }

  /// The geometry to paint: during a morph, values and the axis range part
  /// way between the previous data and the new.
  _BarGeometry _morphingGeometry(Size size, List<CategorySeries> visible, ChartTheme theme, _BarZoomWindow? zoom) {
    final from = _morphFrom;
    if (from == null || !_morph.isAnimating) return _geometryFor(size, visible, theme, zoom);
    final t = Curves.easeInOutCubic.transform(_morph.value);
    double lerp(double a, double b) => a + (b - a) * t;
    final byName = {for (final s in from) s.name: s};
    final values = [
      for (final s in visible)
        CategorySeries(name: s.name, color: s.color, values: [
          for (int i = 0; i < s.values.length; i++)
            // New series/categories grow from zero.
            lerp(byName[s.name] != null && i < byName[s.name]!.values.length ? byName[s.name]!.values[i] : 0, s.values[i]),
        ]),
    ];
    final a = _geometryFor(size, from, theme, zoom), b = _geometryFor(size, visible, theme, zoom);
    return _BarGeometry(
      categories: widget.categories,
      series: values,
      stacked: widget.stacked,
      horizontal: widget.horizontal,
      plotArea: b.plotArea,
      visibleIndices: b.visibleIndices,
      // Glide the value axis rather than snapping between nice ranges.
      fixedMinY: lerp(a.minY, b.minY),
      fixedMaxY: lerp(a.maxY, b.maxY),
    );
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

    final zoomEnabled = widget.zoomMode != ChartZoomMode.none && !widget.horizontal;
    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart(widget.horizontal ? 'Horizontal bar chart' : 'Bar chart', widget.title, ['${widget.categories.length} categories', for (final s in widget.series) summarizeValues(s.name, s.values, widget.yTickFormatter)]),
      title: widget.title,
      subtitle: widget.subtitle,
      legendPosition: widget.legendPosition,
      legendBuilder: widget.showLegend ? _buildLegend : null,
      plot: ValueListenableBuilder<Set<String>>(
        valueListenable: _hiddenNotifier,
        builder: (context, hidden, _) {
          final visibleSeries = widget.series.where((s) => !hidden.contains(s.name)).toList();
          _lastVisible = visibleSeries;
          return LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              return GestureDetector(
                onTapUp: (d) => _handleTap(d.localPosition, size, visibleSeries, theme),
                onPanStart: zoomEnabled
                    ? (d) => _dragZoom.start(d.localPosition, _barPlotArea(size, false, widget.categories, theme))
                    : null,
                onPanUpdate: zoomEnabled ? (d) => _handlePanUpdate(d.localPosition, size, theme) : null,
                onPanEnd: zoomEnabled ? (_) => _handlePanEnd(size, visibleSeries, theme) : null,
                child: MouseRegion(
                  onHover: (e) => _applyHover(_hitTest(e.localPosition, size, visibleSeries, theme)),
                  onExit: (_) {
                    _interactionNotifier.value = _interactionNotifier.value.copyWith(clearHover: true);
                    widget.onBarHover?.call(null, null, null);
                  },
                  child: ValueListenableBuilder<_BarInteraction>(
                    valueListenable: _interactionNotifier,
                    builder: (context, interaction, __) {
                      return Stack(
                        children: [
                          AnimatedBuilder(
                            animation: Listenable.merge([_controller, _morph]),
                            builder: (context, _) => CustomPaint(
                              size: size,
                              painter: _BarChartPainter(
                                geometry: _morphingGeometry(size, visibleSeries, theme, interaction.zoom),
                                theme: theme,
                                xAxisTitle: widget.xAxisTitle,
                                yAxisTitle: widget.yAxisTitle,
                                yTickFormatter: widget.yTickFormatter,
                                valueLabelFormatter: widget.showValueLabels
                                    ? (widget.valueLabelFormatter ?? widget.yTickFormatter)
                                    : null,
                                showGrid: widget.showGrid,
                                referenceLines: widget.referenceLines,
                                referenceBands: widget.referenceBands,
                                hover: interaction.hover,
                                progress: _controller.value,
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

  // ---------------- zoom drag handling (vertical layout only) ----------------

  void _handlePanUpdate(Offset pos, Size size, ChartTheme theme) {
    final rect = _dragZoom.update(pos, _barPlotArea(size, false, widget.categories, theme), widget.zoomMode);
    if (rect == null) return;
    _interactionNotifier.value = _interactionNotifier.value.copyWith(dragRectScreen: rect, clearHover: true);
  }

  void _handlePanEnd(Size size, List<CategorySeries> visibleSeries, ChartTheme theme) {
    final current = _interactionNotifier.value;
    final rect = current.dragRectScreen;
    _dragZoom.end();
    if (rect == null) return;

    if (ChartDragZoom.isTooSmall(rect, widget.zoomMode, widget.zoomDragThreshold)) {
      _interactionNotifier.value = current.copyWith(clearDragRect: true);
      return;
    }

    final geometry = _geometryFor(size, visibleSeries, theme, current.zoom);
    final plotArea = geometry.plotArea;
    final visibleIndices = geometry.visibleIndices;

    // Map screen x back to a "slot" position within the currently visible
    // categories, then to original category indices. startSlot must stay a
    // valid index (0..length-1); endSlotExclusive is a count (1..length) so
    // endSlotExclusive-1 is also always a valid index.
    final slotWidth = plotArea.width / visibleIndices.length;
    final startSlot = ((rect.left - plotArea.left) / slotWidth).floor().clamp(0, visibleIndices.length - 1);
    final endSlotExclusive = ((rect.right - plotArea.left) / slotWidth).ceil().clamp(1, visibleIndices.length);

    if (endSlotExclusive - startSlot < 1) {
      _interactionNotifier.value = current.copyWith(clearDragRect: true);
      return;
    }

    double? newMinY;
    double? newMaxY;
    if (widget.zoomMode == ChartZoomMode.xy) {
      newMaxY = geometry.valueAt(rect.top);
      newMinY = geometry.valueAt(rect.bottom);
    }

    _interactionNotifier.value = current.copyWith(
      zoom: _BarZoomWindow(
        startIndex: visibleIndices[startSlot],
        endIndexExclusive: visibleIndices[endSlotExclusive - 1] + 1,
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

  void _handleTap(Offset pos, Size size, List<CategorySeries> visibleSeries, ChartTheme theme) {
    final hit = _hitTest(pos, size, visibleSeries, theme);
    _applyHover(hit);
    if (hit != null) widget.onBarTap?.call(hit.$2, widget.categories[hit.$1], hit.$3);
  }

  void _applyHover(_BarHit? hit) {
    final current = _interactionNotifier.value;
    final changed = hit?.$1 != current.hover?.$1 || hit?.$2 != current.hover?.$2;
    _interactionNotifier.value = hit == null ? current.copyWith(clearHover: true) : current.copyWith(hover: hit);
    if (changed) widget.onBarHover?.call(hit?.$2, hit == null ? null : widget.categories[hit.$1], hit?.$3);
  }

  _BarHit? _hitTest(Offset pos, Size size, List<CategorySeries> visibleSeries, ChartTheme theme) {
    if (visibleSeries.isEmpty || widget.categories.isEmpty) return null;
    return _geometryFor(size, visibleSeries, theme, _interactionNotifier.value.zoom).hitTest(pos);
  }

  Widget _buildTooltip(_BarHit hover, Size size, ChartTheme theme) {
    final (catIndex, seriesName, value, pos) = hover;
    final custom = widget.tooltipBuilder;
    return positionChartTooltip(
      anchor: pos,
      areaSize: size,
      child: custom != null
          ? custom(context, seriesName, widget.categories[catIndex], value)
          : ChartTooltipCard(
              theme: theme,
              width: 150,
              title: seriesName,
              subtitle: widget.categories[catIndex],
              value: widget.yTickFormatter(value),
            ),
    );
  }
}

/// Shared bar-position math between the painter and hit-testing so they
/// always agree on where each bar actually is. [visibleIndices] are the
/// *original* category indices to render, stretched to fill [plotArea] —
/// this is what makes zooming into a category range work.
///
/// Bars are laid out in a vertical "virtual" space (categories along x,
/// values up y) and, when [horizontal], rotated into place — so stacking,
/// grouping and negatives work identically in both layouts.
class _BarGeometry {
  final List<String> categories;
  final List<CategorySeries> series;
  final bool stacked;
  final bool horizontal;
  final Rect plotArea;
  final List<int> visibleIndices;
  final double? fixedMinY;
  final double? fixedMaxY;

  _BarGeometry({
    required this.categories,
    required this.series,
    required this.stacked,
    required this.horizontal,
    required this.plotArea,
    required this.visibleIndices,
    this.fixedMinY,
    this.fixedMaxY,
  });

  /// The plot in virtual (vertical) space: categories run along its width,
  /// values up its height.
  Rect get _virtual => horizontal ? Rect.fromLTWH(0, 0, plotArea.height, plotArea.width) : plotArea;

  Rect _toScreen(Rect v) => horizontal
      ? Rect.fromLTRB(plotArea.left + plotArea.width - v.bottom, plotArea.top + v.left,
          plotArea.left + plotArea.width - v.top, plotArea.top + v.right)
      : v;

  /// The y-range to plot. An explicit (zoomed) range is used as-is; the
  /// auto range always includes zero and is rounded out to nice tick values.
  late final (double, double) _yRange = fixedMinY != null && fixedMaxY != null
      ? (fixedMinY!, fixedMaxY!)
      : Cartesian2DAxes.niceExtent(fixedMinY ?? _dataMinY, fixedMaxY ?? _dataMaxY);

  double get minY => _yRange.$1;
  double get maxY => _yRange.$2;

  double get _dataMinY {
    double m = 0;
    if (stacked) {
      // negative values stack downward, so the floor is the most negative sum
      for (final idx in visibleIndices) {
        double sum = 0;
        for (final s in series) {
          if (idx < s.values.length && s.values[idx] < 0) sum += s.values[idx];
        }
        if (sum < m) m = sum;
      }
    } else {
      for (final s in series) {
        for (final idx in visibleIndices) {
          if (idx < s.values.length && s.values[idx] < m) m = s.values[idx];
        }
      }
    }
    return m;
  }

  double get _dataMaxY {
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

  double get _yScale => _virtual.height / (maxY - minY == 0 ? 1 : maxY - minY);

  /// Virtual-space y of the zero baseline.
  double get _yZero => _virtual.bottom + minY * _yScale;

  double _y(double value) => _yZero - value * _yScale;

  /// Inverse of the value mapping, for a screen y (vertical layout only).
  double valueAt(double screenY) => (_yZero - screenY) / _yScale;

  /// Cross-axis center of each visible category's slot, in screen space
  /// (x for vertical bars, y for horizontal ones).
  List<double> get slotCenters {
    final v = _virtual;
    final w = v.width / visibleIndices.length;
    return [
      for (int i = 0; i < visibleIndices.length; i++)
        horizontal ? plotArea.top + (i + 0.5) * w : v.left + (i + 0.5) * w,
    ];
  }

  /// Returns (originalCategoryIndex, seriesIndex, value, Rect) for every bar,
  /// in screen space, so painting and hit-testing share identical geometry.
  List<(int, int, double, Rect)> buildBars({double progress = 1}) {
    final bars = <(int, int, double, Rect)>[];
    final catCount = visibleIndices.length;
    if (catCount == 0 || series.isEmpty) return bars;

    final v = _virtual;
    final groupWidth = v.width / catCount;
    final yZero = _yZero;
    // Entrance animation: every edge grows out from the zero baseline.
    double grow(double y) => yZero + (y - yZero) * progress;
    Rect bar(double left, double right, double a, double b) =>
        _toScreen(Rect.fromLTRB(left, math.min(grow(a), grow(b)), right, math.max(grow(a), grow(b))));

    for (int slot = 0; slot < catCount; slot++) {
      final c = visibleIndices[slot];
      final groupLeft = v.left + slot * groupWidth;
      if (stacked) {
        double posStackTop = 0;
        double negStackTop = 0;
        final barWidth = groupWidth * 0.6;
        final barLeft = groupLeft + (groupWidth - barWidth) / 2;
        for (int s = 0; s < series.length; s++) {
          final value = c < series[s].values.length ? series[s].values[c] : 0.0;
          final from = value >= 0 ? posStackTop : negStackTop;
          bars.add((c, s, value, bar(barLeft, barLeft + barWidth, _y(from), _y(from + value))));
          value >= 0 ? posStackTop += value : negStackTop += value;
        }
      } else {
        final barWidth = (groupWidth * 0.7) / series.length;
        final groupInnerLeft = groupLeft + (groupWidth * 0.15);
        for (int s = 0; s < series.length; s++) {
          final value = c < series[s].values.length ? series[s].values[c] : 0.0;
          final left = groupInnerLeft + s * barWidth;
          bars.add((c, s, value, bar(left, left + barWidth, yZero, _y(value))));
        }
      }
    }
    return bars;
  }

  _BarHit? hitTest(Offset pos) {
    if (!plotArea.contains(pos)) return null; // bars are clipped to the plot
    for (final (c, s, value, rect) in buildBars()) {
      if (rect.inflate(1).contains(pos)) {
        final anchor = horizontal ? Offset(rect.right, rect.center.dy) : Offset(rect.center.dx, rect.top);
        return (c, series[s].name, value, anchor);
      }
    }
    return null;
  }
}

class _BarChartPainter extends CustomPainter {
  final _BarGeometry geometry;
  final ChartTheme theme;
  final String? xAxisTitle;
  final String? yAxisTitle;
  final String Function(double) yTickFormatter;
  final String Function(double)? valueLabelFormatter;
  final bool showGrid;
  final List<ChartReferenceLine> referenceLines;
  final List<ChartReferenceBand> referenceBands;
  final _BarHit? hover;

  /// 0 (bars flat) to 1 (full height) — drives the entrance animation.
  final double progress;

  _BarChartPainter({
    required this.geometry,
    required this.theme,
    required this.xAxisTitle,
    required this.yAxisTitle,
    required this.yTickFormatter,
    required this.valueLabelFormatter,
    required this.showGrid,
    required this.referenceLines,
    required this.referenceBands,
    required this.hover,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final series = geometry.series;
    if (geometry.categories.isEmpty || series.isEmpty) return;

    final plotArea = geometry.plotArea;
    final valueTicks = Cartesian2DAxes.niceTicks(geometry.minY, geometry.maxY);
    final names = [for (final i in geometry.visibleIndices) geometry.categories[i]];

    final Cartesian2DAxes axes;
    final List<ChartReferenceLine> lines;
    final List<ChartReferenceBand> bands;
    if (geometry.horizontal) {
      // Values run along x here, so value-axis references become x ones.
      axes = Cartesian2DAxes(plotArea: plotArea, minX: geometry.minY, maxX: geometry.maxY, minY: 0, maxY: 1, theme: theme);
      _drawHorizontalAxes(canvas, axes, valueTicks, names);
      lines = [
        for (final l in referenceLines.where((l) => l.axis == ChartReferenceAxis.y))
          ChartReferenceLine.x(l.value, label: l.label, color: l.color, strokeWidth: l.strokeWidth, dashed: l.dashed),
      ];
      bands = [
        for (final b in referenceBands.where((b) => b.axis == ChartReferenceAxis.y))
          ChartReferenceBand.x(b.from, b.to, label: b.label, color: b.color),
      ];
    } else {
      axes = Cartesian2DAxes(plotArea: plotArea, minX: 0, maxX: 1, minY: geometry.minY, maxY: geometry.maxY, theme: theme);
      axes.drawGridAndAxes(
        canvas,
        yTicks: valueTicks,
        yFormatter: yTickFormatter,
        xAxisTitle: xAxisTitle,
        yAxisTitle: yAxisTitle,
        showGrid: showGrid,
      );
      final centers = geometry.slotCenters;
      axes.drawXTicks(canvas, [for (int i = 0; i < names.length; i++) (centers[i], names[i])]);
      lines = referenceLines.where((l) => l.axis == ChartReferenceAxis.y).toList();
      bands = referenceBands.where((b) => b.axis == ChartReferenceAxis.y).toList();
    }

    final references = ReferencePainter(axes);
    references.paintBands(canvas, bands);

    // An xy zoom can cut bars off mid-height; keep them inside the axes.
    canvas.save();
    canvas.clipRect(plotArea);
    final bars = geometry.buildBars(progress: progress);
    for (final (c, s, _, rect) in bars) {
      final isHovered = hover != null && hover!.$1 == c && hover!.$2 == series[s].name;
      final paint = Paint()..color = isHovered ? series[s].color : series[s].color.withValues(alpha: 0.9);
      const r = Radius.circular(3);
      final rounded = geometry.horizontal
          ? RRect.fromRectAndCorners(rect, topRight: r, bottomRight: r)
          : RRect.fromRectAndCorners(rect, topLeft: r, topRight: r);
      canvas.drawRRect(rounded, paint);
    }
    canvas.restore();

    if (valueLabelFormatter != null && progress >= 1) _drawValueLabels(canvas, axes, bars);

    references.paintLines(canvas, lines);
  }

  void _drawHorizontalAxes(Canvas canvas, Cartesian2DAxes axes, List<double> valueTicks, List<String> names) {
    final plot = geometry.plotArea;
    final gridPaint = Paint()
      ..color = theme.gridColor
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = theme.axisColor
      ..strokeWidth = 1.2;
    if (showGrid) {
      for (final v in valueTicks) {
        final x = axes.toScreenX(v);
        canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
      }
    }
    canvas.drawLine(plot.bottomLeft, plot.topLeft, axisPaint);
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, axisPaint);
    axes.drawXTicks(canvas, [for (final v in valueTicks) (axes.toScreenX(v), yTickFormatter(v))]);

    // Category labels, right-aligned against the axis and ellipsized to fit.
    final centers = geometry.slotCenters;
    final slotHeight = names.length > 1 ? (centers[1] - centers[0]).abs() : plot.height;
    final maxWidth = math.max(0.0, plot.left - 10);
    int stride = 1;
    for (int i = 0; i < names.length; i += stride) {
      final tp = TextPainter(
        text: TextSpan(
          text: names[i],
          style: TextStyle(
              color: theme.tickTextColor,
              fontSize: theme.tickFontSize,
              fontWeight: FontWeight.w600,
              fontFamily: theme.fontFamily),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: maxWidth);
      // When slots are thinner than a line of text, label every n-th one.
      stride = math.max(1, (tp.height / slotHeight).ceil());
      tp.paint(canvas, Offset(plot.left - 6 - tp.width, centers[i] - tp.height / 2));
    }

    if (yAxisTitle != null) {
      final size = axes.measureLabel(yAxisTitle!, fontSize: 12);
      axes.drawLabel(canvas, yAxisTitle!, Offset(plot.center.dx - size.width / 2, plot.bottom + 26),
          color: theme.axisColor, fontSize: 12);
    }
    if (xAxisTitle != null) {
      final size = axes.measureLabel(xAxisTitle!, fontSize: 12);
      canvas.save();
      canvas.translate(2, plot.center.dy + size.width / 2);
      canvas.rotate(-math.pi / 2);
      axes.drawLabel(canvas, xAxisTitle!, Offset.zero, color: theme.axisColor, fontSize: 12);
      canvas.restore();
    }
  }

  /// Non-stacked: value just past each bar's end. Stacked: centered inside
  /// each segment, only where it fits.
  void _drawValueLabels(Canvas canvas, Cartesian2DAxes axes, List<(int, int, double, Rect)> bars) {
    final fmt = valueLabelFormatter!;
    // Labels may use the padding above the plot (for the tallest bar).
    final plot = geometry.plotArea;
    final bounds = Rect.fromLTRB(plot.left - 2, plot.top - 12, plot.right + 12, plot.bottom + 2);
    for (final (_, _, value, rect) in bars) {
      final text = fmt(value);
      final size = axes.measureLabel(text);
      if (geometry.stacked) {
        if (rect.width < size.width + 4 || rect.height < size.height + 2) continue;
        axes.drawLabel(canvas, text, rect.center - Offset(size.width / 2, size.height / 2), color: Colors.white);
        continue;
      }
      final Offset pos;
      if (geometry.horizontal) {
        pos = value >= 0
            ? Offset(rect.right + 4, rect.center.dy - size.height / 2)
            : Offset(rect.left - 4 - size.width, rect.center.dy - size.height / 2);
      } else {
        pos = value >= 0
            ? Offset(rect.center.dx - size.width / 2, rect.top - size.height - 2)
            : Offset(rect.center.dx - size.width / 2, rect.bottom + 2);
      }
      // Skip labels that would land outside the plot (e.g. clipped by zoom).
      if (!bounds.contains(pos) || !bounds.contains(pos + Offset(size.width, size.height))) continue;
      axes.drawLabel(canvas, text, pos);
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) => true;
}
