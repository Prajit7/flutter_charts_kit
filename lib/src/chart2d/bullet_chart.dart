import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'cartesian_axes.dart';
import 'theme.dart';
import 'common.dart';

/// A qualitative band behind a [BulletChart]'s bar, e.g. "poor" up to 60.
class BulletRange {
  /// Upper end of the band; it starts where the previous one ended (or at
  /// the chart's minimum).
  final double to;

  /// Defaults to graded shades of the theme's grid color.
  final Color? color;
  final String? label;

  const BulletRange(this.to, {this.color, this.label});
}

/// A bullet chart: one measure against a target, over qualitative bands —
/// a compact, readable replacement for a gauge in dashboards and tables.
///
/// ```dart
/// BulletChart(
///   label: 'Revenue',
///   sublabel: 'USD k',
///   value: 270,
///   target: 250,
///   ranges: [BulletRange(150), BulletRange(225), BulletRange(300)],
/// )
/// ```
///
/// Sizes itself to its parent; stack several in a [Column] for a KPI panel.
class BulletChart extends StatelessWidget {
  final double value;

  /// The goal, drawn as a short perpendicular line.
  final double? target;

  /// Extra markers, e.g. last year's value.
  final List<double> comparatives;

  /// Qualitative bands from [min] upwards, darkest first.
  final List<BulletRange> ranges;
  final double min;

  /// The scale's end. Defaults to a nice number above the value, target and
  /// bands.
  final double? max;
  final String? label;
  final String? sublabel;

  /// Width reserved for [label]/[sublabel] (horizontal layout).
  final double labelWidth;
  final Axis orientation;
  final Color? barColor;
  final Color? targetColor;
  final String Function(double value) valueFormatter;
  final bool showAxis;
  final bool enableAnimation;
  final Duration animationDuration;

  const BulletChart({
    super.key,
    required this.value,
    this.target,
    this.comparatives = const [],
    this.ranges = const [],
    this.min = 0,
    this.max,
    this.label,
    this.sublabel,
    this.labelWidth = 96,
    this.orientation = Axis.horizontal,
    this.barColor,
    this.targetColor,
    this.valueFormatter = Cartesian2DAxes.formatNumber,
    this.showAxis = true,
    this.enableAnimation = true,
    this.animationDuration = const Duration(milliseconds: 600),
  });

  double get _max {
    if (max != null) return max!;
    final top = [value, target ?? value, ...comparatives, ...ranges.map((r) => r.to)].reduce(math.max);
    return Cartesian2DAxes.niceExtent(min, top <= min ? min + 1 : top).$2;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    final f = valueFormatter;
    return Semantics(
      label: [
        if (label != null) label!,
        f(value),
        if (target != null) 'target ${f(target!)}',
        if (target != null) value >= target! ? 'on target' : 'below target',
      ].join(', '),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: enableAnimation ? min : value, end: value),
        duration: enableAnimation ? animationDuration : Duration.zero,
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => CustomPaint(
          size: Size.infinite,
          painter: _BulletPainter(this, v, _max, theme),
        ),
      ),
    );
  }
}

class _BulletPainter extends CustomPainter {
  final BulletChart b;
  final double value;
  final double max;
  final ChartTheme theme;

  _BulletPainter(this.b, this.value, this.max, this.theme);

