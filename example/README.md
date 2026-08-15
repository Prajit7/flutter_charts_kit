# Examples

Two runnable demos.

## 1. Simple 3D surface (`lib/simple_3d_demo.dart`)

The minimal starting point — hardcoded data, no networking, ~40 lines.

```bash
flutter run -t lib/simple_3d_demo.dart
```

```dart
Surface3DChart(
  data: const [
    [12.0, 18.0, 9.0, 22.0],
    [15.0, 20.0, 11.0, 25.0],
    [19.0, 24.0, 14.0, 30.0],
    [23.0, 29.0, 17.0, 35.0],
  ],
  xLabels: const ['North', 'South', 'East', 'West'],
  yLabels: const ['Jan', 'Feb', 'Mar', 'Apr'],
  xAxisTitle: 'Region',
  yAxisTitle: 'Month',
  zAxisTitle: 'Sales',
  valueFormatter: (v) => '\$${v.toStringAsFixed(0)}k',
  gradient: const [Colors.teal, Colors.amber, Colors.deepOrange],
  showLegend: true,
)
```

## 2. All four 2D chart types (`lib/charts_2d_demo.dart`)

Line, bar (grouped + stacked), pie/donut, and scatter — each with theming,
titles, drag-to-zoom, and a dark-mode toggle in the app bar.

```bash
flutter run -t lib/charts_2d_demo.dart
```
