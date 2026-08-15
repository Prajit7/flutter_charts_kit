import 'package:flutter/material.dart';

/// A color-scale legend — a gradient bar with min/max (and optional
/// in-between) value labels. Works standalone, or embedded automatically
/// inside [Surface3DChart] via `showLegend: true`.
///
/// ```dart
/// Surface3DLegend(
///   gradient: [Colors.teal, Colors.amber, Colors.red],
///   min: 0,
///   max: 100,
///   valueFormatter: (v) => v.toStringAsFixed(0),
///   title: 'OI',
/// )
/// ```
class Surface3DLegend extends StatelessWidget {
  /// Color stops from low value to high value. Needs at least 2 colors.
  final List<Color> gradient;

  final double min;
  final double max;

  /// Formats a value for the tick labels.
  final String Function(double value) valueFormatter;

  /// Optional label shown above/beside the bar (e.g. the metric name).
  final String? title;

  final Axis orientation;

  /// Thickness of the gradient bar (perpendicular to its length).
  final double thickness;

  /// Length of the gradient bar along its main axis.
  final double length;

  /// How many intermediate ticks to show between min and max (in addition
  /// to min and max themselves). 0 shows just min/max.
  final int intermediateTicks;

  final TextStyle? labelStyle;
  final TextStyle? titleStyle;

  const Surface3DLegend({
    super.key,
    required this.gradient,
    required this.min,
    required this.max,
    required this.valueFormatter,
    this.title,
    this.orientation = Axis.vertical,
    this.thickness = 14,
    this.length = 160,
    this.intermediateTicks = 2,
    this.labelStyle,
    this.titleStyle,
  }) : assert(gradient.length >= 2, 'gradient needs at least 2 colors');

  @override
  Widget build(BuildContext context) {
    final isVertical = orientation == Axis.vertical;
    final resolvedLabelStyle =
        labelStyle ?? const TextStyle(fontSize: 10, color: Colors.black54);
    final resolvedTitleStyle = titleStyle ??
        const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87);

    // Build tick fractions from high to low for vertical (top = max),
    // low to high for horizontal (left = min).
    final tickCount = intermediateTicks + 2;
    final fractions = List<double>.generate(tickCount, (i) => i / (tickCount - 1));

    final bar = Container(
      width: isVertical ? thickness : length,
      height: isVertical ? length : thickness,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.black12, width: 0.5),
        gradient: LinearGradient(
          begin: isVertical ? Alignment.bottomCenter : Alignment.centerLeft,
          end: isVertical ? Alignment.topCenter : Alignment.centerRight,
          colors: gradient,
        ),
      ),
    );

    final ticks = fractions.map((f) {
      final value = min + f * (max - min);
      final label = Text(valueFormatter(value), style: resolvedLabelStyle);
      // vertical bar: max at top, so reverse the order label appears
      return label;
    }).toList();

    final orderedTicks = isVertical ? ticks.reversed.toList() : ticks;

    final barWithTicks = isVertical
        ? Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              bar,
              const SizedBox(width: 6),
              SizedBox(
                height: length,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: orderedTicks,
                ),
              ),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              bar,
              const SizedBox(height: 4),
              SizedBox(
                width: length,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: orderedTicks,
                ),
              ),
            ],
          );

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title!, style: resolvedTitleStyle),
            const SizedBox(height: 8),
          ],
          barWithTicks,
        ],
      ),
    );
  }
}
