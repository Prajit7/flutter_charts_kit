import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'cartesian_axes.dart';
import 'theme.dart';
import 'chart_chrome.dart';
import 'common.dart';
import 'controller.dart';
import 'hover_plot.dart';

/// One step of a [FunnelChart2D], e.g. "Visited", "Signed up", "Paid".
class FunnelStage {
  final String label;
  final double value;

  /// Defaults to the chart's palette.
  final Color? color;

  const FunnelStage({required this.label, required this.value, this.color});
}

/// A conversion funnel: stages drawn as stacked, narrowing bands, labelled
/// with their value and the share that made it from the first stage.
///
/// ```dart
/// FunnelChart2D(
///   stages: [
///     FunnelStage(label: 'Visited', value: 12000),
///     FunnelStage(label: 'Signed up', value: 3100),
///     FunnelStage(label: 'Activated', value: 1400),
///     FunnelStage(label: 'Paid', value: 380),
///   ],
/// )
/// ```
class FunnelChart2D extends StatefulWidget {
  final List<FunnelStage> stages;
  final String? title;
  final String? subtitle;
  final String emptyStateMessage;
  final String Function(double value) valueFormatter;

  /// Colors for stages without their own, cycled in order.
  final List<Color> palette;

  /// Taper each band into the next (true) or draw straight-edged bars (false).
  final bool tapered;

  /// Gap between bands, in pixels.
  final double gap;

  /// Smallest band width as a fraction of the widest, so tiny final
  /// stages stay visible and labelled.
  final double minWidthFraction;
  final bool enableAnimation;
  final Duration animationDuration;

  /// Replaces the default tooltip card.
  final Widget Function(BuildContext context, FunnelStage stage, int index)? tooltipBuilder;

  /// Export an image from outside the chart.
  final ChartController? controller;
  final void Function(FunnelStage stage, int index)? onStageTap;

  const FunnelChart2D({
    super.key,
    required this.stages,
    this.title,
    this.subtitle,
    this.emptyStateMessage = 'No data to display',
    this.valueFormatter = Cartesian2DAxes.formatNumber,
    this.palette = const [
      Color(0xFF3949AB),
      Color(0xFF1E88E5),
      Color(0xFF00ACC1),
      Color(0xFF43A047),
      Color(0xFF7CB342),
      Color(0xFFFDD835),
    ],
    this.tapered = true,
    this.gap = 3,
    this.minWidthFraction = 0.12,
    this.enableAnimation = true,
    this.animationDuration = const Duration(milliseconds: 600),
    this.tooltipBuilder,
    this.controller,
    this.onStageTap,
  });

  @override
  State<FunnelChart2D> createState() => _FunnelChart2DState();
}

class _FunnelChart2DState extends State<FunnelChart2D> with ChartControllerMixin<FunnelChart2D> {
  @override
  ChartController? controllerOf(FunnelChart2D widget) => widget.controller;

  @override
  void resetZoom() {} // no zoom on this chart

  Color _color(int i) => widget.stages[i].color ?? widget.palette[i % widget.palette.length];

  /// The band area: centred, leaving the right side for the labels.
  Rect _area(Size size) => Rect.fromLTWH(0, 0, size.width * 0.62, size.height);

  double _widthFraction(int i) {
    final top = widget.stages.first.value;
    if (top <= 0) return 1;
    return math.max(widget.minWidthFraction, (widget.stages[i].value / top).clamp(0.0, 1.0));
  }

