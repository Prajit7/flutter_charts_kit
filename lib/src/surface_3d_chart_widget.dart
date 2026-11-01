import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'geometry.dart';
import 'painter.dart';
import 'chart_controller.dart';
import 'legend.dart';
import 'chart2d/theme.dart';
import 'chart2d/common.dart';

/// Info passed to [Surface3DChart.tooltipBuilder] describing whichever tile
/// is currently hovered/tapped.
class Surface3DHit {
  final int colIndex;
  final int rowIndex;
  final double value;
  final String xLabel;
  final String yLabel;

  const Surface3DHit({
    required this.colIndex,
    required this.rowIndex,
    required this.value,
    required this.xLabel,
    required this.yLabel,
  });
}

/// A generic, interactive 3D surface chart.
///
/// Feed it any `data[rowIndex][colIndex]` grid — it doesn't know or care
/// whether rows are "expiries" and columns are "strikes", or rows are
/// "months" and columns are "regions". Rotate by dragging, zoom by
/// scrolling/pinching, and hover/tap any tile for a tooltip.
///
/// ```dart
/// Surface3DChart(
///   data: myGrid,               // data[row][col]
///   xLabels: ['A', 'B', 'C'],
///   yLabels: ['Jan', 'Feb'],
///   xAxisTitle: 'Category',
///   yAxisTitle: 'Month',
///   zAxisTitle: 'Revenue',
///   valueFormatter: (v) => '\$${v.toStringAsFixed(0)}',
///   gradient: [Colors.blue, Colors.orange, Colors.red],
/// )
/// ```
class Surface3DChart extends StatefulWidget {
  /// `data[rowIndex][colIndex]`. Must be a rectangular grid with at least
  /// 2 rows and 2 columns.
  final List<List<double>> data;

  /// One label per column, same length as `data[0]`.
  final List<String> xLabels;

  /// One label per row, same length as `data`.
  final List<String> yLabels;

  final String xAxisTitle;
  final String yAxisTitle;
  final String zAxisTitle;

  /// Formats a raw data value for axis ticks and tooltips, e.g.
  /// `(v) => '${(v/100000).toStringAsFixed(2)}L'`.
  final String Function(double value) valueFormatter;

  /// Color stops from low value to high value. Needs at least 2 colors.
  final List<Color> gradient;

  /// Pin the color scale to a fixed range instead of the data's own
  /// min/max, so colors stay comparable across data refreshes. Leave both
  /// null to auto-scale to whatever's in `data` right now.
  final double? fixedMin;
  final double? fixedMax;

  /// Optional vertical reference line (e.g. "current price", "today") drawn
  /// through the column closest to this index. Pass the column index
  /// directly — if your x-axis has meaningful numeric values, compute the
  /// nearest index yourself before passing it in.
  final int? referenceColIndex;
  final String? referenceLabel;

  /// Build a custom tooltip. If omitted, a sensible default card is shown.
  final Widget Function(BuildContext context, Surface3DHit hit)? tooltipBuilder;

  final double initialRotationX;
  final double initialRotationY;
  final double initialZoom;
  final double cellSpacing;

  /// Max visual height (in model units) the tallest surface point reaches.
  final double maxSurfaceHeight;

  final bool showResetButton;
  final bool enableScrollZoom;

  /// Shows a built-in color-scale legend overlaid on the chart. For custom
  /// placement (e.g. outside the chart, in your own layout) use the
  /// standalone [Surface3DLegend] widget instead and leave this false.
  final bool showLegend;

  /// Corner/edge to anchor the built-in legend to.
  final Alignment legendAlignment;

  /// Label shown above the legend bar. Defaults to [zAxisTitle] if null.
  final String? legendTitle;

  /// Orientation of the built-in legend bar.
  final Axis legendOrientation;

  /// Optional external controller (e.g. to trigger reset from your own
  /// toolbar instead of the built-in button).
  final Surface3DChartController? controller;

  /// Scale and centre the chart to fill its box at any size, pushing the
  /// camera back for large grids so perspective stays natural. With this
  /// on, [initialZoom] is relative: 16 fills the box, 32 is 2× closer.
  /// Set false for the pre-0.1 fixed scale (useful if you tuned zoom values
  /// for a specific size).
  final bool fitToSize;

  /// Filled tiles, or a see-through colored mesh.
  final SurfaceRenderMode renderMode;

