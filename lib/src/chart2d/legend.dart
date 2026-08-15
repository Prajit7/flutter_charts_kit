import 'package:flutter/material.dart';
import 'models.dart';
import 'theme.dart';

/// A row of tappable (color swatch + label) chips. Tapping a chip toggles
/// that series/slice's visibility — the classic Highcharts legend behavior.
///
/// Used internally by [LineChart2D], [BarChart2D], [PieChart2D], and
/// [ScatterChart2D] when `showLegend: true`, but also exported for custom
/// placement.
class Chart2DLegend extends StatelessWidget {
  final List<LegendEntry> entries;
  final Set<String> hidden;
  final ValueChanged<String>? onToggle;
  final Axis direction;

  const Chart2DLegend({
    super.key,
    required this.entries,
    this.hidden = const {},
    this.onToggle,
    this.direction = Axis.horizontal,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    final chips = entries.map((e) {
      final isHidden = hidden.contains(e.label);
      return InkWell(
        onTap: onToggle == null ? null : () => onToggle!(e.label),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isHidden ? theme.tickTextColor.withOpacity(0.3) : e.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                e.label,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: theme.fontFamily,
                  color: isHidden ? theme.tickTextColor.withOpacity(0.5) : theme.axisColor,
                  decoration: isHidden ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();

    return direction == Axis.horizontal
        ? Wrap(spacing: 4, runSpacing: 2, children: chips)
        : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: chips);
  }
}
