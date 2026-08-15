# Changelog

## 0.0.1

- **Initial release** of `flutter_charts_kit`.
- Added `Surface3DChart` with drag-to-rotate, scroll/pinch-to-zoom, hover/tap tooltips, and calibrated color gradients.
- Added automatic color scaling from chart data, with optional `fixedMin`/`fixedMax` bounds.
- Added optional vertical reference line using `referenceColIndex` and `referenceLabel`.
- Added `Surface3DChartController` for external reset control.
- Added custom tooltip support through `tooltipBuilder`.
- Added `Surface3DLegend`: a standalone color-scale legend with gradient bar and tick labels.
- Added configurable surface chart legend options:
  - `showLegend`
  - `legendAlignment`
  - `legendTitle`
  - `legendOrientation`
- Added `LineChart2D` with multi-series support, optional area fill, hover tooltips, and toggleable legend.
- Added `BarChart2D` with grouped or stacked columns, multi-series support, and hover tooltips.
- Added `PieChart2D` with pie/donut modes, hover highlighting, and percentage labels.
- Added `ScatterChart2D` with multi-series support and optional per-point bubble sizing.
- Added shared `Chart2DLegend` and `Cartesian2DAxes` components.
- Added chart models including `ChartPoint`, `XySeries`, `CategorySeries`, `PieSlice`, and `LegendEntry`.
- Added `ChartTheme` and `ChartThemeScope` for centralized chart styling, including the built-in `ChartTheme.dark`.
- Added `title` and `subtitle` support with the shared `ChartHeader`.
- Added automatic `ChartEmptyState` for empty chart data.
- Added entrance animations for line, bar, pie/donut, and scatter charts.
- Added crosshair support for `LineChart2D` and `ScatterChart2D`.
- Added tap and hover callbacks for line, scatter, bar, and pie charts.
- Added zoom interactions across supported charts:
  - `BarChart2D`: horizontal category zoom with automatic Y-axis rescaling.
  - `LineChart2D`: X-axis zoom with automatic Y-axis rescaling.
  - `ScatterChart2D`: XY drag-to-zoom.
  - `PieChart2D`: pinch/scroll-to-zoom and drag-to-pan.
  - `Surface3DChart`: two-finger pinch-to-zoom on touch devices.
- Added a consistent reset-button UX for zoomed charts.
- **Performance improvement:** moved chart interaction state to `ValueNotifier`s instead of `setState()`, reducing unnecessary widget rebuilds during pointer interaction.
- Added widget tests covering empty states, legend toggling, and drag-to-zoom.
- Fixed a `RangeError` in `BarChart2D` drag-to-zoom when a selection ended at or near the right edge of the plot.
- Fixed the x-only drag-to-zoom selection overlay appearing as a thin sliver instead of a full-height selection band.
- Fixed `LineChart2D` Y-axis scaling while zoomed so the visible data range is tightly fitted with padding.
