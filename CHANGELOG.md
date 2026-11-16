# Changelog

## 0.2.0

### Added
- `WaterfallChart2D`: bridge charts with running totals (`WaterfallStep.total`), connectors
  and value labels.
- `BulletChart`: a measure against a target over qualitative bands, with comparative markers;
  horizontal or vertical.
- `CalendarHeatmap`: one cell per day in week columns (GitHub-style), stepped or continuous
  colors, month/weekday labels and a "Less … More" key.
- `SunburstChart2D`: hierarchies as rings using `TreemapNode`; tap to drill down, tap the
  centre to go back up.
- `PolarBarChart2D`: rose (Nightingale) charts with stacked series and area-proportional
  wedges, or radial bars.
- `RangeChart2D`: floating range bars, dumbbells, error bars and shaded bands (`RangeValue`).
- `BarChart2D.barStyle`: `BarStyle.lollipop`.
- `GanttChart2D`: grouped tasks with progress, milestones, dependency arrows and a today line;
  drag to scroll, pinch or wheel to zoom.
- Log scales: `LineChart2D.yAxisScale` and `ScatterChart2D.xAxisScale` / `yAxisScale`
  (`ChartAxisScale.logarithmic`), with power-of-ten ticks.
- 100% stacking: `BarChart2D.percentStacked` and `LineChart2D.percentStacked`; tooltips and
  callbacks report real values alongside shares.
- `ChartAnnotation`: callouts pinned to data points on line, scatter, bar, combo and
  candlestick charts.
- Data labels: `LineChart2D.showValueLabels` / `valueLabelFormatter` and
  `ScatterChart2D.showPointLabels`.
- `ChartCrosshairSync`: linked crosshairs across line, scatter, bar, combo and candlestick
  charts (`crosshairSync:`).
- `ChartController.toSvg()`: SVG export of any 2D chart.

- `NetworkGraph2D`: force-directed graph with groups, weighted and directed edges; drag nodes,
  pan and zoom; hover highlights neighbours.
- `ChordChart2D`: flows between groups as ribbons, with both directions in tooltips.
- `ParallelCoordinatesChart2D`: one axis per measure, brushing filters with
  `onSelectionChanged`, inverted axes, grouped legend.
- `ChoroplethMap2D` + `GeoFeature.parse`: maps shaded by value from your own GeoJSON (no
  bundled map data, no dependencies); Mercator or equirectangular, log color scale, pan/zoom.
- Options: `OptionPayoffChart2D` (expiry and today P&L, breakevens, max profit/loss, expected
  move), `OpenInterestChart2D` (calls vs puts per strike, spot, max pain, PCR, change view,
  sideways scroll), `MarketDepthChart2D` (cumulative order book) and `VolatilitySmileChart2D`.
- `OptionMath`: Black-Scholes prices and Greeks, implied volatility, strategy payoffs,
  breakevens, max profit/loss, max pain and expected move — pure Dart.
- `CandlestickChart2D.candleType`: Heikin-Ashi, Renko and line break (`CandleTransforms`).
- `CandlestickChart2D.volumeProfile`: volume at price with point of control and value area.
- Drawing tools on `CandlestickChart2D` via `ChartDrawingController`: trend line, ray,
  horizontal level, Fibonacci retracement and rectangle; select, move, reshape, delete, and
  save/restore as JSON.

### Improved
- Y-axis tick labels shrink to fit instead of overflowing the left margin (e.g. "10000").

## 0.1.0

### Breaking
- Requires Flutter 3.27+ / Dart 3.6+ (uses `Color.withValues`).
- `Surface3DChart.initialRotationX` now defaults to `0.6` (was `-0.6`). The old default
  viewed the surface from below, so higher values pointed down the screen.
- 3D projection is now a turntable camera: `rotationY` spins about the vertical axis, then
  `rotationX` tilts. Vertical lines stay vertical. `Surface3DChart.initialRotationY` now
  defaults to `-0.7`, which puts the axes' corner at the front.
- `Surface3DChart` now scales and centres itself to fill its box (`fitToSize: true`); with
  it, `initialZoom` is relative (16 fills the box). Pass `fitToSize: false` for the old scale.
- `LineChart2D.xTickFormatter` and `ScatterChart2D.xTickFormatter` are now nullable (null
  picks a numeric or date format to match `xAxisType`).
- When a `LineChart2D`'s or `BarChart2D`'s data changes, it now morphs to the new values and
  keeps zoom instead of replaying the entrance animation (set
  `updateAnimation: ChartUpdateAnimation.replay` for the old behavior).
- `ChartPoint`, `XySeries`, `CategorySeries` and `PieSlice` now compare by value (`==`), not
  identity.
- Default tick/tooltip number format now shows up to 2 decimals with trailing zeros trimmed
  (was 1 decimal).

### Added
- `LineChart2D`: `curve` (`LineChartCurve.straight` / `smooth` / `step`); smooth curves use
  monotone interpolation so they never overshoot the data.
- `LineChart2D`: `stacked` for stacked lines/areas; tooltips still report each point's own value.
- Time x-axis for `LineChart2D` and `ScatterChart2D`: `xAxisType: ChartAxisType.time` with
  `ChartPoint.at(DateTime, y: ...)`; ticks land on calendar boundaries.
