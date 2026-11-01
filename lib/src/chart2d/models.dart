import 'package:flutter/foundation.dart';
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

  /// A point on a time x-axis: [x] is [time] in milliseconds since epoch.
  /// Use with `xAxisType: ChartAxisType.time` on the chart.
  ChartPoint.at(DateTime time, {required this.y, this.label, this.size}) : x = time.millisecondsSinceEpoch.toDouble();

  /// [x] read back as a [DateTime] (meaningful for points made with [ChartPoint.at]).
  DateTime get time => DateTime.fromMillisecondsSinceEpoch(x.round());

  @override
  bool operator ==(Object other) =>
      other is ChartPoint && other.x == x && other.y == y && other.label == label && other.size == size;

  @override
  int get hashCode => Object.hash(x, y, label, size);
}

/// A named, colored series of (x, y) points — used by [LineChart2D] and
/// [ScatterChart2D].
class XySeries {
  final String name;
  final Color color;
  final List<ChartPoint> data;

  const XySeries({required this.name, required this.color, required this.data});

  @override
  bool operator ==(Object other) =>
      other is XySeries && other.name == name && other.color == color && listEquals(other.data, data);

  @override
  int get hashCode => Object.hash(name, color, Object.hashAll(data));
}

/// A named, colored series of values aligned 1:1 with a shared list of
/// category labels — used by [BarChart2D].
class CategorySeries {
  final String name;
  final Color color;
  final List<double> values;

  const CategorySeries({required this.name, required this.color, required this.values});

  @override
  bool operator ==(Object other) =>
      other is CategorySeries && other.name == name && other.color == color && listEquals(other.values, values);

  @override
  int get hashCode => Object.hash(name, color, Object.hashAll(values));
}

/// One slice of a [PieChart2D] / donut chart.
class PieSlice {
  final String label;
  final double value;
  final Color color;

  const PieSlice({required this.label, required this.value, required this.color});

  @override
  bool operator ==(Object other) =>
      other is PieSlice && other.label == label && other.value == value && other.color == color;

  @override
  int get hashCode => Object.hash(label, value, color);
}

/// What a chart does when its data changes after the first build.
enum ChartUpdateAnimation {
  /// Animate each value from where it was to where it is now (when the
  /// series keeps its name and point count; otherwise update instantly).
  /// Zoom is kept.
  morph,

  /// Replay the entrance animation and reset zoom — the pre-0.1 behavior.
  replay,

  /// Update instantly and keep zoom — best for streaming data.
  none,
}

/// How a chart interprets [ChartPoint.x].
enum ChartAxisType {
  /// Plain numbers.
  numeric,

  /// Milliseconds since epoch (see [ChartPoint.at]) — ticks fall on calendar
  /// boundaries and are labelled as dates/times.
  time,
}

/// Builds a custom tooltip for a hovered/tapped point in [LineChart2D] or
/// [ScatterChart2D].
typedef ChartPointTooltipBuilder = Widget Function(BuildContext context, String series, ChartPoint point);

/// Builds a custom tooltip for a hovered/tapped bar in [BarChart2D].
typedef ChartBarTooltipBuilder = Widget Function(BuildContext context, String series, String category, double value);

/// Builds a custom tooltip for a hovered/tapped slice in [PieChart2D].
/// [percent] is the slice's share of the visible total, 0–100.
typedef ChartSliceTooltipBuilder = Widget Function(BuildContext context, PieSlice slice, double percent);

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