  /// Draw contour lines (lines of equal value) on the floor under the surface.
  final bool showContours;

  /// How many contour levels to draw, evenly spaced between min and max.
  final int contourLevels;

  const Surface3DChart({
    super.key,
    required this.data,
    required this.xLabels,
    required this.yLabels,
    required this.xAxisTitle,
    required this.yAxisTitle,
    required this.zAxisTitle,
    required this.valueFormatter,
    required this.gradient,
    this.fixedMin,
    this.fixedMax,
    this.referenceColIndex,
    this.referenceLabel,
    this.tooltipBuilder,
    this.initialRotationX = 0.6,
    this.initialRotationY = -0.7,
    this.initialZoom = 16,
    this.cellSpacing = 45.0,
    this.maxSurfaceHeight = 130,
    this.showResetButton = true,
    this.enableScrollZoom = true,
    this.showLegend = false,
    this.legendAlignment = Alignment.bottomLeft,
    this.legendTitle,
    this.legendOrientation = Axis.vertical,
    this.controller,
    this.fitToSize = true,
    this.renderMode = SurfaceRenderMode.solid,
    this.showContours = false,
    this.contourLevels = 8,
  }) : assert(contourLevels > 0);

  @override
  State<Surface3DChart> createState() => Surface3DChartState();
}

/// Combined rotation/zoom/hover state for [Surface3DChart], held in a
/// single [ValueNotifier] so dragging, scrolling, and hovering never call
/// `setState()` — only the canvas/tooltip subtree repaints.
class Surface3DViewState {
  final double rotationX;
  final double rotationY;
  final double zoom;
  final SurfaceQuad? hoveredQuad;
  final Offset? pointerPos;

  const Surface3DViewState({
    required this.rotationX,
    required this.rotationY,
    required this.zoom,
    this.hoveredQuad,
    this.pointerPos,
  });

  Surface3DViewState copyWith({
    double? rotationX,
    double? rotationY,
    double? zoom,
    SurfaceQuad? hoveredQuad,
    bool clearHover = false,
    Offset? pointerPos,
  }) {
    return Surface3DViewState(
      rotationX: rotationX ?? this.rotationX,
      rotationY: rotationY ?? this.rotationY,
      zoom: zoom ?? this.zoom,
      hoveredQuad: clearHover ? null : (hoveredQuad ?? this.hoveredQuad),
      pointerPos: clearHover ? null : (pointerPos ?? this.pointerPos),
    );
  }
}

class Surface3DChartState extends State<Surface3DChart> {
  late final ValueNotifier<Surface3DViewState> _viewNotifier = ValueNotifier(
    Surface3DViewState(
      rotationX: widget.initialRotationX,
      rotationY: widget.initialRotationY,
      zoom: widget.initialZoom,
    ),
  );

  /// Current rotation/zoom — exposed for external inspection (e.g. tests).
  double get rotationX => _viewNotifier.value.rotationX;
  double get rotationY => _viewNotifier.value.rotationY;
  double get zoom => _viewNotifier.value.zoom;

  double _gestureBaseZoom = 0;

  @override
  void initState() {
    super.initState();
    widget.controller?.attach(resetView);
  }

