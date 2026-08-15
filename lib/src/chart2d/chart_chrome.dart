import 'package:flutter/material.dart';
import 'theme.dart';

/// Title/subtitle shown above a chart. Renders nothing if both are empty,
/// so it's always safe to include even when you don't set either.
class ChartHeader extends StatelessWidget {
  final String? title;
  final String? subtitle;

  const ChartHeader({super.key, this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final hasTitle = title != null && title!.isNotEmpty;
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;
    if (!hasTitle && !hasSubtitle) return const SizedBox.shrink();

    final theme = ChartThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasTitle)
            Text(
              title!,
              style: TextStyle(
                fontSize: theme.titleFontSize,
                fontWeight: FontWeight.bold,
                color: theme.titleColor,
                fontFamily: theme.fontFamily,
              ),
            ),
          if (hasSubtitle)
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: theme.subtitleFontSize,
                color: theme.subtitleColor,
                fontFamily: theme.fontFamily,
              ),
            ),
        ],
      ),
    );
  }
}

/// Placeholder shown instead of the plot area when a chart has no data.
/// Every chart in the package renders this automatically when its
/// series/slices list is empty — you don't need to check for empty data
/// yourself before building the chart widget.
class ChartEmptyState extends StatelessWidget {
  final String message;

  const ChartEmptyState({super.key, this.message = 'No data to display'});

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.show_chart, size: 32, color: theme.tickTextColor),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(color: theme.subtitleColor, fontSize: 13, fontFamily: theme.fontFamily),
          ),
        ],
      ),
    );
  }
}