  Rect _band(Size size, int i) {
    final area = _area(size);
    final n = widget.stages.length;
    final h = (area.height - widget.gap * (n - 1)) / n;
    final w = area.width * _widthFraction(i);
    return Rect.fromLTWH(area.center.dx - w / 2, area.top + i * (h + widget.gap), w, h);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    if (widget.stages.isEmpty) {
      return ChartFrame(
        boundaryKey: chartBoundaryKey,
        title: widget.title,
        subtitle: widget.subtitle,
        plot: ChartEmptyState(message: widget.emptyStateMessage),
      );
    }
    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Funnel chart', widget.title, [for (final s in widget.stages) '${s.label}: ${widget.valueFormatter(s.value)}']),
      title: widget.title,
      subtitle: widget.subtitle,
      plot: HoverPlot<int>(
        enableAnimation: widget.enableAnimation,
        animationDuration: widget.animationDuration,
        animationKey: Object.hashAll([for (final s in widget.stages) Object.hash(s.label, s.value)]),
        onTap: (i) => widget.onStageTap?.call(widget.stages[i], i),
        hitTest: (pos, size) {
          for (int i = 0; i < widget.stages.length; i++) {
            final band = _band(size, i);
            // Anywhere across the row counts, so narrow stages are easy to hit.
            if (pos.dy >= band.top && pos.dy <= band.bottom) return i;
          }
          return null;
        },
        painterBuilder: (size, hover, progress) => _FunnelPainter(
          bands: [for (int i = 0; i < widget.stages.length; i++) _band(size, i)],
          colors: [for (int i = 0; i < widget.stages.length; i++) _color(i)],
          stages: widget.stages,
          tapered: widget.tapered,
          labelLeft: _area(size).right + 12,
          valueFormatter: widget.valueFormatter,
          theme: theme,
          hover: hover,
          progress: Curves.easeOutCubic.transform(progress),
        ),
        tooltipBuilder: (context, i, pointer, size) {
          final s = widget.stages[i];
          final first = widget.stages.first.value;
          final prev = i == 0 ? null : widget.stages[i - 1].value;
          final custom = widget.tooltipBuilder;
          final band = _band(size, i);
          return positionChartTooltip(
            anchor: Offset(band.center.dx, band.center.dy),
            areaSize: size,
            cardWidth: 170,
            child: custom != null
                ? custom(context, s, i)
                : ChartTooltipCard(
                    theme: theme,
                    width: 170,
                    title: s.label,
                    subtitle: [
                      if (first > 0) '${_pct(s.value / first)} of ${widget.stages.first.label}',
                      if (prev != null && prev > 0) '${_pct(s.value / prev)} of previous step',
                    ].join('\n'),
                    value: widget.valueFormatter(s.value),
                  ),
          );
        },
      ),
    );
  }
}

String _pct(double fraction) => '${(fraction * 100).toStringAsFixed(fraction >= 0.1 ? 0 : 1)}%';

class _FunnelPainter extends CustomPainter {
  final List<Rect> bands;
  final List<Color> colors;
  final List<FunnelStage> stages;
  final bool tapered;
  final double labelLeft;
  final String Function(double) valueFormatter;
  final ChartTheme theme;
  final int? hover;
  final double progress;

  _FunnelPainter({
    required this.bands,
    required this.colors,
    required this.stages,
    required this.tapered,
    required this.labelLeft,
    required this.valueFormatter,
    required this.theme,
    required this.hover,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final first = stages.first.value;
    for (int i = 0; i < bands.length; i++) {
      final b = bands[i];
      // Entrance: bands widen out from the centre line.
      final w = b.width * progress;
      final top = Rect.fromCenter(center: b.center, width: w, height: b.height);
      final Path shape;
      if (tapered) {
        // The bottom edge narrows to the next band's width (or 70% for the last).
        final nextW = (i + 1 < bands.length ? bands[i + 1].width : b.width * 0.7) * progress;
        shape = Path()
          ..moveTo(top.left, top.top)
          ..lineTo(top.right, top.top)
          ..lineTo(b.center.dx + nextW / 2, top.bottom)
          ..lineTo(b.center.dx - nextW / 2, top.bottom)
          ..close();
      } else {
        shape = Path()..addRRect(RRect.fromRectAndRadius(top, const Radius.circular(3)));
      }
      canvas.drawPath(shape, Paint()..color = hover == null || hover == i ? colors[i] : colors[i].withValues(alpha: 0.55));

      // Value inside the band when it fits.
      final valueTp = layoutChartText(valueFormatter(stages[i].value),
          color: contrastingTextColor(colors[i]), fontSize: 12, fontWeight: FontWeight.bold, fontFamily: theme.fontFamily);
      if (progress >= 1 && valueTp.width + 8 < math.min(w, tapered ? (i + 1 < bands.length ? bands[i + 1].width : w * 0.7) : w) &&
          valueTp.height < b.height) {
        valueTp.paint(canvas, b.center - Offset(valueTp.width / 2, valueTp.height / 2));
      }

      // Stage label + share of the first stage, to the right.
      final labelTp = layoutChartText(stages[i].label,
          color: theme.axisColor, fontSize: 12, fontFamily: theme.fontFamily, maxWidth: math.max(1, size.width - labelLeft));
      final pctTp = layoutChartText(
          first > 0 ? '${_pct(stages[i].value / first)} · ${valueFormatter(stages[i].value)}' : valueFormatter(stages[i].value),
          color: theme.tickTextColor,
          fontSize: theme.tickFontSize,
          fontFamily: theme.fontFamily,
          maxWidth: math.max(1, size.width - labelLeft));
      final blockH = labelTp.height + pctTp.height;
      final y = b.center.dy - blockH / 2;
      labelTp.paint(canvas, Offset(labelLeft, y));
      pctTp.paint(canvas, Offset(labelLeft, y + labelTp.height));
    }
  }

  @override
  bool shouldRepaint(covariant _FunnelPainter old) => true;
}
