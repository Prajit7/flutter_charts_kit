import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'models.dart';
import 'legend.dart';
import 'theme.dart';
import 'chart_chrome.dart';
import 'common.dart';
import 'cartesian_axes.dart';
import 'controller.dart';

/// Pinch/scroll zoom + pan state for [PieChart2D]. A pie has no axes, so
/// there's no "range" to drag-select the way [LineChart2D]/[ScatterChart2D]/
/// [BarChart2D] do — instead this behaves like zooming a photo: pinch or
/// scroll to scale, drag to pan while zoomed, reset button to snap back.
class _PieViewState {
  final double scale;
  final Offset translation;

  const _PieViewState({this.scale = 1, this.translation = Offset.zero});

  bool get isDefault => scale == 1 && translation == Offset.zero;
}

/// A pie chart — or a donut chart if [innerRadiusRatio] > 0.
///
/// ```dart
/// PieChart2D(
///   title: 'Browser Share',
///   slices: [
///     PieSlice(label: 'Chrome', value: 64, color: Colors.blue),
///     PieSlice(label: 'Safari', value: 19, color: Colors.orange),
///     PieSlice(label: 'Other', value: 17, color: Colors.grey),
///   ],
///   innerRadiusRatio: 0.6, // set 0 for a solid pie
///   onSliceTap: (slice) => print(slice?.label),
/// )
/// ```
///
/// Pinch (or scroll on desktop) to zoom in on the pie; drag to pan while
/// zoomed. A reset button appears while zoomed and restores the original
/// view.
class PieChart2D extends StatefulWidget {
  final List<PieSlice> slices;

  /// 0 = solid pie. 0.5–0.7 is a typical donut hole.
  final double innerRadiusRatio;

  final String? title;
  final String? subtitle;
  final String emptyStateMessage;
  final bool showLegend;
  final ChartLegendPosition legendPosition;
  final bool showPercentageLabels;
  final String Function(double value)? valueFormatter;

  final bool enableAnimation;
  final Duration animationDuration;

  /// Enables pinch/scroll zoom + pan. Set false to disable entirely.
  final bool enableZoom;
  final double minZoomScale;
  final double maxZoomScale;

  /// Replaces the default tooltip card shown in the middle of the chart.
  final ChartSliceTooltipBuilder? tooltipBuilder;

  /// Reset pan/zoom or export an image from outside the chart.
  final ChartController? controller;

  /// Fired continuously as the pointer moves over/off a slice (mouse hover
  /// and touch). Called with `null` when nothing is hovered.
  final ChartSliceCallback? onSliceHover;

  /// Fired once per tap/click on a slice. Not called on taps that miss.
  final ChartSliceCallback? onSliceTap;

  const PieChart2D({
    super.key,
    required this.slices,
    this.innerRadiusRatio = 0,
    this.title,
    this.subtitle,
    this.emptyStateMessage = 'No data to display',
    this.showLegend = true,
    this.legendPosition = ChartLegendPosition.bottom,
    this.showPercentageLabels = true,
    this.valueFormatter,
    this.enableAnimation = true,
    this.animationDuration = const Duration(milliseconds: 600),
    this.enableZoom = true,
    this.minZoomScale = 1.0,
    this.maxZoomScale = 4.0,
    this.tooltipBuilder,
    this.controller,
    this.onSliceHover,
    this.onSliceTap,
  });

  @override
  State<PieChart2D> createState() => _PieChart2DState();
}