  @override
  void didUpdateWidget(covariant Surface3DChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.detach();
      widget.controller?.attach(resetView);
    }
  }

  @override
  void dispose() {
    widget.controller?.detach();
    _viewNotifier.dispose();
    super.dispose();
  }

  /// Resets rotation/zoom back to the widget's initial values. Also
  /// reachable externally via a [Surface3DChartController].
  void resetView() {
    _viewNotifier.value = Surface3DViewState(
      rotationX: widget.initialRotationX,
      rotationY: widget.initialRotationY,
      zoom: widget.initialZoom,
    );
  }

  double get _zScale {
    double maxAbs = 0;
    for (final row in widget.data) {
      for (final v in row) {
        if (v.abs() > maxAbs) maxAbs = v.abs();
      }
    }
    if (maxAbs == 0) return 1;
    return widget.maxSurfaceHeight / maxAbs;
  }

  /// Same fixed-vs-dynamic logic the painter uses, so the legend always
  /// matches the colors actually drawn on the surface.
  (double, double) get _valueRange {
    if (widget.fixedMin != null && widget.fixedMax != null) {
      return (widget.fixedMin!, widget.fixedMax!);
    }
    double minV = double.infinity, maxV = -double.infinity;
    for (final row in widget.data) {
      for (final v in row) {
        if (v < minV) minV = v;
        if (v > maxV) maxV = v;
      }
    }
    return (minV, maxV);
  }

  Projector _projectorFor(Size size, Surface3DViewState view) {
    if (!widget.fitToSize) {
      return Projector(
        rotationX: view.rotationX,
        rotationY: view.rotationY,
        zoom: view.zoom,
        center: Offset(size.width / 2, size.height / 2 + 60),
      );
    }
    final rows = widget.data.length, cols = widget.data[0].length;
    final zScale = _zScale;
    final (lo, hi) = _valueRange;
    // Grid points span (index - n/2) * spacing; the axes reach ~1 cell beyond.
    final s = widget.cellSpacing;
    return fitProjector(
      area: _plotArea(size),
      rotationX: view.rotationX,
      rotationY: view.rotationY,
      zoom: view.zoom,
      xMin: (-0.6 - cols / 2) * s,
      xMax: (cols - 1 + 0.6 - cols / 2) * s,
      yMin: (-0.6 - rows / 2) * s,
      yMax: (rows - 1 + 0.6 - rows / 2) * s,
      zMin: math.min(0.0, lo * zScale),
      zMax: math.max(0.0, hi * zScale),
      fitRotationX: widget.initialRotationX,
      fitRotationY: widget.initialRotationY,
      defaultZoom: 16,
      margin: 40,
    );
  }

  /// The part of the chart the surface should fit into — the whole box,
  /// minus room for the built-in legend when it's shown.
  Rect _plotArea(Size size) {
    var area = Offset.zero & size;
    if (!widget.showLegend) return area;
    final a = widget.legendAlignment;
    if (widget.legendOrientation == Axis.vertical) {
      const legendWidth = 96.0;
      area = a.x <= 0
          ? Rect.fromLTRB(area.left + legendWidth, area.top, area.right, area.bottom)
          : Rect.fromLTRB(area.left, area.top, area.right - legendWidth, area.bottom);
    } else {
      const legendHeight = 72.0;
      area = a.y <= 0
          ? Rect.fromLTRB(area.left, area.top + legendHeight, area.right, area.bottom)
          : Rect.fromLTRB(area.left, area.top, area.right, area.bottom - legendHeight);
    }
    return area;
  }

  void _updateHover(Offset localPos, Size size) {
    final view = _viewNotifier.value;
    final geometry = SurfaceGeometry(
      data: widget.data,
      spacing: widget.cellSpacing,
      zScale: _zScale,
      projector: _projectorFor(size, view),
    );
    final quads = geometry.buildQuads();
    SurfaceQuad? found;
    for (final q in quads.reversed) {
      if (q.path.contains(localPos)) {
        found = q;
        break;
      }
    }
    _viewNotifier.value = found == null
        ? view.copyWith(clearHover: true)
        : view.copyWith(hoveredQuad: found, pointerPos: localPos);
  }

  @override
  Widget build(BuildContext context) {
    // Checked here, not in the constructor, so `const Surface3DChart(...)` compiles.
    assert(widget.gradient.length >= 2, 'gradient needs at least 2 colors');
    assert(widget.data.length >= 2 && widget.data.every((r) => r.length >= 2), 'need at least a 2×2 grid');
    final theme = ChartThemeScope.of(context);
    final (lo, hi) = _valueRange;
    return Semantics(
      container: true,
      label: describeChart('3D surface chart', widget.zAxisTitle, [
        '${widget.data.length} ${widget.yAxisTitle.isEmpty ? 'rows' : widget.yAxisTitle} by '
            '${widget.data[0].length} ${widget.xAxisTitle.isEmpty ? 'columns' : widget.xAxisTitle}',
        'values from ${widget.valueFormatter(lo)} to ${widget.valueFormatter(hi)}',
      ]),
      child: LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Listener(
          onPointerSignal: widget.enableScrollZoom
              ? (event) {
                  if (event is PointerScrollEvent) {
                    final view = _viewNotifier.value;
                    _viewNotifier.value = view.copyWith(
                      zoom: (view.zoom - event.scrollDelta.dy * 0.02).clamp(6.0, 40.0),
                    );
                  }
                }
              : null,
          child: MouseRegion(
            onHover: (event) => _updateHover(event.localPosition, size),
            onExit: (_) {
              final view = _viewNotifier.value;
              _viewNotifier.value = view.copyWith(clearHover: true);
            },
            child: GestureDetector(
              onScaleStart: (details) {
                _gestureBaseZoom = _viewNotifier.value.zoom;
              },
              onScaleUpdate: (details) {
                final view = _viewNotifier.value;
                double newRotX = view.rotationX;
                double newRotY = view.rotationY;
                // Only apply focal-point movement as rotation for a single
                // touch/pointer — during a two-finger pinch the focal point
                // still drifts a little, and we don't want that read as an
                // unintended rotation on top of the zoom.
                if (details.pointerCount <= 1) {
                  newRotY += details.focalPointDelta.dx * 0.01;
                  newRotX -= details.focalPointDelta.dy * 0.01;
                }
                final newZoom = (_gestureBaseZoom * details.scale).clamp(6.0, 40.0);
                _viewNotifier.value = view.copyWith(
                  rotationX: newRotX,
                  rotationY: newRotY,
                  zoom: newZoom,
                  clearHover: true,
                );
              },
              onTapUp: (details) => _updateHover(details.localPosition, size),
              child: ValueListenableBuilder<Surface3DViewState>(
                valueListenable: _viewNotifier,
                builder: (context, view, _) {
                  return Stack(
                    children: [
                      CustomPaint(
                        size: size,
                        painter: Surface3DPainter(
                          data: widget.data,
                          xLabels: widget.xLabels,
                          yLabels: widget.yLabels,
                          xAxisTitle: widget.xAxisTitle,
                          yAxisTitle: widget.yAxisTitle,
                          zAxisTitle: widget.zAxisTitle,
                          valueFormatter: widget.valueFormatter,
                          gradient: widget.gradient,
                          fixedMin: widget.fixedMin,
                          fixedMax: widget.fixedMax,
                          spacing: widget.cellSpacing,
                          zScale: _zScale,
                          projector: _projectorFor(size, view),
                          highlightedQuad: view.hoveredQuad,
                          theme: theme,
                          referenceColIndex: widget.referenceColIndex,
                          referenceLabel: widget.referenceLabel,
                          renderMode: widget.renderMode,
                          showContours: widget.showContours,
                          contourLevels: widget.contourLevels,
                        ),
                      ),
                      if (view.hoveredQuad != null && view.pointerPos != null)
                        _buildTooltip(view.hoveredQuad!, view.pointerPos!, size, theme),
                      if (widget.showResetButton)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: ChartResetZoomButton(theme: theme, icon: Icons.refresh, onTap: resetView),
                        ),
                      if (widget.showLegend) _buildLegend(),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    ),
    );
  }

  Widget _buildLegend() {
    final (minV, maxV) = _valueRange;
    final legend = Surface3DLegend(
      gradient: widget.gradient,
      min: minV,
      max: maxV,
      valueFormatter: widget.valueFormatter,
      title: widget.legendTitle ?? widget.zAxisTitle,
      orientation: widget.legendOrientation,
    );

    const margin = 8.0;
    final a = widget.legendAlignment;

    return Positioned(
      left: a.x <= 0 ? margin : null,
      right: a.x > 0 ? margin : null,
      top: a.y <= 0 ? margin : null,
      bottom: a.y > 0 ? margin : null,
      child: legend,
    );
  }

  Widget _buildTooltip(SurfaceQuad quad, Offset pos, Size size, ChartTheme theme) {
    final hit = Surface3DHit(
      colIndex: quad.colIndex,
      rowIndex: quad.rowIndex,
      value: quad.value,
      xLabel: widget.xLabels[quad.colIndex],
      yLabel: widget.yLabels[quad.rowIndex],
    );

    if (widget.tooltipBuilder != null) {
      return Positioned(
        left: pos.dx,
        top: pos.dy,
        child: IgnorePointer(child: widget.tooltipBuilder!(context, hit)),
      );
    }

    return positionChartTooltip(
      anchor: pos,
      areaSize: size,
      cardWidth: 190,
      child: ChartTooltipCard(
        theme: theme,
        width: 190,
        title: hit.xLabel,
        subtitle: '${widget.yAxisTitle}  ${hit.yLabel}',
        value: '${widget.zAxisTitle}  ${widget.valueFormatter(hit.value)}',
      ),
    );
  }
}
