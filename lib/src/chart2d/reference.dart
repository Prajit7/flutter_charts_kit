import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'cartesian_axes.dart';
import 'common.dart';
import 'theme.dart';

/// Which data axis a reference line/band is measured along.
enum ChartReferenceAxis {
  /// A value on the x-axis — drawn as a vertical line / column.
  x,

  /// A value on the y-axis — drawn as a horizontal line / row.
  y,
}

/// A straight marker line across the plot at a fixed data value — a target,
/// threshold, average, or "today" marker.
///
/// ```dart
/// LineChart2D(
///   referenceLines: [
///     ChartReferenceLine.y(100, label: 'Target', color: Colors.red),
///     ChartReferenceLine.time(DateTime(2026, 3, 1), label: 'Launch'),
///   ],
///   ...
/// )
/// ```
///
/// Lines outside the visible range are skipped; they don't widen the axes.
class ChartReferenceLine {
  final ChartReferenceAxis axis;
  final double value;
  final String? label;

  /// Defaults to the theme's crosshair color.
  final Color? color;
  final double strokeWidth;
  final bool dashed;

  const ChartReferenceLine({
    required this.axis,
    required this.value,
    this.label,
    this.color,
    this.strokeWidth = 1.2,
    this.dashed = true,
  });

  /// A horizontal line at y = [value].
  const ChartReferenceLine.y(this.value, {this.label, this.color, this.strokeWidth = 1.2, this.dashed = true})
      : axis = ChartReferenceAxis.y;

  /// A vertical line at x = [value].
  const ChartReferenceLine.x(this.value, {this.label, this.color, this.strokeWidth = 1.2, this.dashed = true})
      : axis = ChartReferenceAxis.x;

  /// A vertical line at [time], for charts using a time x-axis.
  ChartReferenceLine.time(DateTime time, {this.label, this.color, this.strokeWidth = 1.2, this.dashed = true})
      : axis = ChartReferenceAxis.x,
        value = time.millisecondsSinceEpoch.toDouble();
}

/// A shaded range across the plot between two data values — a normal range,
/// a target zone, or a highlighted period.
///
/// Drawn behind the data. The visible part is clipped to the plot.
class ChartReferenceBand {
  final ChartReferenceAxis axis;
  final double from;
  final double to;
  final String? label;

  /// Defaults to a faint version of the theme's crosshair color.
  final Color? color;

  const ChartReferenceBand({required this.axis, required this.from, required this.to, this.label, this.color});

  /// A horizontal band between y = [from] and y = [to].
  const ChartReferenceBand.y(this.from, this.to, {this.label, this.color}) : axis = ChartReferenceAxis.y;

  /// A vertical band between x = [from] and x = [to].
  const ChartReferenceBand.x(this.from, this.to, {this.label, this.color}) : axis = ChartReferenceAxis.x;

  /// A vertical band between two times, for charts using a time x-axis.
  ChartReferenceBand.time(DateTime from, DateTime to, {this.label, this.color})
      : axis = ChartReferenceAxis.x,
        from = from.millisecondsSinceEpoch.toDouble(),
        to = to.millisecondsSinceEpoch.toDouble();
}

/// Draws reference bands and lines onto a plot laid out by [axes].
/// Pass `supportsX: false` for charts whose x-axis is categorical (bars),
/// where x-values have no meaning.
class ReferencePainter {
  final Cartesian2DAxes axes;
  final bool supportsX;

  const ReferencePainter(this.axes, {this.supportsX = true});

  void paintBands(Canvas canvas, List<ChartReferenceBand> bands) {
    if (bands.isEmpty) return;
    final plot = axes.plotArea;
    canvas.save();
    canvas.clipRect(plot);
    for (final band in bands) {
      if (band.axis == ChartReferenceAxis.x && !supportsX) continue;
      final color = band.color ?? axes.theme.crosshairColor.withValues(alpha: 0.12);
      final Rect rect;
      if (band.axis == ChartReferenceAxis.y) {
        final a = axes.toScreenY(band.from), b = axes.toScreenY(band.to);
        rect = Rect.fromLTRB(plot.left, a < b ? a : b, plot.right, a < b ? b : a);
      } else {
        final a = axes.toScreenX(band.from), b = axes.toScreenX(band.to);
        rect = Rect.fromLTRB(a < b ? a : b, plot.top, a < b ? b : a, plot.bottom);
      }
      canvas.drawRect(rect, Paint()..color = color);
      if (band.label != null) {
        final visible = rect.intersect(plot);
        if (!visible.isEmpty) axes.drawLabel(canvas, band.label!, visible.topLeft + const Offset(4, 2));
      }
    }
    canvas.restore();
  }

