import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'cartesian_axes.dart';
import 'theme.dart';
import 'common.dart';
import 'controller.dart';

/// A colored stretch of a [GaugeChart]'s scale, e.g. "danger" from 80 to 100.
class GaugeRange {
  final double from;
  final double to;
  final Color color;
  final String? label;

  const GaugeRange({required this.from, required this.to, required this.color, this.label});
}

/// How a [GaugeChart] shows its value.
enum GaugeStyle {
  /// A filled arc from the minimum up to the value — a progress meter.
  arc,

  /// A needle pointing at the value over the (optionally banded) scale.
  needle,
}

/// A single value on a dial — progress toward a goal, a KPI against
/// thresholds, a speedometer.
///
/// ```dart
/// GaugeChart(
///   value: 72,
///   max: 100,
///   label: 'CPU',
///   valueFormatter: (v) => '${v.round()}%',
///   ranges: [
///     GaugeRange(from: 0, to: 60, color: Colors.green),
///     GaugeRange(from: 60, to: 85, color: Colors.orange),
///     GaugeRange(from: 85, to: 100, color: Colors.red),
///   ],
/// )
/// ```
///
/// Changing [value] animates the gauge from its previous value.
class GaugeChart extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final GaugeStyle style;

  /// Colored bands along the scale. With [GaugeStyle.arc] the value arc
  /// takes the color of the range it ends in.
  final List<GaugeRange> ranges;

  /// Value arc / needle color when no range applies. Defaults to the
  /// theme's axis color for needles and blue for arcs.
  final Color? color;

  /// Caption under the value, e.g. the metric name.
  final String? label;
  final String? title;
  final String? subtitle;
  final String Function(double value) valueFormatter;

  /// Total sweep of the dial in degrees (180 = half circle, 270 = ¾).
  final double sweepAngle;

  /// Thickness of the arc as a fraction of the radius.
  final double thickness;

  /// Print the min and max values at the ends of the dial.
  final bool showMinMax;

  final bool enableAnimation;
  final Duration animationDuration;

  /// Export an image from outside the chart.
  final ChartController? controller;

  const GaugeChart({
    super.key,
    required this.value,
    this.min = 0,
    this.max = 100,
    this.style = GaugeStyle.arc,
    this.ranges = const [],
    this.color,
    this.label,
    this.title,
    this.subtitle,
    this.valueFormatter = Cartesian2DAxes.formatNumber,
    this.sweepAngle = 240,
    this.thickness = 0.18,
    this.showMinMax = true,
    this.enableAnimation = true,
    this.animationDuration = const Duration(milliseconds: 800),
    this.controller,
  })  : assert(max > min, 'max must be greater than min'),
        assert(sweepAngle > 0 && sweepAngle <= 360);

  @override
  State<GaugeChart> createState() => _GaugeChartState();
}

