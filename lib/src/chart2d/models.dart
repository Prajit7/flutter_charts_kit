import 'package:flutter/material.dart';

/// A single (x, y) data point, used by [XySeries] for line/scatter charts.
class ChartPoint {
  final double x;
  final double y;

  /// Optional label shown in tooltips (e.g. a date string) instead of the
  /// raw numeric x value.
  final String? label;

  /// Optional size, used by scatter charts to render bubbles instead of
  /// fixed-radius points.
  final double? size;

  const ChartPoint({required this.x, required this.y, this.label, this.size});
}

/// A named, colored series of (x, y) points — used by [LineChart2D] and
/// [ScatterChart2D].
class XySeries {
  final String name;
  final Color color;
  final List<ChartPoint> data;

  const XySeries({required this.name, required this.color, required this.data});
}

/// A named, colored series of values aligned 1:1 with a shared list of
/// category labels — used by [BarChart2D].
class CategorySeries {
  final String name;
  final Color color;
  final List<double> values;

  const CategorySeries({required this.name, required this.color, required this.values});
}

/// One slice of a [PieChart2D] / donut chart.
class PieSlice {
  final String label;
  final double value;
  final Color color;

  const PieSlice({required this.label, required this.value, required this.color});
}

/// A generic (label, color) pair rendered by [Chart2DLegend].
class LegendEntry {
  final String label;
  final Color color;

  const LegendEntry({required this.label, required this.color});
}

/// Fired by [LineChart2D] / [ScatterChart2D] on tap or hover.
/// Called with `(null, null)` when the pointer moves off every point.
typedef ChartPointCallback = void Function(String? seriesName, ChartPoint? point);

/// Fired by [BarChart2D] on tap or hover. Called with `(null, null, null)`
/// when the pointer moves off every bar.
typedef ChartBarCallback = void Function(String? seriesName, String? category, double? value);

/// Fired by [PieChart2D] on tap or hover. Called with `null` when the
/// pointer moves off every slice.
typedef ChartSliceCallback = void Function(PieSlice? slice);
