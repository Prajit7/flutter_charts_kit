import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_charts_kit/flutter_charts_kit.dart';

// Visual snapshots of every chart in both themes. Text renders as solid
// boxes (the test font), which is enough to catch layout regressions.
//
// Regenerate after an intentional visual change with:
//   flutter test --update-goldens test/golden_test.dart

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'];

final Map<String, Widget Function()> _charts = {
  'line': () => LineChart2D(
        title: 'Revenue',
        filled: true,
        enableAnimation: false,
        series: [
          XySeries(name: 'A', color: Colors.blue, data: [
            for (int i = 0; i < 6; i++) ChartPoint(x: i.toDouble(), y: 20.0 + i * 13 % 37, label: _months[i]),
          ]),
          XySeries(name: 'B', color: Colors.orange, data: [
            for (int i = 0; i < 6; i++) ChartPoint(x: i.toDouble(), y: 10.0 + i * 7, label: _months[i]),
          ]),
        ],
      ),
  'bar_grouped': () => const BarChart2D(
        title: 'Sales',
        enableAnimation: false,
        categories: _months,
        series: [
          CategorySeries(name: 'A', color: Colors.teal, values: [12, 19, 7, 23, 15, 9]),
          CategorySeries(name: 'B', color: Colors.purple, values: [8, 11, 14, 6, 18, 21]),
        ],
      ),
  'bar_stacked_negative': () => const BarChart2D(
        title: 'Net flow',
        stacked: true,
        enableAnimation: false,
        categories: _months,
        series: [
          CategorySeries(name: 'In', color: Colors.green, values: [12, 9, 15, 7, 10, 13]),
          CategorySeries(name: 'Out', color: Colors.red, values: [-6, -11, -4, -9, -12, -5]),
        ],
      ),
  'pie_donut': () => const PieChart2D(
        title: 'Share',
        innerRadiusRatio: 0.55,
        enableAnimation: false,
        slices: [
          PieSlice(label: 'A', value: 45, color: Colors.indigo),
          PieSlice(label: 'B', value: 30, color: Colors.amber),
          PieSlice(label: 'C', value: 25, color: Colors.pink),
        ],
      ),
  'scatter': () => ScatterChart2D(
        title: 'Height vs weight',
        enableAnimation: false,
        series: [
          XySeries(name: 'S', color: Colors.cyan, data: [
            for (int i = 0; i < 20; i++) ChartPoint(x: 150.0 + i * 2.3, y: 50.0 + (i * 17 % 29), size: 3.0 + i % 4),
          ]),
        ],
      ),
  'line_smooth_stacked': () => LineChart2D(
        title: 'Traffic by source',
        curve: LineChartCurve.smooth,
        stacked: true,
        filled: true,
        showPoints: false,
        enableAnimation: false,
        series: [
          for (final (name, color, base) in [('Direct', Colors.blue, 30.0), ('Search', Colors.green, 20.0), ('Social', Colors.purple, 10.0)])
            XySeries(name: name, color: color, data: [
              for (int i = 0; i < 8; i++) ChartPoint(x: i.toDouble(), y: base + (i * 7 + base) % 13),
            ]),
        ],
      ),
  'line_time_step_reference': () => LineChart2D(
        title: 'Stock level',
        xAxisType: ChartAxisType.time,
        curve: LineChartCurve.step,
        enableAnimation: false,
        showLegend: false,
        referenceLines: [
          const ChartReferenceLine.y(40, label: 'Reorder', color: Colors.red),
          ChartReferenceLine.time(DateTime(2026, 3, 8), label: 'Audit'),
        ],
        referenceBands: [ChartReferenceBand.time(DateTime(2026, 3, 3), DateTime(2026, 3, 5), label: 'Sale')],
        series: [
          XySeries(name: 'Units', color: Colors.teal, data: [
            for (int i = 0; i < 14; i++) ChartPoint.at(DateTime(2026, 3, 1 + i), y: 90.0 - i * 6 + (i % 3) * 9),
          ]),
        ],
      ),
  'bar_horizontal_labels': () => const BarChart2D(
        title: 'Top regions',
        horizontal: true,
        showValueLabels: true,
        enableAnimation: false,
        categories: ['North America', 'Europe', 'Asia Pacific', 'Latin America', 'Middle East & Africa'],
        series: [CategorySeries(name: 'Revenue', color: Colors.indigo, values: [82, 64, 71, 23, 15])],
        referenceLines: [ChartReferenceLine.y(50, label: 'Avg')],
      ),
  'combo_dual_axis': () => const ComboChart2D(
        title: 'Revenue & growth',
        enableAnimation: false,
        categories: _months,
        yAxisTitle: 'Revenue',
        secondaryYAxisTitle: 'Growth %',
        curve: LineChartCurve.smooth,
        series: [
          ComboSeries(name: 'Revenue', color: Colors.blue, values: [120, 150, 170, 160, 190, 210]),
          ComboSeries(name: 'Costs', color: Colors.blueGrey, values: [90, 100, 110, 115, 120, 125]),
          ComboSeries.line(name: 'Growth %', color: Colors.orange, values: [4, 25, 13, -6, 19, 11], secondaryAxis: true),
        ],
      ),
  'pie_legend_right': () => const PieChart2D(
        title: 'Share',
        legendPosition: ChartLegendPosition.right,
        enableAnimation: false,
        slices: [
          PieSlice(label: 'Alpha', value: 45, color: Colors.indigo),
          PieSlice(label: 'Beta', value: 30, color: Colors.amber),
          PieSlice(label: 'Gamma', value: 25, color: Colors.pink),
        ],
      ),
  'heatmap': () => HeatmapChart2D(
        title: 'Activity by hour',
        showValues: true,
        legendTitle: 'Events',
        enableAnimation: false,
        xLabels: const ['9', '10', '11', '12', '13', '14', '15'],
        yLabels: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
        data: [
          for (int r = 0; r < 5; r++) [for (int c = 0; c < 7; c++) (r == 2 && c == 3) ? null : ((r * 7 + c * 5) % 23).toDouble()],
        ],
      ),
  'gauges': () => const Row(children: [
        Expanded(
          child: GaugeChart(value: 72, label: 'CPU', enableAnimation: false, ranges: [
            GaugeRange(from: 0, to: 60, color: Colors.green),
            GaugeRange(from: 60, to: 85, color: Colors.orange),
            GaugeRange(from: 85, to: 100, color: Colors.red),
          ]),
        ),
        Expanded(
          child: GaugeChart(value: 38, label: 'Speed', style: GaugeStyle.needle, sweepAngle: 180, enableAnimation: false, ranges: [
            GaugeRange(from: 0, to: 70, color: Colors.teal),
            GaugeRange(from: 70, to: 100, color: Colors.redAccent),
          ]),
        ),
      ]),
  'sparklines': () => const Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        SizedBox(width: 200, height: 40, child: Sparkline(values: [3, 5, 4, 8, 6, 9, 7, 11], color: Colors.green, filled: true)),
        SizedBox(width: 200, height: 40, child: Sparkline(values: [9, 7, 8, 4, 6, 3, 5, 2], color: Colors.red, showMinMax: true, curve: LineChartCurve.smooth)),
        SizedBox(width: 200, height: 40, child: Sparkline(values: [3, -2, 5, 1, -4, 6, 2], type: SparklineType.bar, color: Colors.indigo, negativeColor: Colors.orange)),
      ]),
  'radar': () => const RadarChart2D(
        title: 'Model comparison',
        enableAnimation: false,
        axes: ['Speed', 'Power', 'Range', 'Comfort', 'Price', 'Safety'],
        max: 10,
        series: [
          CategorySeries(name: 'Model A', color: Colors.blue, values: [8, 6, 7, 9, 4, 8]),
          CategorySeries(name: 'Model B', color: Colors.orange, values: [6, 9, 5, 6, 8, 7]),
        ],
      ),
  'candlestick': () => CandlestickChart2D(
        title: 'ACME',
        showVolume: true,
        enableAnimation: false,
        referenceLines: const [ChartReferenceLine.y(104, label: 'Resistance')],
        candles: [
          for (int i = 0; i < 24; i++)
            Candle(
              time: DateTime(2026, 3, 2).add(Duration(days: i)),
              open: 100.0 + (i * 7 % 9) - 4,
              close: 100.0 + (i * 5 % 11) - 5,
              high: 100.0 + math.max((i * 7 % 9) - 4, (i * 5 % 11) - 5) + 2 + i % 3,
              low: 100.0 + math.min((i * 7 % 9) - 4, (i * 5 % 11) - 5) - 2 - i % 2,
              volume: 1e6 + (i * 37 % 10) * 2e5,
            ),
        ],
      ),
  'candlestick_indicators': () => CandlestickChart2D(
        title: 'ACME · 1D',
        showVolume: true,
        enableAnimation: false,
        lastPrice: 104.6,
        indicators: const [
          MovingAverageIndicator(period: 10),
          MovingAverageIndicator(period: 20, type: MovingAverageType.exponential, color: Colors.cyan),
          BollingerBandsIndicator(),
          RsiIndicator(),
          MacdIndicator(),
        ],
        candles: [
          for (int i = 0; i < 70; i++)
            Candle(
              time: DateTime(2026, 1, 5).add(Duration(days: i + (i ~/ 5) * 2)), // weekdays only
              open: 100 + 6 * math.sin(i / 6) + (i % 3) - 1,
              close: 100 + 6 * math.sin((i + 1) / 6) + (i % 4) - 1.5,
              high: 100 + 6 * math.max(math.sin(i / 6), math.sin((i + 1) / 6)) + 2.5,
              low: 100 + 6 * math.min(math.sin(i / 6), math.sin((i + 1) / 6)) - 2.5,
              volume: 1e6 + (i * 37 % 10) * 2e5,
            ),
        ],
      ),
  'histogram': () => Histogram2D(
        title: 'Response times',
        xAxisTitle: 'ms',
        showMean: true,
        enableAnimation: false,
        values: [for (int i = 0; i < 400; i++) 120 + 60 * math.sin(i * 1.7) * math.cos(i * 0.31) + (i % 17) * 3],
      ),
  'boxplot': () => const BoxPlot2D(
        title: 'Resolution time',
        yAxisTitle: 'Hours',
        enableAnimation: false,
        groups: [
          BoxPlotGroup(label: 'Team A', values: [12, 15, 14, 19, 22, 13, 41, 16, 18]),
          BoxPlotGroup(label: 'Team B', values: [18, 21, 17, 25, 24, 20, 2, 23], color: Colors.teal),
          BoxPlotGroup(label: 'Team C', values: [9, 11, 10, 14, 13, 30, 12], color: Colors.orange),
        ],
      ),
  'funnel': () => const FunnelChart2D(
        title: 'Signup funnel',
        enableAnimation: false,
        stages: [
          FunnelStage(label: 'Visited', value: 12000),
          FunnelStage(label: 'Signed up', value: 3100),
          FunnelStage(label: 'Activated', value: 1400),
          FunnelStage(label: 'Paid', value: 380),
        ],
      ),
  'treemap': () => const TreemapChart2D(
        title: 'Budget',
        enableAnimation: false,
        nodes: [
          TreemapNode(label: 'Engineering', children: [
            TreemapNode(label: 'Salaries', value: 820),
            TreemapNode(label: 'Cloud', value: 240),
            TreemapNode(label: 'Tools', value: 90),
          ]),
          TreemapNode(label: 'Marketing', children: [
            TreemapNode(label: 'Ads', value: 300),
            TreemapNode(label: 'Events', value: 120),
          ]),
          TreemapNode(label: 'Sales', value: 380),
          TreemapNode(label: 'Office', value: 150),
        ],
      ),
  'sankey': () => const SankeyChart2D(
        title: 'User journey',
        enableAnimation: false,
        links: [
          SankeyLink(source: 'Ads', target: 'Landing', value: 500),
          SankeyLink(source: 'Search', target: 'Landing', value: 700),
          SankeyLink(source: 'Search', target: 'Blog', value: 300),
          SankeyLink(source: 'Landing', target: 'Signup', value: 450),
          SankeyLink(source: 'Landing', target: 'Bounce', value: 750),
          SankeyLink(source: 'Blog', target: 'Signup', value: 120),
          SankeyLink(source: 'Blog', target: 'Bounce', value: 180),
          SankeyLink(source: 'Signup', target: 'Paid', value: 160),
        ],
      ),
  'surface_3d_wireframe_contours': () => Surface3DChart(
        data: [
          for (int r = 0; r < 12; r++)
            [for (int c = 0; c < 12; c++) 50 + 40 * math.sin(r / 2.2) * math.cos(c / 2.6)],
        ],
        xLabels: [for (int c = 0; c < 12; c++) 'C$c'],
        yLabels: [for (int r = 0; r < 12; r++) 'R$r'],
        xAxisTitle: 'X',
        yAxisTitle: 'Y',
        zAxisTitle: 'Z',
        valueFormatter: (v) => v.toStringAsFixed(0),
        gradient: const [Colors.blue, Colors.amber, Colors.red],
        renderMode: SurfaceRenderMode.wireframe,
        showContours: true,
      ),
  'bar_3d': () => Bar3DChart(
        data: [
          for (int r = 0; r < 4; r++) [for (int c = 0; c < 5; c++) 10.0 + (r * 7 + c * 11) % 30],
        ],
        xLabels: const ['N', 'S', 'E', 'W', 'C'],
        yLabels: const ['Q1', 'Q2', 'Q3', 'Q4'],
        xAxisTitle: 'Region',
        yAxisTitle: 'Quarter',
        zAxisTitle: 'Sales',
        enableAnimation: false,
      ),
  'scatter_3d': () => Scatter3DChart(
        xAxisTitle: 'Price',
        yAxisTitle: 'Rating',
        zAxisTitle: 'Sales',
        showDropLines: true,
        enableAnimation: false,
        series: [
          for (final (name, color, offset) in [('Phones', Colors.blue, 0.0), ('Laptops', Colors.orange, 400.0)])
            Scatter3DSeries(name: name, color: color, points: [
              for (int i = 0; i < 12; i++)
                Scatter3DPoint(x: 200 + offset + i * 60.0, y: 3 + (i * 7 % 20) / 10, z: 200 + (i * 37 % 90) * 10.0),
            ]),
        ],
      ),
  'surface_3d': () => Surface3DChart(
        data: [
          for (int r = 0; r < 5; r++) [for (int c = 0; c < 6; c++) 40.0 + r * 9 + (c - 2.5).abs() * 6],
        ],
        xLabels: _months,
        yLabels: const ['R1', 'R2', 'R3', 'R4', 'R5'],
        xAxisTitle: 'Month',
        yAxisTitle: 'Region',
        zAxisTitle: 'Sales',
        valueFormatter: (v) => v.toStringAsFixed(0),
        gradient: const [Colors.blue, Colors.amber, Colors.red],
        showLegend: true,
      ),
};

void main() {
  for (final dark in [false, true]) {
    final themeName = dark ? 'dark' : 'light';
    for (final entry in _charts.entries) {
      testWidgets('golden: ${entry.key} ($themeName)', (tester) async {
        tester.view.physicalSize = const Size(480, 360);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          home: ChartThemeScope(
            theme: dark ? ChartTheme.dark : ChartTheme.light,
            child: Scaffold(
              backgroundColor: dark ? const Color(0xFF1C1C1F) : Colors.white,
              body: RepaintBoundary(
                key: const ValueKey('golden'),
                // Paint the background inside the boundary so it is captured.
                child: ColoredBox(
                  color: dark ? const Color(0xFF1C1C1F) : Colors.white,
                  child: Padding(padding: const EdgeInsets.all(12), child: entry.value()),
                ),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();

        await expectLater(
          find.byKey(const ValueKey('golden')),
          matchesGoldenFile('goldens/${entry.key}_$themeName.png'),
        );
      });
    }
  }
}
