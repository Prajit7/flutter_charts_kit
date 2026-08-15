# flutter_charts_kit

A generic, interactive 3D surface chart for Flutter. Rotate by dragging,
zoom by scrolling/pinching, hover or tap any tile for a tooltip. It knows
nothing about your data's meaning — feed it a `data[row][col]` grid, axis
labels, a color gradient, and a value formatter.

## Install

Local package (not yet published):

```yaml
dependencies:
  flutter_charts_kit:
    path: ../flutter_charts_kit
```

## Usage

```dart
import 'package:flutter_charts_kit/flutter_charts_kit.dart';

Surface3DChart(
  data: [
    [10, 40, 90],   // row 0 (e.g. "Jan")
    [15, 55, 120],  // row 1 (e.g. "Feb")
    [20, 70, 160],  // row 2 (e.g. "Mar")
  ],
  xLabels: ['North', 'South', 'East'],
  yLabels: ['Jan', 'Feb', 'Mar'],
  xAxisTitle: 'Region',
  yAxisTitle: 'Month',
  zAxisTitle: 'Revenue',
  valueFormatter: (v) => '\$${v.toStringAsFixed(0)}',
  gradient: [Colors.teal, Colors.amber, Colors.red],
)
```

### Stable colors across live/refreshed data

By default the gradient auto-scales to the min/max of whatever is in
`data` right now. If you're polling an API and want the same color to
always mean the same value (recommended for anything users compare over
time), pin the scale instead:

```dart
Surface3DChart(
  ...,
  fixedMin: 0,
  fixedMax: 100,
)
```

### Reference line

Draw a vertical dashed marker through a specific column (e.g. "today",
"current price"):

```dart
Surface3DChart(
  ...,
  referenceColIndex: 4,
  referenceLabel: 'Spot (24675)',
)
```

### Legend

Turn on the built-in color-scale legend:

```dart
Surface3DChart(
  ...,
  showLegend: true,
  legendAlignment: Alignment.bottomLeft, // any corner
)
```

Or place it yourself anywhere in your layout using the standalone widget
(e.g. outside the chart, in a sidebar):

```dart
Surface3DLegend(
  gradient: [Colors.teal, Colors.amber, Colors.red],
  min: 0,
  max: 100,
  valueFormatter: (v) => v.toStringAsFixed(0),
  title: 'OI',
  orientation: Axis.horizontal, // or Axis.vertical
)
```

### External reset control

```dart
final controller = Surface3DChartController();

Surface3DChart(controller: controller, ...);

ElevatedButton(onPressed: controller.resetView, child: Text('Reset view'));
```

### Custom tooltip

```dart
Surface3DChart(
  ...,
  tooltipBuilder: (context, hit) => Card(
    child: Text('${hit.xLabel} / ${hit.yLabel}: ${hit.value}'),
  ),
)
```

## Example

`example/lib/simple_3d_demo.dart` — hardcoded data, no networking, ~40
lines. Run with `flutter run -t lib/simple_3d_demo.dart`.

`example/lib/charts_2d_demo.dart` — all four 2D chart types (line, bar,
pie/donut, scatter) with theming, titles, and drag-to-zoom.

## What's generic vs. what's app-specific

| Generic (package)              | App-specific (your code)                  |
|---------------------------------|--------------------------------------------|
| Rotation, zoom, projection       | What rows/columns represent                |
| Hit-testing & tooltip plumbing   | Networking, JSON parsing, polling           |
| Color gradient math              | Which colors, which fixed min/max           |
| Axis drawing                     | Axis titles, label text, formatting         |
| Reset button / controller        | Any extra app UI (tabs, refresh button)     |

## 2D chart types

Beyond the 3D surface, the package also includes four standard 2D chart
types, all sharing the same series-based API and a toggleable legend
(tap a legend entry to hide/show that series or slice — like Highcharts).

