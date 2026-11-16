import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'svg_export.dart';
import 'theme.dart';

/// Maps data-space values to canvas pixels for a simple 2D Cartesian plot,
/// and draws the shared axis lines, gridlines, and tick labels. Shared by
/// [LineChart2D], [BarChart2D], and [ScatterChart2D] painters so the three
/// chart types look visually consistent.
class Cartesian2DAxes {
  final Rect plotArea; // the area inside the axes, in canvas pixels
  final double minX, maxX, minY, maxY;
  final ChartTheme theme;

  /// Map x / y logarithmically. The axis range must then be positive;
  /// values at or below zero are pinned to the axis minimum.
  final bool logX;
  final bool logY;

  Cartesian2DAxes({
    required this.plotArea,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    this.theme = ChartTheme.light,
    this.logX = false,
    this.logY = false,
  });

  static double _log10(double v) => math.log(v) / math.ln10;

  /// Fraction 0–1 of the way from [lo] to [hi] (logarithmically if [log]).
  static double _fraction(double v, double lo, double hi, bool log) {
    if (hi == lo) return 0.5;
    if (!log) return (v - lo) / (hi - lo);
    final l = _log10(lo);
    return ((v > 0 ? _log10(v) : l) - l) / (_log10(hi) - l);
  }

  static double _fromFraction(double t, double lo, double hi, bool log) {
    if (!log) return lo + t * (hi - lo);
    final l = _log10(lo);
    return math.pow(10, l + t * (_log10(hi) - l)).toDouble();
  }

  double toScreenX(double x) => plotArea.left + _fraction(x, minX, maxX, logX) * plotArea.width;

  // screen y grows downward, data y grows upward
  double toScreenY(double y) => plotArea.bottom - _fraction(y, minY, maxY, logY) * plotArea.height;

  /// Inverse of [toScreenX] — converts a canvas x-coordinate back to data
  /// space. Used to turn a drag-selection rectangle into a zoom window.
  double toDataX(double screenX) =>
      _fromFraction(plotArea.width == 0 ? 0.0 : (screenX - plotArea.left) / plotArea.width, minX, maxX, logX);

  /// Inverse of [toScreenY].
  double toDataY(double screenY) =>
      _fromFraction(plotArea.height == 0 ? 0.0 : (plotArea.bottom - screenY) / plotArea.height, minY, maxY, logY);

  /// The y ticks for this axis: nice linear steps, or powers of ten (with
  /// 2× and 5× steps over narrow ranges) on a log axis.
  List<double> get yTicks => logY ? logTicks(minY, maxY) : niceTicks(minY, maxY);

  /// The x ticks for this axis (see [yTicks]).
  List<double> get xTicks => logX ? logTicks(minX, maxX) : niceTicks(minX, maxX);

  /// Log-axis ticks within [min]..[max]: every power of ten, with 2× and 5×
  /// steps when the range spans few decades, and only every n-th decade
  /// when it spans very many.
  static List<double> logTicks(double min, double max) {
    if (min <= 0 || max <= min) return [if (min > 0) min];
    final a = _log10(min).floor(), b = _log10(max).ceil();
    final decades = b - a;
    final multiples = decades <= 2 ? const [1, 2, 5] : const [1];
    final every = decades > 8 ? (decades / 6).ceil() : 1;
    return [
      for (int e = a; e <= b; e += every)
        for (final m in multiples)
          if (m * math.pow(10, e) >= min * (1 - 1e-9) && m * math.pow(10, e) <= max * (1 + 1e-9))
            double.parse((m * math.pow(10, e)).toStringAsPrecision(6)),
    ];
  }

  /// Widens a positive range out to whole powers of ten, for log axes.
  static (double, double) logExtent(double min, double max) {
    if (min <= 0) min = max > 0 ? max / 10 : 1;
    if (max <= min) max = min * 10;
    return (math.pow(10, _log10(min).floor()).toDouble(), math.pow(10, _log10(max).ceil()).toDouble());
  }

  /// Standard padding reserved around the plot for axis titles + tick
  /// labels. Widen [leftPad] for long category labels (horizontal bars) and
  /// [rightPad] when drawing a secondary y-axis.
  static Rect computePlotArea(Size size, {double leftPad = 48, double rightPad = 12}) {
    const bottomPad = 44.0;
    const topPad = 12.0;
    return Rect.fromLTWH(
      leftPad,
      topPad,
      (size.width - leftPad - rightPad).clamp(0, double.infinity),
      (size.height - topPad - bottomPad).clamp(0, double.infinity),
    );
  }