class _GaugeChartState extends State<GaugeChart>
    with SingleTickerProviderStateMixin, ChartControllerMixin<GaugeChart> {
  late final AnimationController _controller;
  late Animation<double> _value;

  @override
  ChartController? controllerOf(GaugeChart widget) => widget.controller;

  @override
  void resetZoom() {} // no zoom on this chart

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.animationDuration);
    _animateTo(from: widget.min);
  }

  void _animateTo({required double from}) {
    _value = Tween(begin: from, end: widget.value).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    if (widget.enableAnimation) {
      _controller.forward(from: 0);
    } else {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant GaugeChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _animateTo(from: _value.value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      title: widget.title,
      subtitle: widget.subtitle,
      plot: Semantics(
        label: '${widget.label ?? widget.title ?? 'Gauge'}: ${widget.valueFormatter(widget.value)}',
        child: AnimatedBuilder(
          animation: _value,
          builder: (context, _) => CustomPaint(
            size: Size.infinite,
            painter: _GaugePainter(widget, _value.value, theme),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final GaugeChart g;
  final double value;
  final ChartTheme theme;

  _GaugePainter(this.g, this.value, this.theme);

  double _fraction(double v) => ((v - g.min) / (g.max - g.min)).clamp(0.0, 1.0);

  Color? _rangeColorAt(double v) {
    for (final r in g.ranges) {
      if (v >= math.min(r.from, r.to) && v <= math.max(r.from, r.to)) return r.color;
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final sweep = g.sweepAngle * math.pi / 180;
    // The dial opens downward, symmetric about the vertical axis.
    final start = math.pi / 2 + (2 * math.pi - sweep) / 2;

    // Fit the dial's bounding box (a full circle, minus whatever the gap at
    // the bottom cuts off) into the available space.
    final bottomExtent = sweep >= math.pi ? math.max(0.0, -math.cos(sweep / 2)) : 0.0;
    final below = math.max(bottomExtent, 0.35); // room under the centre for text
    final radius = math.max(0.0, math.min(size.width / 2, size.height / (1 + below)) - 6);
    if (radius <= 0) return;
    // Centre the whole dial (arc + text below) vertically.
    final contentHeight = radius * (1 + below);
    final center = Offset(size.width / 2, (size.height - contentHeight) / 2 + radius);
    final stroke = radius * g.thickness;
    final arcRect = Rect.fromCircle(center: center, radius: radius - stroke / 2);

    Paint arcPaint(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    // Track
    canvas.drawArc(arcRect, start, sweep, false, arcPaint(theme.gridColor));

    // Ranges
    final faded = g.style == GaugeStyle.arc;
    for (final r in g.ranges) {
      final a = _fraction(r.from), b = _fraction(r.to);
      canvas.drawArc(arcRect, start + sweep * math.min(a, b), sweep * (b - a).abs(), false,
          arcPaint(faded ? r.color.withValues(alpha: 0.25) : r.color));
    }

    final f = _fraction(value);
    if (g.style == GaugeStyle.arc) {
      final color = _rangeColorAt(value) ?? g.color ?? Colors.blue;
      canvas.drawArc(arcRect, start, sweep * f, false, arcPaint(color)..strokeCap = StrokeCap.round);
    } else {
      final angle = start + sweep * f;
      final tip = center + Offset(math.cos(angle), math.sin(angle)) * (radius - stroke * 0.3);
      final needleColor = g.color ?? theme.axisColor;
      final normal = Offset(-math.sin(angle), math.cos(angle)) * (stroke * 0.22);
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(center.dx + normal.dx, center.dy + normal.dy)
          ..lineTo(center.dx - normal.dx, center.dy - normal.dy)
          ..close(),
        Paint()..color = needleColor,
      );
      canvas.drawCircle(center, stroke * 0.35, Paint()..color = needleColor);
    }

    // Value + label in the middle (below the hub for needles).
    final valueText = layoutChartText(g.valueFormatter(value),
        color: theme.titleColor, fontSize: radius * 0.32, fontWeight: FontWeight.bold, fontFamily: theme.fontFamily);
    final valueTop = g.style == GaugeStyle.needle ? center.dy + stroke * 0.6 : center.dy - valueText.height * 0.6;
    valueText.paint(canvas, Offset(center.dx - valueText.width / 2, valueTop));
    if (g.label != null) {
      final label = layoutChartText(g.label!,
          color: theme.subtitleColor, fontSize: math.max(10, radius * 0.11), fontFamily: theme.fontFamily);
      label.paint(canvas, Offset(center.dx - label.width / 2, valueTop + valueText.height));
    }

    if (g.showMinMax) {
      for (final (v, a) in [(g.min, start), (g.max, start + sweep)]) {
        final tp = layoutChartText(g.valueFormatter(v), color: theme.tickTextColor, fontSize: theme.tickFontSize, fontFamily: theme.fontFamily);
        final p = center + Offset(math.cos(a), math.sin(a)) * (radius - stroke / 2);
        tp.paint(canvas, Offset(p.dx - tp.width / 2, p.dy + stroke / 2 + 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) => true;
}
