# Changelog

## 0.6.1

- Fixed a crash in `BarChart2D`'s drag-to-zoom: dragging a selection that ended at or near the right edge of the plot could throw a `RangeError` (array index clamped to an invalid bound).
- Fixed the drag-to-zoom selection overlay showing as a thin sliver instead of a full-height band on x-only zoom (`LineChart2D`, `BarChart2D`, and `ScatterChart2D` when explicitly set to `ChartZoomMode.x`).
- Fixed `LineChart2D`'s y-axis staying anchored at zero even while zoomed, which made zooming into a narrow x-range look like it barely zoomed at all. Y now tightly fits the visible slice (with padding) once zoomed, and still anchors at zero for the default unzoomed view.

## 0.6.0

- Zoom is now available on every chart, adapted to what makes sense for each one:
  - `BarChart2D`: drag horizontally to zoom into a range of categories (y auto-rescales); `zoomMode: ChartZoomMode.xy` also zooms the dragged rectangle's y-range.
  - `PieChart2D`: no axes to drag-select, so it's pinch/scroll-to-zoom + drag-to-pan instead (like a photo viewer), with the same reset-button pattern.
  - `Surface3DChart`: single-finger drag still rotates; two-finger pinch now zooms (previously only desktop scroll-wheel could zoom — touch users had no way to zoom in).
- All zoom interactions across every chart share the same reset-button UX: it only appears while zoomed, and restores the exact original view.

## 0.5.0

- **Breaking (internal only, no API change):** all interaction state (hover, legend visibility, rotation/zoom, drag-zoom) across every chart — `Surface3DChart`, `LineChart2D`, `BarChart2D`, `PieChart2D`, `ScatterChart2D` — now lives in `ValueNotifier`s instead of `setState()`. Pointer movement now only repaints the canvas/tooltip subtree, not the legend or header.
- Added drag-to-zoom on `LineChart2D` (x-axis by default, y auto-rescales — `zoomMode: ChartZoomMode.x`) and `ScatterChart2D` (both axes by default — `zoomMode: ChartZoomMode.xy`). Drag a rectangle over the plot; a reset button appears while zoomed and restores the full view. Set `zoomMode: ChartZoomMode.none` to disable.
- `Surface3DChartState.zoom`/`rotationX`/`rotationY` are now getters (still readable the same way) backed by the new `Surface3DViewState`.
- Added widget tests covering empty states, legend toggling, and drag-to-zoom.

## 0.4.0

- Added `ChartTheme` + `ChartThemeScope`: central styling (grid, axis, tooltip, title colors and fonts) for all 2D charts, including a built-in `ChartTheme.dark`.
- Added `title`/`subtitle` props and a shared `ChartHeader` to `LineChart2D`, `BarChart2D`, `PieChart2D`, `ScatterChart2D`.
- Added automatic `ChartEmptyState` when a chart's data/series/slices are empty.
- Added entrance animations: line draw-in, bars growing from baseline, pie/donut radial grow-in, scatter pop-in. Controlled via `enableAnimation`/`animationDuration`, replays when series data changes.
- Added a crosshair (`showCrosshair`) on `LineChart2D` and `ScatterChart2D` that follows the hovered point.
- Added tap/hover callbacks: `onPointHover`/`onPointTap` (line, scatter), `onBarHover`/`onBarTap` (bar), `onSliceHover`/`onSliceTap` (pie).

## 0.3.0

- Added `LineChart2D` — multi-series, optional area fill, hover tooltips, toggleable legend.
- Added `BarChart2D` — grouped or stacked columns, multi-series, hover tooltips.
- Added `PieChart2D` — pie or donut (`innerRadiusRatio`), hover highlight + percentage labels.
- Added `ScatterChart2D` — multi-series scatter, optional per-point bubble sizing.
- Added shared `Chart2DLegend` (click-to-toggle series/slice visibility) and `Cartesian2DAxes` (shared axis/grid math for line/bar/scatter).
- New models: `ChartPoint`, `XySeries`, `CategorySeries`, `PieSlice`, `LegendEntry`.

## 0.2.0

- Added `Surface3DLegend`: a standalone color-scale legend (gradient bar + tick labels), usable on its own or embedded automatically in `Surface3DChart` via `showLegend: true`.
- New `Surface3DChart` params: `showLegend`, `legendAlignment`, `legendTitle`, `legendOrientation`.

## 0.1.0

- Initial release.
- `Surface3DChart` widget: drag-to-rotate, scroll/pinch-to-zoom, hover/tap tooltips.
- Calibrated color gradients via `fixedMin`/`fixedMax`, or auto-scaling from data.
- Optional vertical reference line (`referenceColIndex`/`referenceLabel`).
- `Surface3DChartController` for external reset control.
- Custom tooltip support via `tooltipBuilder`.