class _PieChart2DState extends State<PieChart2D>
    with SingleTickerProviderStateMixin, ChartControllerMixin<PieChart2D> {
  final ValueNotifier<Set<String>> _hiddenNotifier = ValueNotifier(const {});
  final ValueNotifier<String?> _hoveredLabelNotifier = ValueNotifier(null);
  final ValueNotifier<_PieViewState> _viewNotifier = ValueNotifier(const _PieViewState());
  late final AnimationController _controller;

  double _gestureBaseScale = 1;
  Offset _gestureBaseTranslation = Offset.zero;

  @override
  ChartController? controllerOf(PieChart2D widget) => widget.controller;

  @override
  void resetZoom() => _viewNotifier.value = const _PieViewState();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.animationDuration);
    if (widget.enableAnimation) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
    _viewNotifier.addListener(() => reportZoomed(!_viewNotifier.value.isDefault));
  }

  @override
  void didUpdateWidget(covariant PieChart2D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.slices, widget.slices)) {
      if (widget.enableAnimation) _controller.forward(from: 0);
      _viewNotifier.value = const _PieViewState();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _hiddenNotifier.dispose();
    _hoveredLabelNotifier.dispose();
    _viewNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);

    if (widget.slices.isEmpty) {
      return ChartFrame(
        boundaryKey: chartBoundaryKey,
        title: widget.title,
        subtitle: widget.subtitle,
        plot: ChartEmptyState(message: widget.emptyStateMessage),
      );
    }

    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart(widget.innerRadiusRatio > 0 ? 'Donut chart' : 'Pie chart', widget.title, _sliceSummaries()),
      title: widget.title,
      subtitle: widget.subtitle,
      legendPosition: widget.legendPosition,
      legendBuilder: widget.showLegend ? _buildLegend : null,
      plot: ValueListenableBuilder<Set<String>>(
        valueListenable: _hiddenNotifier,
        builder: (context, hidden, _) {
          // Zero/negative values have no meaningful share of a pie.
          final visibleSlices = widget.slices.where((s) => !hidden.contains(s.label) && s.value > 0).toList();
          return LayoutBuilder(
            builder: (context, constraints) {
              // Measure the plot area itself: the legend can wrap to several
              // rows, so its size is not a fixed constant.
              final size = constraints.biggest;
              return Listener(
                onPointerSignal: widget.enableZoom
                    ? (event) {
                        if (event is PointerScrollEvent) {
                          final view = _viewNotifier.value;
                          final newScale = (view.scale - event.scrollDelta.dy * 0.0025)
                              .clamp(widget.minZoomScale, widget.maxZoomScale);
                          _viewNotifier.value = _PieViewState(
                            scale: newScale,
                            translation: newScale <= widget.minZoomScale ? Offset.zero : view.translation,
                          );
                        }
                      }
                    : null,
                child: GestureDetector(
                  onTapUp: (d) => _handleTap(d.localPosition, size, visibleSlices),
                  onScaleStart: widget.enableZoom
                      ? (d) {
                          final view = _viewNotifier.value;
                          _gestureBaseScale = view.scale;
                          _gestureBaseTranslation = view.translation;
                        }
                      : null,
                  onScaleUpdate: widget.enableZoom ? (d) => _handleScaleUpdate(d, size) : null,
                  child: MouseRegion(
                    onHover: (e) => _updateHover(e.localPosition, size, visibleSlices),
                    onExit: (_) {
                      _hoveredLabelNotifier.value = null;
                      widget.onSliceHover?.call(null);
                    },
                    child: ValueListenableBuilder<_PieViewState>(
                      valueListenable: _viewNotifier,
                      builder: (context, view, _) {
                        return ValueListenableBuilder<String?>(
                          valueListenable: _hoveredLabelNotifier,
                          builder: (context, hoveredLabel, __) {
                            return ClipRect(
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Transform.translate(
                                    offset: view.translation,
                                    child: Transform.scale(
                                      scale: view.scale,
                                      child: AnimatedBuilder(
                                        animation: _controller,
                                        builder: (context, _) => CustomPaint(
                                          size: size,
                                          painter: _PieChartPainter(
                                            slices: visibleSlices,
                                            innerRadiusRatio: widget.innerRadiusRatio,
                                            showPercentageLabels: widget.showPercentageLabels,
                                            hoveredLabel: hoveredLabel,
                                            progress: _controller.value,
                                            fontFamily: theme.fontFamily,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (hoveredLabel != null) _buildCenterTooltip(theme, hoveredLabel, visibleSlices),
                                  if (!view.isDefault)
                                    Positioned(right: 8, top: 8, child: ChartResetZoomButton(theme: theme, onTap: resetZoom)),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  List<String> _sliceSummaries() {
    final positive = widget.slices.where((s) => s.value > 0);
    final total = positive.fold<double>(0, (sum, s) => sum + s.value);
    return [
      for (final s in positive)
        '${s.label}: ${widget.valueFormatter?.call(s.value) ?? Cartesian2DAxes.formatNumber(s.value)}'
            ' (${total == 0 ? 0 : (s.value / total * 100).toStringAsFixed(1)}%)',
    ];
  }

  Widget _buildLegend(Axis direction) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: _hiddenNotifier,
      builder: (context, hidden, _) => Chart2DLegend(
        direction: direction,
        entries: widget.slices.map((s) => LegendEntry(label: s.label, color: s.color)).toList(),
        hidden: hidden,
        onToggle: (label) {
          final next = {...hidden};
          next.contains(label) ? next.remove(label) : next.add(label);
          _hiddenNotifier.value = next;
          _hoveredLabelNotifier.value = null;
        },
      ),
    );
  }

  // ---------------- zoom/pan handling ----------------

  void _handleScaleUpdate(ScaleUpdateDetails details, Size size) {
    final newScale = (_gestureBaseScale * details.scale).clamp(widget.minZoomScale, widget.maxZoomScale);

    Offset newTranslation;
    if (newScale <= widget.minZoomScale) {
      newTranslation = Offset.zero;
    } else {
      // Pan only makes sense once zoomed in; clamp so content can't drift
      // arbitrarily far off-screen.
      final proposed = _gestureBaseTranslation + details.focalPointDelta;
      final maxPan = (newScale - 1) * math.min(size.width, size.height) / 2;
      newTranslation = Offset(
        proposed.dx.clamp(-maxPan, maxPan),
        proposed.dy.clamp(-maxPan, maxPan),
      );
    }

    _viewNotifier.value = _PieViewState(scale: newScale, translation: newTranslation);
  }

  /// Converts a raw pointer position (in the untransformed widget's local
  /// coordinate space) into the CustomPaint's own draw space, undoing the
  /// current pan/zoom transform — so hit-testing lines up with what's
  /// actually drawn on screen.
  Offset _toContentSpace(Offset screenPos, Size size) {
    final view = _viewNotifier.value;
    if (view.isDefault) return screenPos;
    final center = Offset(size.width / 2, size.height / 2);
    final afterTranslate = screenPos - view.translation;
    return (afterTranslate - center) / view.scale + center;
  }

  // ---------------- hover / tap handling ----------------

  void _handleTap(Offset pos, Size size, List<PieSlice> visibleSlices) {
    final label = _hitTest(_toContentSpace(pos, size), size, visibleSlices);
    _applyHover(label, visibleSlices);
    if (label != null) {
      final slice = widget.slices.firstWhere((s) => s.label == label);
      widget.onSliceTap?.call(slice);
    }
  }

  void _updateHover(Offset pos, Size size, List<PieSlice> visibleSlices) {
    final label = _hitTest(_toContentSpace(pos, size), size, visibleSlices);
    _applyHover(label, visibleSlices);
  }

  void _applyHover(String? label, List<PieSlice> visibleSlices) {
    final changed = label != _hoveredLabelNotifier.value;
    _hoveredLabelNotifier.value = label;
    if (changed) {
      final slice = label == null ? null : widget.slices.firstWhere((s) => s.label == label);
      widget.onSliceHover?.call(slice);
    }
  }

  String? _hitTest(Offset pos, Size size, List<PieSlice> visible) {
    if (visible.isEmpty) return null;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;
    final dist = (pos - center).distance;
    final innerR = radius * widget.innerRadiusRatio;

    if (dist < innerR || dist > radius) return null;

    var angle = math.atan2(pos.dy - center.dy, pos.dx - center.dx);
    angle = angle < -math.pi / 2 ? angle + 2 * math.pi : angle;
    // normalize so 0 = top (12 o'clock), matching the painter's start angle
    final normalized = (angle + math.pi / 2) % (2 * math.pi);

    final total = visible.fold<double>(0, (sum, s) => sum + s.value);
    double cursor = 0;
    for (final s in visible) {
      final sweep = total == 0 ? 0 : (s.value / total) * 2 * math.pi;
      if (normalized >= cursor && normalized < cursor + sweep) {
        return s.label;
      }
      cursor += sweep;
    }
    return null;
  }

  Widget _buildCenterTooltip(ChartTheme theme, String hoveredLabel, List<PieSlice> visibleSlices) {
    final slice = widget.slices.firstWhere((s) => s.label == hoveredLabel);
    final total = visibleSlices.fold<double>(0, (sum, s) => sum + s.value);
    final pct = total == 0 ? 0.0 : slice.value / total * 100;
    final valueText = widget.valueFormatter?.call(slice.value) ?? slice.value.toStringAsFixed(1);

    final custom = widget.tooltipBuilder;
    if (custom != null) return IgnorePointer(child: custom(context, slice, pct));
    return IgnorePointer(
      child: ChartTooltipCard(
        theme: theme,
        title: slice.label,
        subtitle: '$valueText  (${pct.toStringAsFixed(1)}%)',
      ),
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final List<PieSlice> slices;
  final double innerRadiusRatio;
  final bool showPercentageLabels;
  final String? hoveredLabel;

  /// 0 (collapsed at center) to 1 (full radius) — drives the entrance animation.
  final double progress;
  final String? fontFamily;

  _PieChartPainter({
    required this.slices,
    required this.innerRadiusRatio,
    required this.showPercentageLabels,
    required this.hoveredLabel,
    required this.progress,
    this.fontFamily,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (slices.isEmpty) return;
    final total = slices.fold<double>(0, (sum, s) => sum + s.value);
    if (total <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) / 2 - 8) * progress;
    final innerRadius = radius * innerRadiusRatio;

    if (radius <= 0) return;

    double startAngle = -math.pi / 2; // 12 o'clock
    for (final s in slices) {
      final sweep = (s.value / total) * 2 * math.pi;
      final isHovered = s.label == hoveredLabel;
      final r = isHovered ? radius + 6 : radius;

      final path = Path();
      if (innerRadius > 0) {
        path.addArc(Rect.fromCircle(center: center, radius: r), startAngle, sweep);
        path.arcTo(Rect.fromCircle(center: center, radius: innerRadius), startAngle + sweep, -sweep, false);
        path.close();
      } else {
        path.moveTo(center.dx, center.dy);
        path.arcTo(Rect.fromCircle(center: center, radius: r), startAngle, sweep, false);
        path.close();
      }

      canvas.drawPath(path, Paint()..color = s.color);
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );

      if (showPercentageLabels && sweep > 0.18 && progress > 0.7) {
        final midAngle = startAngle + sweep / 2;
        final labelR = innerRadius > 0 ? (innerRadius + r) / 2 : r * 0.65;
        final labelPos = center + Offset(math.cos(midAngle), math.sin(midAngle)) * labelR;
        final pct = (s.value / total * 100).toStringAsFixed(0);
        _drawCenteredText(canvas, '$pct%', labelPos, opacity: ((progress - 0.7) / 0.3).clamp(0.0, 1.0));
      }

      startAngle += sweep;
    }
  }

  void _drawCenteredText(Canvas canvas, String text, Offset center, {double opacity = 1}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: Colors.white.withValues(alpha: opacity), fontSize: 11, fontWeight: FontWeight.w700, fontFamily: fontFamily),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) => true;
}