- `BarChart2D`: `horizontal` layout and `showValueLabels` / `valueLabelFormatter`.
- `ComboChart2D`: bars and lines over shared categories, with an optional secondary y-axis
  and a shared per-category tooltip.
- `ChartReferenceLine` / `ChartReferenceBand` for line, scatter, bar and combo charts.
- `ChartController` for every 2D chart: `resetZoom()`, `isZoomed`, `toImage()`, `toPngBytes()`.
- `tooltipBuilder` on every 2D chart, and `legendPosition` (`top`, `bottom`, `left`, `right`, `none`).
- `CandlestickChart2D`, a trading chart: candles or OHLC bars, volume, a live last-traded-price
  line and axis tag that flashes on each tick, technical indicators (`MovingAverageIndicator`
  SMA/EMA, `BollingerBandsIndicator`, `VwapIndicator` on the price pane; `RsiIndicator` and
  `MacdIndicator` in their own panes), evenly spaced candles (no weekend/overnight gaps),
  right-hand price axis, OHLC header legend with an eye button per indicator to hide/show it
  (`showIndicatorToggles`, `onIndicatorVisibilityChanged`), trading-app navigation (drag to
  scroll through history with momentum, pinch or wheel to zoom, long-press crosshair on touch),
  `visibleCandles` to follow live data (at the user's zoom while the newest candle is in view),
  and the dark `ChartTheme.trading` look by default.
- `LiveCandles`: aggregates live trades into interval candles and tracks the last price.
- `ChartThemeScope.maybeOf` and `ChartTheme.trading`.
- New chart types: `HeatmapChart2D`, `RadarChart2D`, `GaugeChart` (arc or needle, animated), `Histogram2D`,
  `BoxPlot2D`, `FunnelChart2D`, `TreemapChart2D` (squarified, nested) and `SankeyChart2D`.
- `Sparkline`: a tiny axis-less line/bar trend for lists and KPI cards.
- `Bar3DChart` (3D bars on a category grid) and `Scatter3DChart` (three numeric axes,
  multiple series, optional drop lines), both with turntable rotation and zoom.
- `Surface3DChart`: `renderMode: SurfaceRenderMode.wireframe` and `showContours` /
  `contourLevels` (contour lines on the floor).
- 3D axes keep their labels on the floor edges facing the viewer as you rotate; the value
  axis stands at the back corner with nice tick values.
- `updateAnimation` on `LineChart2D` and `BarChart2D`: `ChartUpdateAnimation.morph` (default)
  animates values from old to new and keeps zoom; `.none` for streaming; `.replay` for the
  previous behavior.
- `LineChart2D.liveWindow`: follow the latest x-range for streaming data.
- `LineChart2D.downsample` (default on): LTTB downsampling for very long series.
- `fitProjector` for fitting any 3D model into a box, and `Projector.cameraDistance`.
- Screen-reader summaries for every chart (e.g. "Line chart, Revenue. Revenue: 12 values from
  80 to 210").
- pub.dev screenshots and a `tool/screenshots_test.dart` script that regenerates them.
- `HistogramBin.compute` (nice-width binning) and `BoxPlotStats.fromValues` (R-7 quartiles,
  1.5×IQR whiskers) are public.

### Fixed
- `HeatmapChart2D`, `Bar3DChart`, `Surface3DChart` and `Surface3DLegend` can be built with
  `const` (their constructors asserted on a list's length, which isn't allowed in const).
- `PieChart2D`: percentage labels now use the theme's `fontFamily`.
- `PieChart2D`: zero and negative slices are skipped instead of drawing invalid angles.
- Axis ranges always end exactly on a tick, and y-axis titles no longer overlap tick labels.
- `BarChart2D`: `RangeError` when hovering a series with fewer values than categories.
- `BarChart2D`: stacked negative values overflowed below the plot; xy-zoomed bars drew over the axes.
- `ScatterChart2D`: hover/tap now picks the nearest point instead of the last one in range.
- `ScatterChart2D`: tiny drags no longer zoom in x mode.
- `LineChart2D`: `filled: true` drew a wedge instead of filling down to the baseline; fill no
  longer spills below the axis when zoomed.
- Line/scatter: points outside the zoom window can no longer be hovered.
- All 2D charts: hover, tooltips and drag-zoom were offset when the legend wrapped to several rows.
- All 2D charts: rebuilding the parent with equal data no longer resets zoom or replays the
  animation. `ChartPoint`, `XySeries`, `CategorySeries` and `PieSlice` now compare by value.
- `Surface3DChart`: y-axis labels were in reverse row order; z-axis ticks now line up with the surface.
- `Surface3DChart`: large grids no longer distort at the near corner (the camera now backs
  off in proportion to the model's size).

### Improved
- Performance: hovering a line or scatter chart no longer repaints its data layer; scatter
  points are drawn in one batch per series; stacked line charts compute stacks in linear
  time (was quadratic).
- Axis ticks use "nice" steps (1/2/5 × 10ⁿ), and y-axes round out to them.
- X-axis labels are centred and skipped when they would overlap.
- `Surface3DChart`, `Surface3DLegend`, tooltips and reset buttons follow `ChartThemeScope`
  (dark mode now works for the 3D chart).
- Shared tooltip, reset button and drag-zoom code across all charts.
- Golden image tests for every chart in light and dark themes.

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
