import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'geometry.dart';
import 'painter.dart';
import 'chart_controller.dart';
import 'legend.dart';

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
    this.initialRotationX = -0.6,
    this.initialRotationY = 0.8,
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
  })  : assert(gradient.length >= 2, 'gradient needs at least 2 colors'),
        assert(data.length >= 2, 'need at least 2 rows');

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
    return Projector(
      rotationX: view.rotationX,
      rotationY: view.rotationY,
      zoom: view.zoom,
      center: Offset(size.width / 2, size.height / 2 + 60),
    );
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
    return LayoutBuilder(
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
                          referenceColIndex: widget.referenceColIndex,
                          referenceLabel: widget.referenceLabel,
                        ),
                      ),
                      if (view.hoveredQuad != null && view.pointerPos != null)
                        _buildTooltip(view.hoveredQuad!, view.pointerPos!, size),
                      if (widget.showResetButton)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: _buildResetButton(),
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

  Widget _buildResetButton() {
    return Material(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: resetView,
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(Icons.refresh, size: 20),
        ),
      ),
    );
  }

  Widget _buildTooltip(SurfaceQuad quad, Offset pos, Size size) {
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

    const cardWidth = 190.0;
    double left = pos.dx + 16;
    double top = pos.dy - 70;
    if (left + cardWidth > size.width) left = pos.dx - cardWidth - 16;
    if (top < 0) top = 8;

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          width: cardWidth,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(hit.xLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              Text('${widget.zAxisTitle}  ${widget.valueFormatter(hit.value)}',
                  style: const TextStyle(fontSize: 13)),
              Text('${widget.yAxisTitle}  ${hit.yLabel}',
                  style: const TextStyle(fontSize: 13, color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }
}
