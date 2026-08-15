import 'package:flutter/material.dart';

/// Central styling for all charts in the package — grid lines, axis text,
/// tooltips, titles. Data/series colors (what you pass to `XySeries`,
/// `CategorySeries`, `PieSlice`) are intentionally separate — the theme
/// controls chart *chrome*, not your data colors.
class ChartTheme {
  final Color backgroundColor;
  final Color gridColor;
  final Color axisColor;
  final Color tickTextColor;
  final Color titleColor;
  final Color subtitleColor;
  final Color tooltipBackgroundColor;
  final Color tooltipTextColor;
  final Color crosshairColor;
  final String? fontFamily;
  final double tickFontSize;
  final double titleFontSize;
  final double subtitleFontSize;

  const ChartTheme({
    this.backgroundColor = Colors.transparent,
    this.gridColor = const Color(0x30000000),
    this.axisColor = Colors.black87,
    this.tickTextColor = Colors.black54,
    this.titleColor = Colors.black87,
    this.subtitleColor = Colors.black54,
    this.tooltipBackgroundColor = Colors.white,
    this.tooltipTextColor = Colors.black87,
    this.crosshairColor = Colors.black38,
    this.fontFamily,
    this.tickFontSize = 10,
    this.titleFontSize = 16,
    this.subtitleFontSize = 12,
  });

  static const ChartTheme light = ChartTheme();

  static const ChartTheme dark = ChartTheme(
    gridColor: Color(0x33FFFFFF),
    axisColor: Colors.white70,
    tickTextColor: Colors.white60,
    titleColor: Colors.white,
    subtitleColor: Colors.white70,
    tooltipBackgroundColor: Color(0xFF2A2A2E),
    tooltipTextColor: Colors.white,
    crosshairColor: Colors.white38,
  );

  ChartTheme copyWith({
    Color? backgroundColor,
    Color? gridColor,
    Color? axisColor,
    Color? tickTextColor,
    Color? titleColor,
    Color? subtitleColor,
    Color? tooltipBackgroundColor,
    Color? tooltipTextColor,
    Color? crosshairColor,
    String? fontFamily,
    double? tickFontSize,
    double? titleFontSize,
    double? subtitleFontSize,
  }) {
    return ChartTheme(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      gridColor: gridColor ?? this.gridColor,
      axisColor: axisColor ?? this.axisColor,
      tickTextColor: tickTextColor ?? this.tickTextColor,
      titleColor: titleColor ?? this.titleColor,
      subtitleColor: subtitleColor ?? this.subtitleColor,
      tooltipBackgroundColor: tooltipBackgroundColor ?? this.tooltipBackgroundColor,
      tooltipTextColor: tooltipTextColor ?? this.tooltipTextColor,
      crosshairColor: crosshairColor ?? this.crosshairColor,
      fontFamily: fontFamily ?? this.fontFamily,
      tickFontSize: tickFontSize ?? this.tickFontSize,
      titleFontSize: titleFontSize ?? this.titleFontSize,
      subtitleFontSize: subtitleFontSize ?? this.subtitleFontSize,
    );
  }
}

/// Wrap any part of your app in this to apply a [ChartTheme] to every chart
/// beneath it. Charts fall back to [ChartTheme.light] if none is found.
///
/// ```dart
/// ChartThemeScope(
///   theme: ChartTheme.dark,
///   child: MaterialApp(...),
/// )
/// ```
class ChartThemeScope extends InheritedWidget {
  final ChartTheme theme;

  const ChartThemeScope({super.key, required this.theme, required super.child});

  static ChartTheme of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ChartThemeScope>();
    return scope?.theme ?? ChartTheme.light;
  }

  @override
  bool updateShouldNotify(ChartThemeScope oldWidget) => true;
}