  void paintLines(Canvas canvas, List<ChartReferenceLine> lines) {
    final plot = axes.plotArea;
    for (final line in lines) {
      if (line.axis == ChartReferenceAxis.x && !supportsX) continue;
      final color = line.color ?? axes.theme.crosshairColor;
      final paint = Paint()
        ..color = color
        ..strokeWidth = line.strokeWidth;
      final Offset a, b;
      if (line.axis == ChartReferenceAxis.y) {
        final y = axes.toScreenY(line.value);
        if (y < plot.top - 0.5 || y > plot.bottom + 0.5) continue;
        a = Offset(plot.left, y);
        b = Offset(plot.right, y);
      } else {
        final x = axes.toScreenX(line.value);
        if (x < plot.left - 0.5 || x > plot.right + 0.5) continue;
        a = Offset(x, plot.top);
        b = Offset(x, plot.bottom);
      }
      line.dashed ? axes.dashedLine(canvas, a, b, paint) : canvas.drawLine(a, b, paint);
      if (line.label != null) {
        // Horizontal lines: label sits just above the line at the right end.
        // Vertical lines: label sits just right of the line at the top.
        final pos = line.axis == ChartReferenceAxis.y ? b + const Offset(-4, -3) : a + const Offset(4, 2);
        axes.drawLabel(canvas, line.label!, pos,
            color: color, alignRight: line.axis == ChartReferenceAxis.y, alignBottom: line.axis == ChartReferenceAxis.y);
      }
    }
  }
}

/// A callout pinned to a data point: a small labelled box joined to the
/// point by a leader line — "Launch", "All-time high", "Outage".
///
/// ```dart
/// LineChart2D(
///   annotations: [ChartAnnotation(x: 6, y: 182, text: 'Record month')],
///   ...
/// )
/// ```
///
/// [x] is in the chart's x units: data x for line/scatter, the category
/// index for bar/combo, milliseconds since epoch for time axes and
/// candlesticks (see [ChartAnnotation.at]). Annotations whose point is out
/// of view aren't drawn.
class ChartAnnotation {
  final double x;
  final double y;
  final String text;

  /// Leader line, dot and border color; defaults to the theme's axis color.
  final Color? color;

  /// Where the box sits relative to the point, in pixels (default: above).
  final Offset offset;

  const ChartAnnotation({required this.x, required this.y, required this.text, this.color, this.offset = const Offset(0, -36)});

  /// An annotation at [time] on a time axis or candlestick chart.
  ChartAnnotation.at(DateTime time, {required this.y, required this.text, this.color, this.offset = const Offset(0, -36)})
      : x = time.millisecondsSinceEpoch.toDouble();
}

/// Draws [ChartAnnotation]s; [project] maps an annotation's (x, y) to the
/// screen, or returns null when it's out of view.
void paintAnnotations(
  Canvas canvas,
  List<ChartAnnotation> annotations,
  Offset? Function(ChartAnnotation a) project,
  Rect bounds,
  ChartTheme theme,
) {
  for (final a in annotations) {
    final p = project(a);
    if (p == null || !bounds.inflate(1).contains(p)) continue;
    final color = a.color ?? theme.axisColor;
    final tp = layoutChartText(a.text, color: theme.tooltipTextColor, fontSize: 11, fontFamily: theme.fontFamily, maxWidth: 180);
    final w = tp.width + 12, h = tp.height + 8;
    // Centre the box on the offset point, kept inside the plot.
    final c = p + a.offset;
    final left = (c.dx - w / 2).clamp(bounds.left, math.max(bounds.left, bounds.right - w)).toDouble();
    final top = (c.dy - h / 2).clamp(bounds.top, math.max(bounds.top, bounds.bottom - h)).toDouble();
    final box = Rect.fromLTWH(left, top, w, h);
    // Leader from the point to the nearest point on the box's edge.
    final edge = Offset(p.dx.clamp(box.left, box.right), p.dy.clamp(box.top, box.bottom));
    canvas.drawLine(p, edge, Paint()
      ..color = color
      ..strokeWidth = 1);
    canvas.drawCircle(p, 3.5, Paint()..color = color);
    final rr = RRect.fromRectAndRadius(box, const Radius.circular(4));
    canvas.drawRRect(rr, Paint()..color = theme.tooltipBackgroundColor);
    canvas.drawRRect(rr, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color);
    tp.paint(canvas, box.topLeft + const Offset(6, 4));
  }
}