```dart
// Line chart, optionally filled
LineChart2D(
  series: [
    XySeries(name: 'Revenue', color: Colors.indigo, data: [
      ChartPoint(x: 1, y: 120, label: 'Jan'),
      ChartPoint(x: 2, y: 180, label: 'Feb'),
    ]),
  ],
  filled: true,
  xAxisTitle: 'Month',
  yAxisTitle: 'USD',
)

// Bar chart, grouped or stacked
BarChart2D(
  categories: ['Q1', 'Q2', 'Q3'],
  series: [
    CategorySeries(name: 'North', color: Colors.teal, values: [40, 55, 48]),
    CategorySeries(name: 'South', color: Colors.amber, values: [30, 35, 42]),
  ],
  stacked: true, // or false for grouped
)

// Pie or donut
PieChart2D(
  innerRadiusRatio: 0.6, // 0 for a solid pie
  slices: [
    PieSlice(label: 'Chrome', value: 64, color: Colors.blue),
    PieSlice(label: 'Safari', value: 19, color: Colors.orange),
  ],
)

// Scatter, or bubble chart if ChartPoint.size is set
ScatterChart2D(
  series: [
    XySeries(name: 'Cohort A', color: Colors.blue, data: [
      ChartPoint(x: 5.2, y: 88, label: 'Player 1'),
    ]),
  ],
  xAxisTitle: 'Hours practiced',
  yAxisTitle: 'Score',
)
```

See `example/lib/charts_2d_demo.dart` for a runnable demo of all four
(`flutter run -t lib/charts_2d_demo.dart` from inside `example/`).

### Zoom

Every chart supports zoom, adapted to what makes sense for its shape:

**`LineChart2D` and `ScatterChart2D`** — drag a rectangle over the plot to
zoom into that range. A reset button appears in the corner while zoomed.

```dart
LineChart2D(
  ...,
  zoomMode: ChartZoomMode.x,   // default: zoom x, y auto-rescales to fit
  // zoomMode: ChartZoomMode.xy, // zoom both axes to the dragged rectangle
  // zoomMode: ChartZoomMode.none, // disable drag-to-zoom
)

ScatterChart2D(
  ...,
  zoomMode: ChartZoomMode.xy,  // default for scatter — both axes carry meaning
)
```

**`BarChart2D`** — drag horizontally to zoom into a range of categories
(y auto-rescales); `zoomMode: ChartZoomMode.xy` also zooms the y-range to
the dragged rectangle's vertical extent.

```dart
BarChart2D(
  ...,
  zoomMode: ChartZoomMode.x, // default
)
```

**`PieChart2D`** — has no axes, so there's no "range" to drag-select.
Instead it zooms like a photo viewer: pinch (or scroll on desktop) to
zoom in, drag to pan while zoomed.

```dart
PieChart2D(
  ...,
  enableZoom: true, // default
  minZoomScale: 1.0,
  maxZoomScale: 4.0,
)
```

**`Surface3DChart`** — single-finger drag rotates, two-finger pinch (or
scroll wheel on desktop) zooms.

Every chart's zoom uses the same reset-button pattern: it only appears
while zoomed, and tapping it restores the exact original view.

### Not included yet

This is a small, purpose-built library, not a Highcharts clone. Things it
does **not** do (yet): log scales, stacked percentage bars, image export,
and accessibility (screen reader) support. Contributions or follow-up
requests welcome.

### Theming

Wrap your app (or just a screen) in `ChartThemeScope` to apply consistent
colors/fonts to every chart beneath it. All four 2D chart types respect it
automatically — no per-chart configuration needed.

```dart
ChartThemeScope(
  theme: ChartTheme.dark, // or ChartTheme.light, or a custom ChartTheme(...)
  child: MaterialApp(...),
)
```

### Titles, empty states, callbacks

Every 2D chart accepts `title`/`subtitle` (rendered above the plot) and
shows a built-in "No data" placeholder automatically when its data is
empty — you don't need to check for empty data yourself.

Each chart also exposes hover/tap callbacks so your app can react to
interactions beyond the built-in tooltip:

```dart
LineChart2D(
  onPointHover: (series, point) => ..., // fires continuously, null on exit
  onPointTap: (series, point) => ...,   // fires once per tap/click
)
BarChart2D(onBarHover: ..., onBarTap: ...);
PieChart2D(onSliceHover: ..., onSliceTap: ...);
ScatterChart2D(onPointHover: ..., onPointTap: ...);
```

`LineChart2D` and `ScatterChart2D` also show a crosshair through the
hovered point by default (`showCrosshair: false` to disable).

### Animations

All four chart types animate in on first build and whenever their data
reference changes (line: draws left-to-right; bar: grows from the zero
baseline; pie/donut: grows radially from the center; scatter: pops in).
Disable with `enableAnimation: false` or adjust `animationDuration`.