  void drawGridAndAxes(
    Canvas canvas, {
    required List<double> yTicks,
    required String Function(double) yFormatter,
    String? xAxisTitle,
    String? yAxisTitle,
    bool showGrid = true,
  }) {
    final axisPaint = Paint()
      ..color = theme.axisColor
      ..strokeWidth = 1.2;
    final gridPaint = Paint()
      ..color = theme.gridColor
      ..strokeWidth = 1;
    final tickPaint = Paint()
      ..color = theme.axisColor.withValues(alpha: 0.5)
      ..strokeWidth = 1;

    // Y gridlines + ticks. If the widest label (e.g. "10000") won't fit the
    // left margin, shrink the tick font rather than clip the labels.
    final labels = [for (final yv in yTicks) yFormatter(yv)];
    final room = plotArea.left - 8;
    final widest = labels.fold(0.0, (w, t) => math.max(w, _layoutText(t, theme.tickTextColor, size: theme.tickFontSize).width));
    final fontSize = widest > room && widest > 0 ? math.max(7.0, theme.tickFontSize * room / widest) : theme.tickFontSize;
    for (int i = 0; i < yTicks.length; i++) {
      final y = toScreenY(yTicks[i]);
      if (showGrid) {
        canvas.drawLine(Offset(plotArea.left, y), Offset(plotArea.right, y), gridPaint);
      }
      canvas.drawLine(Offset(plotArea.left - 4, y), Offset(plotArea.left, y), tickPaint);
      final label = _layoutText(labels[i], theme.tickTextColor, size: fontSize);
      label.paint(canvas, Offset(plotArea.left - 6 - label.width, y - label.height / 2));
    }

    // Axis lines
    canvas.drawLine(plotArea.bottomLeft, plotArea.topLeft, axisPaint);
    canvas.drawLine(plotArea.bottomLeft, plotArea.bottomRight, axisPaint);

    if (yAxisTitle != null) {
      // Rotated to read bottom-to-top, hugging the left edge (clear of the
      // right-aligned tick labels) and centred on the plot.
      final title = _layoutText(yAxisTitle, theme.axisColor, size: 12);
      canvas.save();
      canvas.translate(0, plotArea.center.dy + title.width / 2);
      canvas.rotate(-1.5708); // -90deg
      title.paint(canvas, Offset.zero);
      canvas.restore();
    }
    if (xAxisTitle != null) {
      final title = _layoutText(xAxisTitle, theme.axisColor, size: 12);
      title.paint(canvas, Offset(plotArea.center.dx - title.width / 2, plotArea.bottom + 26));
    }
  }

  /// Draws x-axis tick marks and their labels, centred under each tick.
  ///
  /// Labels that would overlap the previous one are skipped (the tick mark
  /// is still drawn), so dense categories or long date strings stay legible
  /// at any width. Very dense inputs are thinned to an even stride first so
  /// only a bounded number of labels is ever measured.
  void drawXTicks(Canvas canvas, List<(double, String)> ticks, {double minGap = 8}) {
    if (ticks.isEmpty) return;
    final tickPaint = Paint()
      ..color = theme.axisColor.withValues(alpha: 0.5)
      ..strokeWidth = 1;

    final maxLabels = math.max(1, (plotArea.width / 24).floor());
    final stride = (ticks.length / maxLabels).ceil();

    double lastRight = double.negativeInfinity;
    for (int i = 0; i < ticks.length; i += stride) {
      final (screenX, text) = ticks[i];
      canvas.drawLine(Offset(screenX, plotArea.bottom), Offset(screenX, plotArea.bottom + 4), tickPaint);
      final label = _layoutText(text, theme.tickTextColor, size: theme.tickFontSize);
      // Centre under the tick, but keep the label inside the canvas.
      final left = (screenX - label.width / 2).clamp(0.0, math.max(0.0, plotArea.right + 12 - label.width)).toDouble();
      if (left < lastRight + minGap) continue;
      label.paint(canvas, Offset(left, plotArea.bottom + 8));
      lastRight = left + label.width;
    }
  }

  /// Draws a dashed crosshair through [dataPoint] within the plot area —
  /// vertical line only if [horizontal] is false, both if true.
  void drawCrosshair(Canvas canvas, Offset screenPoint, {bool bothAxes = true}) {
    final paint = Paint()
      ..color = theme.crosshairColor
      ..strokeWidth = 1;
    _dashedLine(canvas, Offset(screenPoint.dx, plotArea.top), Offset(screenPoint.dx, plotArea.bottom), paint);
    if (bothAxes) {
      _dashedLine(canvas, Offset(plotArea.left, screenPoint.dy), Offset(plotArea.right, screenPoint.dy), paint);
    }
  }

