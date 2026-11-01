import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_charts_kit/flutter_charts_kit.dart';

Widget _host(Widget chart) => MaterialApp(
      home: Scaffold(body: SizedBox(width: 500, height: 400, child: chart)),
    );

void main() {
  // Each chart paints to a canvas, which screen readers can't see; every
  // chart must therefore describe itself.
  final cases = <String, (Widget, Pattern)>{
    'line': (
      const LineChart2D(title: 'Revenue', series: [
        XySeries(name: 'A', color: Colors.blue, data: [ChartPoint(x: 0, y: 3), ChartPoint(x: 1, y: 48)]),
      ]),
      'Line chart, Revenue. A: 2 values from 3 to 48.',
    ),
    'bar': (
      const BarChart2D(title: 'Sales', categories: ['Q1', 'Q2'], series: [
        CategorySeries(name: 'North', color: Colors.teal, values: [4, 9]),
      ]),
      'Bar chart, Sales. 2 categories; North: 2 values from 4 to 9.',
    ),
    'pie': (
      const PieChart2D(innerRadiusRatio: 0.5, slices: [
        PieSlice(label: 'A', value: 3, color: Colors.red),
        PieSlice(label: 'B', value: 1, color: Colors.blue),
      ]),
      'Donut chart. A: 3 (75.0%); B: 1 (25.0%).',
    ),
    'heatmap': (
      const HeatmapChart2D(data: [
        [1, 2],
        [3, 4],
      ], xLabels: ['a', 'b'], yLabels: ['r', 's']),
      'Heatmap. 2 rows by 2 columns; values from 1 to 4.',
    ),
    'funnel': (
      const FunnelChart2D(stages: [FunnelStage(label: 'Visit', value: 10), FunnelStage(label: 'Buy', value: 2)]),
      'Funnel chart. Visit: 10; Buy: 2.',
    ),
    'sankey': (
      const SankeyChart2D(links: [SankeyLink(source: 'A', target: 'B', value: 5)]),
      'Flow diagram. A to B: 5.',
    ),
    'gauge': (const GaugeChart(value: 42, label: 'CPU'), 'CPU: 42'),
    'surface 3d': (
      Surface3DChart(
        data: const [
          [1, 2],
          [3, 4],
        ],
        xLabels: const ['a', 'b'],
        yLabels: const ['r', 's'],
        xAxisTitle: 'Region',
        yAxisTitle: 'Month',
        zAxisTitle: 'Sales',
        valueFormatter: (v) => v.toStringAsFixed(0),
        gradient: const [Colors.blue, Colors.red],
      ),
      '3D surface chart, Sales. 2 Month by 2 Region; values from 1 to 4.',
    ),
    'scatter 3d': (
      const Scatter3DChart(series: [
        Scatter3DSeries(name: 'S', color: Colors.blue, points: [Scatter3DPoint(x: 1, y: 2, z: 3)]),
      ]),
      '3D scatter chart. S: 1 points.',
    ),
  };

  for (final MapEntry(key: name, value: (chart, label)) in cases.entries) {
    testWidgets('$name chart has a screen-reader summary', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(chart));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(label), findsOneWidget);
      handle.dispose();
    });
  }
}
