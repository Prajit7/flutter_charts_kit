import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../legend.dart';
import 'cartesian_axes.dart';
import 'theme.dart';
import 'chart_chrome.dart';
import 'common.dart';
import 'controller.dart';
import 'hover_plot.dart';

/// One hovered/tapped heatmap cell.
class HeatmapCell {
  final int row;
  final int col;
  final double value;
  final String xLabel;
  final String yLabel;

  const HeatmapCell({required this.row, required this.col, required this.value, required this.xLabel, required this.yLabel});

  @override
  bool operator ==(Object other) => other is HeatmapCell && other.row == row && other.col == col;

  @override
  int get hashCode => Object.hash(row, col);
}

/// A grid of colored cells — the flat 2D view of the same `data[row][col]`
/// grid [Surface3DChart] takes. Good for activity calendars, correlation
/// matrices, hour-by-day usage, and so on.
///
/// ```dart
/// HeatmapChart2D(
///   data: [
///     [3, 7, null, 2],   // row 0 ("Mon"); null = no data
///     [5, 1, 8, 4],      // row 1 ("Tue")
///   ],
///   xLabels: ['9am', '10am', '11am', '12pm'],
///   yLabels: ['Mon', 'Tue'],
///   gradient: [Colors.blue.shade50, Colors.blue.shade900],
///   showValues: true,
/// )
/// ```
class HeatmapChart2D extends StatefulWidget {
  /// `data[row][col]`; null marks a missing value, drawn as an empty cell.
  final List<List<double?>> data;

  /// One label per column (left to right).
  final List<String> xLabels;

  /// One label per row (top to bottom).
  final List<String> yLabels;

  /// Color stops from the lowest to the highest value.
  final List<Color> gradient;

  /// Pin the color scale instead of using the data's min/max, so colors
  /// stay comparable across refreshes.
  final double? fixedMin;
  final double? fixedMax;

  final String? title;
  final String? subtitle;
  final String? xAxisTitle;
  final String? yAxisTitle;
  final String emptyStateMessage;
  final String Function(double value) valueFormatter;

  /// Print each value inside its cell (skipped where it doesn't fit).
  final bool showValues;

  /// Gap between cells, in pixels.
  final double cellGap;

  /// Shows a gradient color-scale legend.
  final bool showLegend;

  /// Only [ChartLegendPosition.right], [ChartLegendPosition.left],
  /// [ChartLegendPosition.bottom], [ChartLegendPosition.top] and
  /// [ChartLegendPosition.none] apply.
  final ChartLegendPosition legendPosition;

  /// Label above the legend's gradient bar.
  final String? legendTitle;

  final bool enableAnimation;
  final Duration animationDuration;

  /// Replaces the default tooltip card.
  final Widget Function(BuildContext context, HeatmapCell cell)? tooltipBuilder;

  /// Export an image from outside the chart.
  final ChartController? controller;

  final ValueChanged<HeatmapCell?>? onCellHover;
  final ValueChanged<HeatmapCell>? onCellTap;

  const HeatmapChart2D({
    super.key,
    required this.data,
    required this.xLabels,
    required this.yLabels,
    this.gradient = const [Color(0xFFE3F2FD), Color(0xFF1565C0)],
    this.fixedMin,
    this.fixedMax,
    this.title,
    this.subtitle,
    this.xAxisTitle,
    this.yAxisTitle,
    this.emptyStateMessage = 'No data to display',
    this.valueFormatter = Cartesian2DAxes.formatNumber,
    this.showValues = false,
    this.cellGap = 1,
    this.showLegend = true,
    this.legendPosition = ChartLegendPosition.right,
    this.legendTitle,
    this.enableAnimation = true,
    this.animationDuration = const Duration(milliseconds: 500),
    this.tooltipBuilder,
    this.controller,
    this.onCellHover,
    this.onCellTap,
  });

  @override
  State<HeatmapChart2D> createState() => _HeatmapChart2DState();
}

class _HeatmapLayout {
  final Rect grid;
  final int rows;
  final int cols;

  _HeatmapLayout(this.grid, this.rows, this.cols);

  double get cellWidth => grid.width / cols;
  double get cellHeight => grid.height / rows;

  Rect cell(int r, int c) => Rect.fromLTWH(grid.left + c * cellWidth, grid.top + r * cellHeight, cellWidth, cellHeight);

  (int, int)? cellAt(Offset pos) {
    if (!grid.contains(pos)) return null;
    final c = ((pos.dx - grid.left) / cellWidth).floor().clamp(0, cols - 1);
    final r = ((pos.dy - grid.top) / cellHeight).floor().clamp(0, rows - 1);
    return (r, c);
  }
}