  /// Draws y-axis ticks and labels down the plot's right edge — a secondary
  /// axis whose scale is this instance's [minY]..[maxY].
  void drawRightAxis(Canvas canvas, {required List<double> yTicks, required String Function(double) yFormatter, String? title}) {
    final axisPaint = Paint()
      ..color = theme.axisColor
      ..strokeWidth = 1.2;
    final tickPaint = Paint()
      ..color = theme.axisColor.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    canvas.drawLine(plotArea.bottomRight, plotArea.topRight, axisPaint);
    for (final yv in yTicks) {
      final y = toScreenY(yv);
      canvas.drawLine(Offset(plotArea.right, y), Offset(plotArea.right + 4, y), tickPaint);
      final label = _layoutText(yFormatter(yv), theme.tickTextColor, size: theme.tickFontSize);
      label.paint(canvas, Offset(plotArea.right + 6, y - label.height / 2));
    }
    if (title != null) {
      final t = _layoutText(title, theme.axisColor, size: 12);
      canvas.save();
      canvas.translate(plotArea.right + 44, plotArea.center.dy - t.width / 2);
      canvas.rotate(1.5708); // +90deg, reads top-to-bottom
      t.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  /// Draws a small tick-styled text label at [position]. With [alignRight]
  /// / [alignBottom], [position] is the label's right / bottom edge instead.
  void drawLabel(Canvas canvas, String text, Offset position,
      {Color? color, bool alignRight = false, bool alignBottom = false, double? fontSize}) {
    final tp = _layoutText(text, color ?? theme.tickTextColor, size: fontSize ?? theme.tickFontSize);
    tp.paint(canvas, Offset(alignRight ? position.dx - tp.width : position.dx, alignBottom ? position.dy - tp.height : position.dy));
  }

  /// Measures [text] as [drawLabel] would draw it.
  Size measureLabel(String text, {double? fontSize}) =>
      _layoutText(text, theme.tickTextColor, size: fontSize ?? theme.tickFontSize).size;

  void dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) => _dashedLine(canvas, a, b, paint);

  /// [dashedLine] for callers without an axes instance.
  static void dashedLineStatic(Canvas canvas, Offset a, Offset b, Paint paint) => _dashedLine(canvas, a, b, paint);

  static void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dashLength = 4.0;
    const gapLength = 3.0;
    final total = (b - a).distance;
    if (total == 0) return;
    final direction = (b - a) / total;
    double drawn = 0;
    while (drawn < total) {
      final segEnd = drawn + dashLength < total ? drawn + dashLength : total;
      canvas.drawLine(a + direction * drawn, a + direction * segEnd, paint);
      drawn += dashLength + gapLength;
    }
  }

  /// Default number formatter for ticks and tooltips: whole numbers without
  /// decimals, otherwise up to two decimals with trailing zeros trimmed.
  static String formatNumber(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  /// A "nice" tick step (1, 2 or 5 times a power of ten) that splits
  /// [range] into roughly [count] intervals.
  static double niceStep(double range, {int count = 5}) {
    final rough = range.abs() / count;
    if (rough == 0 || !rough.isFinite) return 1;
    final magnitude = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
    final norm = rough / magnitude;
    final nice = norm < 1.5
        ? 1
        : norm < 3
            ? 2
            : norm < 7
                ? 5
                : 10;
    return nice * magnitude;
  }

  /// Tick values at a [niceStep] that fall within [min]..[max], e.g.
  /// 0, 25, 50, 75, 100 rather than 0, 23.4, 46.8, ...
  static List<double> niceTicks(double min, double max, {int count = 5}) {
    if (min == max) return [min];
    if (min > max) (min, max) = (max, min);
    final step = niceStep(max - min, count: count);
    // Round away float noise (0.30000000000000004) using the step's precision.
    final decimals = math.max(0, -(math.log(step) / math.ln10).floor() + 1);
    final first = (min / step).ceil() * step;
    final ticks = <double>[];
    for (double v = first; v <= max + step * 1e-6; v += step) {
      ticks.add(double.parse(v.toStringAsFixed(decimals)));
    }
    return ticks;
  }

  /// Widens [min]..[max] outward to the nearest [niceStep] multiples, so the
  /// first and last gridlines sit exactly on the plot's edges.
  ///
  /// Widening can change the step [niceTicks] will pick for the new range
  /// (e.g. -6..25 → -10..25, whose step is 10 not 5), so this repeats until
  /// the step is stable — guaranteeing both ends land exactly on a tick.
  static (double, double) niceExtent(double min, double max, {int count = 5}) {
    if (min == max) return (min, max);
    var lo = min, hi = max;
    for (int i = 0; i < 4; i++) {
      final step = niceStep(hi - lo, count: count);
      final next = ((min / step).floor() * step, (max / step).ceil() * step);
      if (next == (lo, hi)) break;
      (lo, hi) = next;
    }
    return (lo, hi);
  }

  TextPainter _layoutText(String text, Color color, {double size = 12}) {
    return ChartTextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w600, fontFamily: theme.fontFamily)),
      textDirection: TextDirection.ltr,
    )..layout();
  }
}
