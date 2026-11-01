// Regenerates the README / pub.dev screenshots in example/assets/ with real
// fonts (widget tests otherwise render text as solid boxes).
//
//   flutter test tool/screenshots_test.dart
//
// Lives outside test/ so CI doesn't run it: rendering differs slightly
// between machines, and the images only need refreshing when visuals change.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_charts_kit/flutter_charts_kit.dart';

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? '';
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      final bytes = File('$dir/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await family('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await family('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

/// A titled grid of chart cards.
Widget _gallery(String heading, int columns, List<Widget> charts) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo, fontFamily: 'Roboto'),
    home: ChartThemeScope(
      theme: const ChartTheme(fontFamily: 'Roboto'),
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F5F9),
        body: RepaintBoundary(
          key: const ValueKey('shot'),
          child: ColoredBox(
            color: const Color(0xFFF4F5F9),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(heading, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'Roboto')),
                const SizedBox(height: 14),
                Expanded(
                  child: Column(children: [
                    for (int r = 0; r < (charts.length / columns).ceil(); r++)
                      Expanded(
                        child: Row(children: [
                          for (int c = 0; c < columns; c++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: r * columns + c < charts.length
                                    ? Card(
                                        elevation: 0,
                                        color: Colors.white,
                                        child: Padding(padding: const EdgeInsets.all(12), child: charts[r * columns + c]),
                                      )
                                    : const SizedBox(),
                              ),
                            ),
                        ]),
                      ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _shoot(WidgetTester tester, String file, Widget app, Size size) async {
  tester.view.physicalSize = size * 1.5;
  tester.view.devicePixelRatio = 1.5;
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('example/assets/$file').writeAsBytesSync(png!.buffer.asUint8List());
    image.dispose();
  });
  tester.view.reset();
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug'];

void main() {
  setUpAll(_loadFonts);

  testWidgets('2D charts', (tester) async {
    final day0 = DateTime(2026, 1, 1);
    await _shoot(
      tester,
      '2d.png',
      _gallery('2D charts', 3, [
        LineChart2D(
          title: 'Daily traffic',
          xAxisType: ChartAxisType.time,
          curve: LineChartCurve.smooth,
          showPoints: false,
          enableAnimation: false,
          referenceLines: const [ChartReferenceLine.y(560, label: 'Goal', color: Colors.red)],
          referenceBands: [ChartReferenceBand.time(DateTime(2026, 2, 10), DateTime(2026, 2, 20), label: 'Campaign')],
          series: [
            XySeries(name: 'Visits', color: Colors.indigo, data: [
              for (int d = 0; d < 90; d++) ChartPoint.at(day0.add(Duration(days: d)), y: 400 + (d * 37 % 160) + d * 2.0),
            ]),
            XySeries(name: 'Sign-ups', color: Colors.teal, data: [
              for (int d = 0; d < 90; d++) ChartPoint.at(day0.add(Duration(days: d)), y: 120 + (d * 23 % 90) + d * 1.5),
            ]),
          ],
        ),
        LineChart2D(
          title: 'Traffic by source',
          stacked: true,
          filled: true,
          curve: LineChartCurve.smooth,
          showPoints: false,
          enableAnimation: false,
          series: [
            for (final (name, color, v) in [
              ('Direct', Colors.blue, <double>[30, 34, 31, 38, 42, 40, 45, 48]),
              ('Search', Colors.green, <double>[22, 25, 29, 27, 31, 35, 33, 38]),
              ('Social', Colors.purple, <double>[10, 14, 12, 18, 15, 21, 24, 22]),
            ])
              XySeries(name: name, color: color, data: [
                for (int i = 0; i < 8; i++) ChartPoint(x: i.toDouble(), y: v[i], label: _months[i]),
              ]),
          ],
        ),
        const ComboChart2D(
          title: 'Revenue & growth',
          enableAnimation: false,
          categories: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'],
          secondaryYAxisTitle: 'Growth %',
          curve: LineChartCurve.smooth,
          series: [
            ComboSeries(name: 'Revenue', color: Colors.blue, values: [120, 150, 170, 160, 190, 210]),
            ComboSeries(name: 'Costs', color: Colors.blueGrey, values: [90, 100, 110, 115, 120, 125]),
            ComboSeries.line(name: 'Growth %', color: Colors.orange, values: [4, 25, 13, -6, 19, 11], secondaryAxis: true),
          ],
        ),
        const BarChart2D(
          title: 'Revenue by region',
          horizontal: true,
          showValueLabels: true,
          showLegend: false,
          enableAnimation: false,
          categories: ['North America', 'Europe', 'Asia Pacific', 'Latin America', 'Middle East'],
          series: [CategorySeries(name: 'Revenue', color: Colors.indigo, values: [82, 64, 71, 23, 15])],
          referenceLines: [ChartReferenceLine.y(51, label: 'Avg')],
        ),
        const PieChart2D(
          title: 'Browser share',
          innerRadiusRatio: 0.58,
          legendPosition: ChartLegendPosition.right,
          enableAnimation: false,
          slices: [
            PieSlice(label: 'Chrome', value: 64, color: Color(0xFF3949AB)),
            PieSlice(label: 'Safari', value: 19, color: Color(0xFF00ACC1)),
            PieSlice(label: 'Edge', value: 9, color: Color(0xFF7CB342)),
            PieSlice(label: 'Other', value: 8, color: Color(0xFFFFB300)),
          ],
        ),
        ScatterChart2D(
          title: 'Practice vs. score',
          enableAnimation: false,
          xAxisTitle: 'Hours',
          yAxisTitle: 'Score',
          series: [
            for (final (name, color, shift) in [('Cohort A', Colors.indigo, 0.0), ('Cohort B', Colors.deepOrange, 8.0)])
              XySeries(name: name, color: color, data: [
                for (int i = 0; i < 24; i++)
                  ChartPoint(x: 2 + i * 0.6 + shift / 4, y: 55 + i * 1.4 + (i * 13 % 11) - shift, size: 3.0 + i % 4),
              ]),
          ],
        ),
      ]),
      const Size(1500, 860),
    );
  });

  testWidgets('3D charts', (tester) async {
    await _shoot(
      tester,
      '3d.png',
      _gallery('3D charts', 2, [
        Surface3DChart(
          data: const [
            [12.0, 18.0, 9.0, 22.0, 16.0],
            [15.0, 20.0, 11.0, 25.0, 19.0],
            [19.0, 24.0, 14.0, 30.0, 23.0],
            [23.0, 29.0, 17.0, 35.0, 27.0],
          ],
          xLabels: const ['North', 'South', 'East', 'West', 'Central'],
          yLabels: const ['Jan', 'Feb', 'Mar', 'Apr'],
          xAxisTitle: 'Region',
          yAxisTitle: 'Month',
          zAxisTitle: 'Sales',
          valueFormatter: (v) => '\$${v.toStringAsFixed(0)}k',
          gradient: const [Colors.teal, Colors.amber, Colors.deepOrange],
          showLegend: true,
        ),
        Surface3DChart(
          data: [
            for (int r = 0; r < 16; r++)
              [for (int c = 0; c < 16; c++) 50 + 35 * math.sin(r / 2.5) * math.cos(c / 3.0) + 10 * math.cos((r + c) / 4)],
          ],
          xLabels: [for (int c = 0; c < 16; c++) '${c * 10}'],
          yLabels: [for (int r = 0; r < 16; r++) '${r * 10}'],
          xAxisTitle: 'East',
          yAxisTitle: 'North',
          zAxisTitle: 'Elevation',
          valueFormatter: (v) => v.toStringAsFixed(0),
          gradient: const [Color(0xFF1E88E5), Color(0xFF43A047), Color(0xFFFDD835), Color(0xFFE53935)],
          renderMode: SurfaceRenderMode.wireframe,
          showContours: true,
          contourLevels: 10,
        ),
        const Bar3DChart(
          data: [
            [12, 18, 9, 22],
            [15, 20, 11, 25],
            [19, 24, 14, 30],
            [23, 29, 17, 35],
          ],
          xLabels: ['North', 'South', 'East', 'West'],
          yLabels: ['Q1', 'Q2', 'Q3', 'Q4'],
          xAxisTitle: 'Region',
          yAxisTitle: 'Quarter',
          zAxisTitle: 'Sales',
          gradient: [Colors.teal, Colors.amber, Colors.deepOrange],
          enableAnimation: false,
        ),
        Builder(builder: (context) {
          final rnd = math.Random(5);
          Scatter3DSeries cluster(String name, Color color, double cx, double cy, double cz) => Scatter3DSeries(
                name: name,
                color: color,
                points: [
                  for (int i = 0; i < 25; i++)
                    Scatter3DPoint(
                      x: cx + (rnd.nextDouble() - 0.5) * 30,
                      y: cy + (rnd.nextDouble() - 0.5) * 30,
                      z: cz + (rnd.nextDouble() - 0.5) * 30,
                    ),
                ],
              );
          return Scatter3DChart(
            xAxisTitle: 'Age',
            yAxisTitle: 'Income',
            zAxisTitle: 'Spend',
            showDropLines: true,
            enableAnimation: false,
            series: [
              cluster('Students', Colors.blue, 22, 20, 15),
              cluster('Professionals', Colors.orange, 38, 85, 45),
              cluster('Retirees', Colors.green, 68, 45, 30),
            ],
          );
        }),
      ]),
      const Size(1400, 1000),
    );
  });

  testWidgets('Trading chart', (tester) async {
    final rnd = math.Random(11);
    var price = 182.0;
    final candles = <Candle>[];
    var day = DateTime(2025, 11, 3);
    for (int i = 0; i < 120; i++) {
      while (day.weekday > 5) {
        day = day.add(const Duration(days: 1));
      }
      final open = price;
      price = math.max(50, price + (rnd.nextDouble() - 0.47) * 4);
      candles.add(Candle(
        time: day,
        open: open,
        high: math.max(open, price) + rnd.nextDouble() * 2.2,
        low: math.min(open, price) - rnd.nextDouble() * 2.2,
        close: price,
        volume: 2e6 + rnd.nextDouble() * 3e6,
      ));
      day = day.add(const Duration(days: 1));
    }
    tester.view.physicalSize = const Size(1400, 820) * 1.5;
    tester.view.devicePixelRatio = 1.5;
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Roboto'),
      home: Scaffold(
        backgroundColor: ChartTheme.trading.backgroundColor,
        body: RepaintBoundary(
          key: const ValueKey('shot'),
          child: ColoredBox(
            color: ChartTheme.trading.backgroundColor,
            child: Padding(
            padding: const EdgeInsets.all(16),
            child: CandlestickChart2D(
              title: 'ACME Corp · 1D',
              subtitle: 'Candles + volume, SMA 20, EMA 50, Bollinger Bands, RSI and MACD — live last-price tag on the right',
              theme: ChartTheme.trading.copyWith(fontFamily: 'Roboto'),
              candles: candles,
              showVolume: true,
              enableAnimation: false,
              lastPrice: candles.last.close,
              indicators: const [
                MovingAverageIndicator(period: 20),
                MovingAverageIndicator(period: 50, type: MovingAverageType.exponential, color: Color(0xFF26C6DA)),
                BollingerBandsIndicator(),
                RsiIndicator(),
                MacdIndicator(),
              ],
            ),
          ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('example/assets/trading.png').writeAsBytesSync(png!.buffer.asUint8List());
      image.dispose();
    });
    tester.view.reset();
  });

  testWidgets('More charts', (tester) async {
    final rnd = math.Random(7);
    var price = 100.0;
    final candles = <Candle>[];
    for (int i = 0; i < 50; i++) {
      final open = price;
      price = math.max(20, price + (rnd.nextDouble() - 0.48) * 4);
      candles.add(Candle(
        time: DateTime(2026, 1, 5).add(Duration(days: i)),
        open: open,
        high: math.max(open, price) + rnd.nextDouble() * 2,
        low: math.min(open, price) - rnd.nextDouble() * 2,
        close: price,
        volume: 8e5 + rnd.nextDouble() * 1.2e6,
      ));
    }
    double gaussian() => math.sqrt(-2 * math.log(1 - rnd.nextDouble())) * math.cos(2 * math.pi * rnd.nextDouble());

    await _shoot(
      tester,
      'more.png',
      _gallery('More chart types', 3, [
        HeatmapChart2D(
          title: 'Tickets by hour',
          enableAnimation: false,
          legendPosition: ChartLegendPosition.none,
          gradient: const [Color(0xFFE8F5E9), Color(0xFF43A047), Color(0xFF1B5E20)],
          xLabels: [for (int h = 8; h <= 18; h++) '$h'],
          yLabels: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
          data: [
            for (int d = 0; d < 7; d++)
              [for (int h = 8; h <= 18; h++) ((math.sin(h / 3.0) + 1.3) * (d >= 5 ? 4 : 12) + (d * 3 + h) % 5).roundToDouble()],
          ],
        ),
        CandlestickChart2D(
          title: 'ACME',
          candles: candles,
          showVolume: true,
          enableAnimation: false,
          theme: ChartTheme.trading.copyWith(fontFamily: 'Roboto'),
          indicators: const [MovingAverageIndicator(period: 10)],
        ),
        const RadarChart2D(
          title: 'Phone X vs Y',
          enableAnimation: false,
          axes: ['Speed', 'Battery', 'Camera', 'Display', 'Price', 'Build'],
          max: 10,
          series: [
            CategorySeries(name: 'Phone X', color: Colors.indigo, values: [9, 6, 8, 9, 4, 8]),
            CategorySeries(name: 'Phone Y', color: Colors.orange, values: [7, 9, 6, 7, 8, 6]),
          ],
        ),
        Histogram2D(
          title: 'API latency (ms)',
          enableAnimation: false,
          showMean: true,
          valueFormatter: (v) => v.toStringAsFixed(0),
          values: [for (int i = 0; i < 800; i++) math.exp(4.6 + 0.35 * gaussian())],
        ),
        BoxPlot2D(
          title: 'Resolution time (h)',
          enableAnimation: false,
          valueFormatter: (v) => v.toStringAsFixed(0),
          groups: [
            BoxPlotGroup(label: 'Tier 1', values: [for (int i = 0; i < 60; i++) 6 + 2 * gaussian(), 19, 22]),
            BoxPlotGroup(label: 'Tier 2', values: [for (int i = 0; i < 40; i++) 14 + 4 * gaussian()], color: Colors.teal),
            BoxPlotGroup(label: 'Tier 3', values: [for (int i = 0; i < 25; i++) 30 + 8 * gaussian(), 70], color: Colors.deepOrange),
          ],
        ),
        const Row(children: [
          Expanded(
            child: GaugeChart(value: 72, label: 'CPU', title: 'Gauges', enableAnimation: false, ranges: [
              GaugeRange(from: 0, to: 60, color: Colors.green),
              GaugeRange(from: 60, to: 85, color: Colors.orange),
              GaugeRange(from: 85, to: 100, color: Colors.red),
            ]),
          ),
          Expanded(
            child: GaugeChart(value: 58, max: 120, label: 'km/h', style: GaugeStyle.needle, sweepAngle: 180, enableAnimation: false, ranges: [
              GaugeRange(from: 0, to: 90, color: Colors.teal),
              GaugeRange(from: 90, to: 120, color: Colors.redAccent),
            ]),
          ),
        ]),
        const FunnelChart2D(
          title: 'Signup funnel',
          enableAnimation: false,
          stages: [
            FunnelStage(label: 'Visited', value: 24000),
            FunnelStage(label: 'Pricing', value: 9600),
            FunnelStage(label: 'Trial', value: 3100),
            FunnelStage(label: 'Paid', value: 520),
          ],
        ),
        const TreemapChart2D(
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
        const SankeyChart2D(
          title: 'User journey',
          enableAnimation: false,
          links: [
            SankeyLink(source: 'Ads', target: 'Landing', value: 500),
            SankeyLink(source: 'Search', target: 'Landing', value: 700),
            SankeyLink(source: 'Search', target: 'Blog', value: 300),
            SankeyLink(source: 'Landing', target: 'Signup', value: 450),
            SankeyLink(source: 'Landing', target: 'Bounced', value: 750),
            SankeyLink(source: 'Blog', target: 'Signup', value: 140),
            SankeyLink(source: 'Blog', target: 'Bounced', value: 160),
            SankeyLink(source: 'Signup', target: 'Paid', value: 190),
          ],
        ),
      ]),
      const Size(1500, 1100),
    );
  });
}
