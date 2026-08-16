# Changelog

## 0.0.4

- Updated the example application to showcase both 2D and 3D charts in a unified demo with images.


## 0.0.3

- Updated the example application to showcase both 2D and 3D charts in a unified demo.
- Added tab-based navigation between the 2D chart collection and `Surface3DChart`.
- Added a combined 2D charts showcase including:
  - `LineChart2D`
  - `BarChart2D` (grouped and stacked)
  - `PieChart2D`
  - `PieChart2D` donut mode
  - `ScatterChart2D`
- Added a dedicated `Surface3DChart` example with sample region/month sales data.
- Added light/dark theme switching to the example application.
- Updated the example application branding to `Flutter Charts Kit`.
- Renamed the package from `surface_3d_chart` to `flutter_charts_kit`.
- Updated package imports and example references to use `flutter_charts_kit`.
- Updated the example configuration to enable Material Design icons.
- Improved the example app layout to make the available 2D and 3D chart types easier to discover.

## 0.0.2

- Added zoom interactions across all supported chart types.
- Added drag-to-zoom support for `LineChart2D`.
- Added horizontal category zoom support for `BarChart2D`.
- Added XY drag-to-zoom support for `ScatterChart2D`.
- Added pinch/scroll-to-zoom and drag-to-pan support for `PieChart2D`.
- Added two-finger pinch-to-zoom support for `Surface3DChart` on touch devices.
- Added a consistent reset-button experience for zoomed charts.
- Improved `LineChart2D` Y-axis scaling while zoomed so the visible data range is fitted with padding.
- Fixed a `RangeError` in `BarChart2D` drag-to-zoom when the selection ended at or near the right edge of the plot.
- Fixed the x-only drag-to-zoom selection overlay appearing as a thin sliver instead of a full-height selection band.
- Improved chart interaction performance by moving interaction state to `ValueNotifier`s instead of `setState()`.
- Added widget tests covering empty states, legend toggling, and drag-to-zoom.

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
