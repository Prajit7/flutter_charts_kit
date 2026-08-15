import 'package:flutter/material.dart';
import 'theme.dart';

/// Maps data-space values to canvas pixels for a simple 2D Cartesian plot,
/// and draws the shared axis lines, gridlines, and tick labels. Shared by
/// [LineChart2D], [BarChart2D], and [ScatterChart2D] painters so the three
/// chart types look visually consistent.
class Cartesian2DAxes {
  final Rect plotArea; // the area inside the axes, in canvas pixels
  final double minX, maxX, minY, maxY;
  final ChartTheme theme;

  Cartesian2DAxes({
    required this.plotArea,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    this.theme = ChartTheme.light,
  });

  double toScreenX(double x) {
    final t = maxX == minX ? 0.5 : (x - minX) / (maxX - minX);
    return plotArea.left + t * plotArea.width;
  }

  double toScreenY(double y) {
    final t = maxY == minY ? 0.5 : (y - minY) / (maxY - minY);
    // screen y grows downward, data y grows upward
    return plotArea.bottom - t * plotArea.height;
  }

  /// Inverse of [toScreenX] — converts a canvas x-coordinate back to data
  /// space. Used to turn a drag-selection rectangle into a zoom window.
  double toDataX(double screenX) {
    final t = plotArea.width == 0 ? 0.0 : (screenX - plotArea.left) / plotArea.width;
    return minX + t * (maxX - minX);
  }

  /// Inverse of [toScreenY].
  double toDataY(double screenY) {
    final t = plotArea.height == 0 ? 0.0 : (plotArea.bottom - screenY) / plotArea.height;
    return minY + t * (maxY - minY);
  }

  /// Standard left/bottom padding reserved for axis titles + tick labels.
  static Rect computePlotArea(Size size, {bool categoricalX = false}) {
    const leftPad = 48.0;
    const bottomPad = 44.0;
    const topPad = 12.0;
    const rightPad = 12.0;
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
      ..color = theme.axisColor.withOpacity(0.5)
      ..strokeWidth = 1;

    // Y gridlines + ticks
    for (final yv in yTicks) {
      final y = toScreenY(yv);
      if (showGrid) {
        canvas.drawLine(Offset(plotArea.left, y), Offset(plotArea.right, y), gridPaint);
      }
      canvas.drawLine(Offset(plotArea.left - 4, y), Offset(plotArea.left, y), tickPaint);
      _drawText(canvas, yFormatter(yv), Offset(plotArea.left - 44, y - 6), theme.tickTextColor, size: theme.tickFontSize);
    }

    // Axis lines
    canvas.drawLine(plotArea.bottomLeft, plotArea.topLeft, axisPaint);
    canvas.drawLine(plotArea.bottomLeft, plotArea.bottomRight, axisPaint);

    if (yAxisTitle != null) {
      canvas.save();
      canvas.translate(12, plotArea.center.dy + 30);
      canvas.rotate(-1.5708); // -90deg
      _drawText(canvas, yAxisTitle, Offset.zero, theme.axisColor, size: 12);
      canvas.restore();
    }
    if (xAxisTitle != null) {
      _drawText(
        canvas,
        xAxisTitle,
        Offset(plotArea.center.dx - 20, plotArea.bottom + 26),
        theme.axisColor,
        size: 12,
      );
    }
  }

  void drawXTick(Canvas canvas, double screenX, String label) {
    final tickPaint = Paint()
      ..color = theme.axisColor.withOpacity(0.5)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(screenX, plotArea.bottom),
      Offset(screenX, plotArea.bottom + 4),
      tickPaint,
    );
    _drawText(canvas, label, Offset(screenX - 14, plotArea.bottom + 8), theme.tickTextColor, size: theme.tickFontSize);
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

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
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

  static List<double> niceTicks(double min, double max, {int count = 5}) {
    if (min == max) return [min];
    final step = (max - min) / count;
    return List.generate(count + 1, (i) => min + step * i);
  }

  void _drawText(Canvas canvas, String text, Offset position, Color color, {double size = 12}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w600, fontFamily: theme.fontFamily)),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    painter.paint(canvas, position);
  }
}