class _HeatmapChart2DState extends State<HeatmapChart2D> with ChartControllerMixin<HeatmapChart2D> {
  @override
  ChartController? controllerOf(HeatmapChart2D widget) => widget.controller;

  @override
  void resetZoom() {} // no zoom on this chart

  int get _rows => widget.data.length;
  int get _cols => widget.data.fold(0, (m, row) => math.max(m, row.length));

  (double, double) get _range {
    if (widget.fixedMin != null && widget.fixedMax != null) return (widget.fixedMin!, widget.fixedMax!);
    double lo = double.infinity, hi = -double.infinity;
    for (final row in widget.data) {
      for (final v in row) {
        if (v == null) continue;
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
    if (lo.isInfinite) return (0, 1);
    return (widget.fixedMin ?? lo, widget.fixedMax ?? hi);
  }

  _HeatmapLayout _layout(Size size, ChartTheme theme) {
    double widest = 0;
    for (final label in widget.yLabels) {
      widest = math.max(widest, layoutChartText(label, color: theme.tickTextColor, fontSize: theme.tickFontSize).width);
    }
    final leftPad = math.min(widest + 10, size.width / 3) + (widget.yAxisTitle != null ? 18 : 0);
    final bottomPad = 24.0 + (widget.xAxisTitle != null ? 18 : 0);
    return _HeatmapLayout(
      Rect.fromLTRB(leftPad, 4, math.max(leftPad, size.width - 4), math.max(4, size.height - bottomPad)),
      _rows,
      _cols,
    );
  }

  HeatmapCell? _cellFor(int r, int c) {
    final row = widget.data[r];
    final v = c < row.length ? row[c] : null;
    if (v == null) return null;
    return HeatmapCell(
      row: r,
      col: c,
      value: v,
      xLabel: c < widget.xLabels.length ? widget.xLabels[c] : '',
      yLabel: r < widget.yLabels.length ? widget.yLabels[r] : '',
    );
  }

  @override
  Widget build(BuildContext context) {
    // Checked here, not in the constructor, so `const HeatmapChart2D(...)` compiles.
    assert(widget.gradient.length >= 2, 'gradient needs at least 2 colors');
    final theme = ChartThemeScope.of(context);
    final empty = _rows == 0 || _cols == 0 || widget.data.every((row) => row.every((v) => v == null));
    if (empty) {
      return ChartFrame(
        boundaryKey: chartBoundaryKey,
        title: widget.title,
        subtitle: widget.subtitle,
        plot: ChartEmptyState(message: widget.emptyStateMessage),
      );
    }

    final (lo, hi) = _range;
    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Heatmap', widget.title, ['$_rows rows by $_cols columns', 'values from ${widget.valueFormatter(lo)} to ${widget.valueFormatter(hi)}']),
      title: widget.title,
      subtitle: widget.subtitle,
      legendPosition: widget.legendPosition,
      legendBuilder: widget.showLegend
          ? (direction) => Surface3DLegend(
                gradient: widget.gradient,
                min: lo,
                max: hi,
                valueFormatter: widget.valueFormatter,
                title: widget.legendTitle,
                orientation: direction == Axis.horizontal ? Axis.horizontal : Axis.vertical,
                length: direction == Axis.horizontal ? 200 : 140,
              )
          : null,
      plot: HoverPlot<HeatmapCell>(
        enableAnimation: widget.enableAnimation,
        animationDuration: widget.animationDuration,
        animationKey: Object.hashAll([for (final row in widget.data) Object.hashAll(row)]),
        hitTest: (pos, size) {
          final rc = _layout(size, theme).cellAt(pos);
          return rc == null ? null : _cellFor(rc.$1, rc.$2);
        },
        onHover: widget.onCellHover,
        onTap: widget.onCellTap,
        painterBuilder: (size, hover, progress) => _HeatmapPainter(
          layout: _layout(size, theme),
          data: widget.data,
          xLabels: widget.xLabels,
          yLabels: widget.yLabels,
          xAxisTitle: widget.xAxisTitle,
          yAxisTitle: widget.yAxisTitle,
          gradient: widget.gradient,
          min: lo,
          max: hi,
          valueFormatter: widget.showValues ? widget.valueFormatter : null,
          gap: widget.cellGap,
          theme: theme,
          hover: hover,
          progress: progress,
        ),
        tooltipBuilder: (context, cell, pointer, size) {
          final rect = _layout(size, theme).cell(cell.row, cell.col);
          final custom = widget.tooltipBuilder;
          return positionChartTooltip(
            anchor: Offset(rect.right, rect.center.dy),
            areaSize: size,
            child: custom != null
                ? custom(context, cell)
                : ChartTooltipCard(
                    theme: theme,
                    width: 150,
                    title: [cell.yLabel, cell.xLabel].where((s) => s.isNotEmpty).join(' · '),
                    value: widget.valueFormatter(cell.value),
                  ),
          );
        },
      ),
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  final _HeatmapLayout layout;
  final List<List<double?>> data;
  final List<String> xLabels;
  final List<String> yLabels;
  final String? xAxisTitle;
  final String? yAxisTitle;
  final List<Color> gradient;
  final double min;
  final double max;
  final String Function(double)? valueFormatter;
  final double gap;
  final ChartTheme theme;
  final HeatmapCell? hover;
  final double progress;

  _HeatmapPainter({
    required this.layout,
    required this.data,
    required this.xLabels,
    required this.yLabels,
    required this.xAxisTitle,
    required this.yAxisTitle,
    required this.gradient,
    required this.min,
    required this.max,
    required this.valueFormatter,
    required this.gap,
    required this.theme,
    required this.hover,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final grid = layout.grid;
    final emptyPaint = Paint()..color = theme.gridColor.withValues(alpha: 0.25);

    for (int r = 0; r < layout.rows; r++) {
      for (int c = 0; c < layout.cols; c++) {
        final rect = layout.cell(r, c).deflate(gap / 2);
        final row = data[r];
        final v = c < row.length ? row[c] : null;
        if (v == null) {
          canvas.drawRect(rect, emptyPaint);
          continue;
        }
        final t = max == min ? 0.5 : (v - min) / (max - min);
        final color = sampleGradient(gradient, t);
        // Entrance: cells fade in, staggered left-to-right.
        final cellProgress = ((progress * (layout.cols + 4) - c) / 4).clamp(0.0, 1.0);
        canvas.drawRect(rect, Paint()..color = color.withValues(alpha: color.a * cellProgress));

        if (valueFormatter != null && cellProgress >= 1) {
          final tp = layoutChartText(valueFormatter!(v),
              color: contrastingTextColor(color), fontSize: theme.tickFontSize, fontFamily: theme.fontFamily);
          if (tp.width + 4 <= rect.width && tp.height + 2 <= rect.height) {
            tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
          }
        }
      }
    }

    if (hover != null) {
      canvas.drawRect(
        layout.cell(hover!.row, hover!.col).deflate(gap / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = theme.axisColor,
      );
    }

    // Row labels, right-aligned against the grid; every n-th when rows are thin.
    final rowLabels = [for (final l in yLabels.take(layout.rows)) layoutChartText(l, color: theme.tickTextColor, fontSize: theme.tickFontSize, fontFamily: theme.fontFamily, maxWidth: math.max(1, grid.left - 8 - (yAxisTitle != null ? 18 : 0)))];
    if (rowLabels.isNotEmpty) {
      final stride = math.max(1, (rowLabels.first.height / layout.cellHeight).ceil());
      for (int r = 0; r < rowLabels.length; r += stride) {
        final tp = rowLabels[r];
        tp.paint(canvas, Offset(grid.left - 6 - tp.width, layout.cell(r, 0).center.dy - tp.height / 2));
      }
    }

    // Column labels, centred and thinned to avoid overlap.
    final axes = Cartesian2DAxes(
      plotArea: Rect.fromLTRB(grid.left, grid.top, grid.right, grid.bottom - 4),
      minX: 0,
      maxX: 1,
      minY: 0,
      maxY: 1,
      theme: theme,
    );
    axes.drawXTicks(canvas, [
      for (int c = 0; c < math.min(layout.cols, xLabels.length); c++) (layout.cell(0, c).center.dx, xLabels[c]),
    ]);

    if (xAxisTitle != null) {
      final tp = layoutChartText(xAxisTitle!, color: theme.axisColor, fontSize: 12, fontFamily: theme.fontFamily);
      tp.paint(canvas, Offset(grid.center.dx - tp.width / 2, grid.bottom + 24));
    }
    if (yAxisTitle != null) {
      final tp = layoutChartText(yAxisTitle!, color: theme.axisColor, fontSize: 12, fontFamily: theme.fontFamily);
      canvas.save();
      canvas.translate(0, grid.center.dy + tp.width / 2);
      canvas.rotate(-math.pi / 2);
      tp.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter old) => true;
}