  @override
  void paint(Canvas canvas, Size size) {
    final horizontal = b.orientation == Axis.horizontal;
    final hasLabel = b.label != null || b.sublabel != null;
    final axisSpace = b.showAxis ? 16.0 : 0.0;

    // The track: everything but the label column and the axis labels.
    final Rect track;
    if (horizontal) {
      final left = hasLabel ? math.min(b.labelWidth, size.width * 0.4) : 0.0;
      track = Rect.fromLTRB(left, 2, size.width - 6, size.height - axisSpace - 2);
      if (hasLabel) {
        final title = b.label == null
            ? null
            : layoutChartText(b.label!, color: theme.titleColor, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: theme.fontFamily, maxWidth: left - 10);
        final sub = b.sublabel == null
            ? null
            : layoutChartText(b.sublabel!, color: theme.subtitleColor, fontSize: theme.tickFontSize, fontFamily: theme.fontFamily, maxWidth: left - 10);
        final h = (title?.height ?? 0) + (sub?.height ?? 0);
        var y = track.center.dy - h / 2;
        title?.paint(canvas, Offset(left - 10 - title.width, y));
        if (title != null) y += title.height;
        sub?.paint(canvas, Offset(left - 10 - sub.width, y));
      }
    } else {
      final top = hasLabel ? 34.0 : 2.0;
      track = Rect.fromLTRB(2, top, size.width - (b.showAxis ? 34 : 2), size.height - 6);
      if (b.label != null) {
        final t = layoutChartText(b.label!, color: theme.titleColor, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: theme.fontFamily, maxWidth: size.width);
        t.paint(canvas, Offset(track.center.dx - t.width / 2, 0));
        if (b.sublabel != null) {
          final s = layoutChartText(b.sublabel!, color: theme.subtitleColor, fontSize: theme.tickFontSize, fontFamily: theme.fontFamily, maxWidth: size.width);
          s.paint(canvas, Offset(track.center.dx - s.width / 2, t.height));
        }
      }
    }
    if (track.width <= 0 || track.height <= 0) return;

    // Value → distance along the track.
    double along(double v) => ((v - b.min) / (max - b.min)).clamp(0.0, 1.0) * (horizontal ? track.width : track.height);
    Rect span(double from, double to, double thicknessFraction) {
      final a = along(from), z = along(to);
      if (horizontal) {
        final t = track.height * thicknessFraction;
        return Rect.fromLTRB(track.left + a, track.center.dy - t / 2, track.left + z, track.center.dy + t / 2);
      }
      final t = track.width * thicknessFraction;
      return Rect.fromLTRB(track.center.dx - t / 2, track.bottom - z, track.center.dx + t / 2, track.bottom - a);
    }

    // Qualitative bands: darkest first, lightening outward.
    final n = b.ranges.length;
    double from = b.min;
    for (int i = 0; i < n; i++) {
      final r = b.ranges[i];
      final shade = r.color ?? theme.axisColor.withValues(alpha: 0.32 - 0.24 * (n == 1 ? 0 : i / (n - 1)));
      canvas.drawRect(span(from, r.to, 1), Paint()..color = shade);
      from = r.to;
    }
    if (n == 0) canvas.drawRect(span(b.min, max, 1), Paint()..color = theme.gridColor);

    canvas.drawRect(span(b.min, value, 0.36), Paint()..color = b.barColor ?? theme.titleColor);

    void marker(double v, double fraction, double width) {
      final p = along(v);
      final paint = Paint()
        ..color = b.targetColor ?? theme.titleColor
        ..strokeWidth = width;
      if (horizontal) {
        final t = track.height * fraction / 2;
        canvas.drawLine(Offset(track.left + p, track.center.dy - t), Offset(track.left + p, track.center.dy + t), paint);
      } else {
        final t = track.width * fraction / 2;
        canvas.drawLine(Offset(track.center.dx - t, track.bottom - p), Offset(track.center.dx + t, track.bottom - p), paint);
      }
    }

    for (final c in b.comparatives) {
      marker(c, 0.5, 1.5);
    }
    if (b.target != null) marker(b.target!, 0.72, 3);

    if (b.showAxis) {
      final ticks = Cartesian2DAxes.niceTicks(b.min, max, count: horizontal ? math.max(2, (track.width / 70).floor()) : 4);
      for (final v in ticks) {
        final tp = layoutChartText(b.valueFormatter(v), color: theme.tickTextColor, fontSize: theme.tickFontSize - 1, fontFamily: theme.fontFamily);
        if (horizontal) {
          final x = (track.left + along(v) - tp.width / 2).clamp(track.left - tp.width / 2, size.width - tp.width);
          tp.paint(canvas, Offset(x, track.bottom + 3));
        } else {
          tp.paint(canvas, Offset(track.right + 4, track.bottom - along(v) - tp.height / 2));
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BulletPainter old) => old.value != value || old.b != b || old.theme != theme || old.max != max;
}
