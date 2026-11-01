import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'curves.dart';

/// How a [Sparkline] draws its values.
enum SparklineType { line, bar }

/// A tiny chart with no axes, labels or interaction — for showing a trend
/// inline in a list tile, table cell, or KPI card.
///
/// Sizes itself to its parent; give it a bounded box:
///
/// ```dart
/// SizedBox(
///   width: 100,
///   height: 28,
///   child: Sparkline(values: [3, 5, 4, 8, 6, 9], color: Colors.green),
/// )
/// ```
class Sparkline extends StatelessWidget {
  final List<double> values;
  final Color color;
  final SparklineType type;
  final LineChartCurve curve;
  final double lineWidth;

  /// Shade the area under the line (line type only).
  final bool filled;

  /// Mark the last value with a dot (line type only).
  final bool showLastPoint;

  /// Mark the highest and lowest values with dots (line type only).
  final bool showMinMax;

  /// Bar color for negative values (bar type). Defaults to [color].
  final Color? negativeColor;

  /// Draw a faint horizontal line at this value (e.g. a target or zero).
  final double? referenceValue;

  /// Pin the vertical scale instead of fitting the data, so several
  /// sparklines can be compared directly.
  final double? min;
  final double? max;

  /// Describes the trend for screen readers, e.g. "Sales up 12% this week".
  final String? semanticLabel;

  const Sparkline({
    super.key,
    required this.values,
    this.color = Colors.blue,
    this.type = SparklineType.line,
    this.curve = LineChartCurve.straight,
    this.lineWidth = 1.5,
    this.filled = false,
    this.showLastPoint = true,
    this.showMinMax = false,
    this.negativeColor,
    this.referenceValue,
    this.min,
    this.max,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      image: true,
      child: CustomPaint(
        painter: _SparklinePainter(this),
        size: Size.infinite,
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final Sparkline s;
  _SparklinePainter(this.s);

  @override
  void paint(Canvas canvas, Size size) {
    final values = s.values;
    if (values.isEmpty || size.isEmpty) return;

    final pad = s.type == SparklineType.line ? math.max(s.lineWidth, 2.5) : 0.0;
    final area = Rect.fromLTRB(pad, pad, size.width - pad, size.height - pad);
    var lo = s.min ?? values.reduce(math.min);
    var hi = s.max ?? values.reduce(math.max);
    if (s.type == SparklineType.bar) {
      // bars grow from zero, so zero must be in range
      lo = math.min(lo, 0);
      hi = math.max(hi, 0);
    }
    if (s.referenceValue != null) {
      lo = math.min(lo, s.referenceValue!);
      hi = math.max(hi, s.referenceValue!);
    }
    double y(double v) => hi == lo ? area.center.dy : area.bottom - (v - lo) / (hi - lo) * area.height;

    if (s.referenceValue != null) {
      final ry = y(s.referenceValue!);
      canvas.drawLine(Offset(area.left, ry), Offset(area.right, ry),
          Paint()
            ..color = s.color.withValues(alpha: 0.3)
            ..strokeWidth = 1);
    }

    if (s.type == SparklineType.bar) {
      final slot = area.width / values.length;
      final zero = y(0);
      for (int i = 0; i < values.length; i++) {
        final top = y(values[i]);
        final rect = Rect.fromLTRB(area.left + i * slot + slot * 0.15, math.min(top, zero), area.left + (i + 1) * slot - slot * 0.15,
            math.max(math.max(top, zero), math.min(top, zero) + 1)); // at least 1px so zeros show
        canvas.drawRect(rect, Paint()..color = values[i] < 0 ? (s.negativeColor ?? s.color) : s.color);
      }
      return;
    }

    final pts = [
      for (int i = 0; i < values.length; i++)
        Offset(values.length == 1 ? area.center.dx : area.left + i / (values.length - 1) * area.width, y(values[i])),
    ];
    final line = Path();
    traceCurve(line, pts, s.curve);

    if (s.filled) {
      final fill = Path.from(line)
        ..lineTo(pts.last.dx, area.bottom)
        ..lineTo(pts.first.dx, area.bottom)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [s.color.withValues(alpha: 0.3), s.color.withValues(alpha: 0.02)],
          ).createShader(area),
      );
    }

    canvas.drawPath(
      line,
      Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.lineWidth
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    final dot = Paint()..color = s.color;
    if (s.showMinMax && values.length > 1) {
      int iMin = 0, iMax = 0;
      for (int i = 1; i < values.length; i++) {
        if (values[i] < values[iMin]) iMin = i;
        if (values[i] > values[iMax]) iMax = i;
      }
      canvas.drawCircle(pts[iMax], 2, dot);
      canvas.drawCircle(pts[iMin], 2, dot);
    }
    if (s.showLastPoint) canvas.drawCircle(pts.last, 2.5, dot);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      !listEquals(old.s.values, s.values) ||
      old.s.color != s.color ||
      old.s.type != s.type ||
      old.s.curve != s.curve ||
      old.s.filled != s.filled ||
      old.s.min != s.min ||
      old.s.max != s.max ||
      old.s.referenceValue != s.referenceValue ||
      old.s.showLastPoint != s.showLastPoint ||
      old.s.showMinMax != s.showMinMax ||
      old.s.lineWidth != s.lineWidth ||
      old.s.negativeColor != s.negativeColor;
}
