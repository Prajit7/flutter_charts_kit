import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_charts_kit/flutter_charts_kit.dart';
import 'package:flutter_charts_kit/src/chart2d/treemap_chart.dart' show squarify;

Widget _host(Widget chart, {Size size = const Size(400, 300)}) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: size.width, height: size.height, child: chart),
        ),
      ),
    );

void main() {
  group('HistogramBin.compute', () {
    test('uses nice, aligned bin edges and counts every value once', () {
      final values = [for (int i = 0; i < 100; i++) i * 0.97 + 3];
      final bins = HistogramBin.compute(values, binCount: 10);
      expect(bins.first.end - bins.first.start, 10); // nice width for a ~96 range
      expect(bins.first.start % 10, 0);
      expect(bins.fold<int>(0, (s, b) => s + b.count), values.length);
      expect(bins.first.start, lessThanOrEqualTo(values.first));
      expect(bins.last.end, greaterThanOrEqualTo(values.last));
    });

    test('ignores non-finite values and handles a single repeated value', () {
      expect(HistogramBin.compute([double.nan, double.infinity]), isEmpty);
      final bins = HistogramBin.compute([5, 5, 5]);
      expect(bins, hasLength(1));
      expect(bins.single.count, 3);
    });
  });

  test('BoxPlotStats matches the standard (R-7) quartiles and flags outliers', () {
    final s = BoxPlotStats.fromValues([1, 2, 3, 4, 5, 6, 7, 8, 100])!;
    expect(s.median, 5);
    expect(s.q1, 3);
    expect(s.q3, 7);
    expect(s.outliers, [100]);
    expect(s.whiskerHigh, 8);
    expect(s.whiskerLow, 1);
    expect(BoxPlotStats.fromValues([]), isNull);
  });

  test('squarify fills the rect with areas proportional to the values', () {
    const rect = Rect.fromLTWH(0, 0, 300, 200);
    final values = <double>[6, 6, 4, 3, 2, 2, 1];
    final rects = squarify(values, rect);
    final total = values.reduce((a, b) => a + b);
    for (int i = 0; i < values.length; i++) {
      final r = rects[i];
      expect(r.width * r.height, closeTo(values[i] / total * rect.width * rect.height, 0.01));
      expect(rect.inflate(0.001).contains(r.topLeft) && rect.inflate(0.001).contains(r.bottomRight), isTrue);
    }
    // No two tiles overlap.
    for (int i = 0; i < rects.length; i++) {
      for (int j = i + 1; j < rects.length; j++) {
        final o = rects[i].intersect(rects[j]);
        expect(o.width <= 0.001 || o.height <= 0.001, isTrue, reason: 'tiles $i and $j overlap');
      }
    }
  });

  testWidgets('HeatmapChart2D taps report the cell and skip missing values', (tester) async {
    HeatmapCell? tapped;
    await tester.pumpWidget(_host(HeatmapChart2D(
      data: const [
        [1, 2],
        [3, null],
      ],
      xLabels: const ['a', 'b'],
      yLabels: const ['r0', 'r1'],
      showLegend: false,
      enableAnimation: false,
      onCellTap: (c) => tapped = c,
    )));
    await tester.pumpAndSettle();
    final grid = tester.getRect(find.byType(CustomPaint).last);
    // Bottom-left cell (row 1, col 0) is in the lower-left quarter of the grid area.
    await tester.tapAt(grid.bottomRight - const Offset(240, 60));
    await tester.pump();
    expect((tapped?.row, tapped?.col, tapped?.value), (1, 0, 3));

    tapped = null;
    await tester.tapAt(grid.bottomRight - const Offset(40, 60)); // the null cell
    await tester.pump();
    expect(tapped, isNull);
  });

  testWidgets('GaugeChart animates to a new value without errors', (tester) async {
    Widget gauge(double v) => _host(GaugeChart(value: v, label: 'CPU'));
    await tester.pumpWidget(gauge(20));
    await tester.pumpAndSettle();
    await tester.pumpWidget(gauge(90));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('RadarChart2D tap hits the nearest vertex', (tester) async {
    RadarHit? hit;
    await tester.pumpWidget(_host(RadarChart2D(
      axes: const ['A', 'B', 'C', 'D'],
      series: const [CategorySeries(name: 'S', color: Colors.blue, values: [10, 10, 10, 10])],
      max: 10,
      showLegend: false,
      enableAnimation: false,
      onPointTap: (h) => hit = h,
    )));
    await tester.pumpAndSettle();
    // Value 10 = max, so axis A's vertex is at the top of the web, straight
    // above the centre.
    final plot = tester.getRect(find.byType(CustomPaint).last);
    final top = plot.center.dy - (plot.height / 2 - 18);
    await tester.tapAt(Offset(plot.center.dx, top));
    await tester.pump();
    expect((hit?.series, hit?.axis, hit?.value), ('S', 'A', 10));
  });

  testWidgets('CandlestickChart2D zooms by drag and resets via controller', (tester) async {
    final controller = ChartController();
    addTearDown(controller.dispose);
    Candle? tapped;
    final candles = [
      for (int i = 0; i < 30; i++)
        Candle(time: DateTime(2026, 1, 1).add(Duration(days: i)), open: 10, high: 12, low: 9, close: 11 + i % 2 - 0.5),
    ];
    await tester.pumpWidget(_host(CandlestickChart2D(
      candles: candles,
      controller: controller,
      enableAnimation: false,
      onCandleTap: (c) => tapped = c,
    )));
    await tester.pumpAndSettle();

    // The plot starts at x=4 and candles are evenly spaced (30 + 3 padding
    // over ~332px), so candle 0 sits ~5px in.
    await tester.tapAt(const Offset(9, 120));
    await tester.pump();
    expect(tapped, candles.first);

    await tester.dragFrom(const Offset(120, 120), const Offset(160, 0));
    await tester.pumpAndSettle();
    expect(controller.isZoomed, isTrue);
    controller.resetZoom();
    await tester.pumpAndSettle();
    expect(controller.isZoomed, isFalse);
  });

  testWidgets('FunnelChart2D tooltip shows conversion from the first stage', (tester) async {
    await tester.pumpWidget(_host(const FunnelChart2D(
      enableAnimation: false,
      stages: [
        FunnelStage(label: 'Visited', value: 1000),
        FunnelStage(label: 'Paid', value: 250),
      ],
    )));
    await tester.pumpAndSettle();
    // Second (bottom) stage row.
    await tester.tapAt(const Offset(120, 230));
    await tester.pump();
    expect(find.textContaining('25% of Visited'), findsOneWidget);
  });

  testWidgets('TreemapChart2D hit-tests leaves, not their groups', (tester) async {
    TreemapTile? tapped;
    await tester.pumpWidget(_host(TreemapChart2D(
      enableAnimation: false,
      onTileTap: (t) => tapped = t,
      nodes: const [
        TreemapNode(label: 'Group', children: [TreemapNode(label: 'Leaf', value: 10)]),
      ],
    )));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(200, 200));
    await tester.pump();
    expect(tapped?.path, ['Group', 'Leaf']);
  });

  testWidgets('SankeyChart2D drops cycles and reports node/link taps', (tester) async {
    SankeyHit? hit;
    await tester.pumpWidget(_host(SankeyChart2D(
      enableAnimation: false,
      onTap: (h) => hit = h,
      links: const [
        SankeyLink(source: 'A', target: 'B', value: 10),
        SankeyLink(source: 'B', target: 'A', value: 5), // cycle — ignored
      ],
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // A is the left column node, B the right; the band fills between them.
    await tester.tapAt(const Offset(4, 150));
    await tester.pump();
    expect(hit?.nodeId, 'A');
    await tester.tapAt(const Offset(200, 150));
    await tester.pump();
    expect(hit?.link?.source, 'A');
  });

  testWidgets('Histogram2D and BoxPlot2D render and show tooltips', (tester) async {
    await tester.pumpWidget(_host(Histogram2D(
      enableAnimation: false,
      values: [for (int i = 0; i < 50; i++) (i % 10).toDouble()],
    )));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(60, 240));
    await tester.pump();
    expect(find.textContaining('% of 50'), findsOneWidget);

    await tester.pumpWidget(_host(const BoxPlot2D(
      enableAnimation: false,
      groups: [BoxPlotGroup(label: 'G', values: [1, 2, 3, 4, 5])],
    )));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(220, 140));
    await tester.pump();
    expect(find.text('Median 3'), findsOneWidget);
  });

  testWidgets('Sparkline paints in a tiny box, including edge cases', (tester) async {
    for (final values in [<double>[], [5.0], [1.0, 1.0, 1.0], [3.0, -2.0, 4.0]]) {
      await tester.pumpWidget(_host(Sparkline(values: values, filled: true, showMinMax: true), size: const Size(80, 20)));
      expect(tester.takeException(), isNull);
    }
  });
}
