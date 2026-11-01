import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_charts_kit/flutter_charts_kit.dart';
import 'package:flutter_charts_kit/src/chart2d/cartesian_axes.dart';
import 'package:flutter_charts_kit/src/chart2d/curves.dart';
import 'package:flutter_charts_kit/src/chart2d/time_axis.dart';

// Plot geometry for a 400x300 chart with no title and no legend:
// computePlotArea pads left 48, right 12, top 12, bottom 44, giving a plot
// area of (48, 12) -> (388, 256).

Widget _host(Widget chart) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 400, height: 300, child: chart),
        ),
      ),
    );

void main() {
  group('nice ticks', () {
    test('use 1/2/5 steps', () {
      expect(Cartesian2DAxes.niceTicks(0, 100), [0, 20, 40, 60, 80, 100]);
      expect(Cartesian2DAxes.niceTicks(0, 1), [0, 0.2, 0.4, 0.6, 0.8, 1]);
      expect(Cartesian2DAxes.niceTicks(-7, 23), [-5, 0, 5, 10, 15, 20]);
    });

    test('extent rounds outward to the step', () {
      expect(Cartesian2DAxes.niceExtent(0, 93), (0, 100));
      expect(Cartesian2DAxes.niceExtent(-12, 37), (-20, 40));
    });

    test('extent always ends on a tick', () {
      for (final (lo, hi) in [(-6.0, 25.0), (0.0, 93.0), (-0.3, 7.7), (3.0, 1234.0), (-250.0, -17.0)]) {
        final (a, b) = Cartesian2DAxes.niceExtent(lo, hi);
        final ticks = Cartesian2DAxes.niceTicks(a, b);
        expect((ticks.first, ticks.last), (a, b), reason: '$lo..$hi -> $a..$b gave $ticks');
      }
    });

    test('formatNumber trims trailing zeros', () {
      expect(Cartesian2DAxes.formatNumber(5), '5');
      expect(Cartesian2DAxes.formatNumber(2.5), '2.5');
      expect(Cartesian2DAxes.formatNumber(0.30000000000000004), '0.3');
    });
  });

  group('time ticks', () {
    test('daily span gets midnight day ticks', () {
      final ticks = timeTicks(
        DateTime(2026, 3, 1, 6).millisecondsSinceEpoch.toDouble(),
        DateTime(2026, 3, 5, 18).millisecondsSinceEpoch.toDouble(),
      );
      expect(ticks.map((t) => t.$2), ['2 Mar', '3 Mar', '4 Mar', '5 Mar']);
      for (final (x, _) in ticks) {
        final t = DateTime.fromMillisecondsSinceEpoch(x.round());
        expect((t.hour, t.minute), (0, 0));
      }
    });

    test('yearly span gets month ticks, labelling January with the year', () {
      final ticks = timeTicks(
        DateTime(2025, 11, 15).millisecondsSinceEpoch.toDouble(),
        DateTime(2026, 4, 20).millisecondsSinceEpoch.toDouble(),
      );
      expect(ticks.map((t) => t.$2), ['Dec', '2026', 'Feb', 'Mar', 'Apr']);
    });

    test('intra-day span gets clock ticks', () {
      final ticks = timeTicks(
        DateTime(2026, 3, 1, 9, 7).millisecondsSinceEpoch.toDouble(),
        DateTime(2026, 3, 1, 11, 50).millisecondsSinceEpoch.toDouble(),
      );
      expect(ticks.first.$2, '09:30');
      expect(ticks.map((t) => t.$2), contains('11:00'));
    });

    test('formatTime omits midnight', () {
      expect(formatTime(DateTime(2026, 3, 1)), '1 Mar 2026');
      expect(formatTime(DateTime(2026, 3, 1, 14, 5)), '1 Mar 2026 14:05');
    });
  });

  test('smooth curve never overshoots the data', () {
    const pts = [Offset(0, 100), Offset(10, 0), Offset(20, 0), Offset(30, 100), Offset(40, 90)];
    final path = Path();
    traceCurve(path, pts, LineChartCurve.smooth);
    final bounds = path.getBounds();
    // Control points can't push the curve beyond the points' own y-range.
    expect(bounds.top, greaterThanOrEqualTo(-0.001));
    expect(bounds.bottom, lessThanOrEqualTo(100.001));
  });

  testWidgets('stacked LineChart2D reports each point\'s own value', (tester) async {
    ChartPoint? tapped;
    String? tappedSeries;
    final data = [for (int i = 0; i < 5; i++) ChartPoint(x: i.toDouble(), y: 10)];
    await tester.pumpWidget(_host(LineChart2D(
      series: [
        XySeries(name: 'A', color: Colors.blue, data: data),
        XySeries(name: 'B', color: Colors.red, data: data),
      ],
      stacked: true,
      filled: true,
      showLegend: false,
      enableAnimation: false,
      onPointTap: (s, p) {
        tappedSeries = s;
        tapped = p;
      },
    )));
    await tester.pumpAndSettle();

    // y-axis is 0..20 (B stacks to 20), so B's points sit on the top edge.
    // x = 2 is the middle of 0..4.
    await tester.tapAt(const Offset(48 + 340 / 2, 12));
    await tester.pump();
    expect(tappedSeries, 'B');
    expect(tapped?.y, 10);
  });

  testWidgets('custom tooltipBuilder replaces the default card', (tester) async {
    await tester.pumpWidget(_host(LineChart2D(
      series: [
        XySeries(name: 'A', color: Colors.blue, data: [
          for (int i = 0; i < 5; i++) ChartPoint(x: i.toDouble(), y: 10),
        ]),
      ],
      showLegend: false,
      enableAnimation: false,
      tooltipBuilder: (context, series, point) => Text('custom $series ${point.x}'),
    )));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(48 + 340 / 2, 12));
    await tester.pump();
    expect(find.text('custom A 2.0'), findsOneWidget);
  });

  testWidgets('ChartController resets zoom, tracks it, and exports a PNG', (tester) async {
    final controller = ChartController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(LineChart2D(
      controller: controller,
      series: [
        XySeries(name: 'A', color: Colors.blue, data: [
          for (int i = 0; i < 10; i++) ChartPoint(x: i.toDouble(), y: (i * i).toDouble()),
        ]),
      ],
      showLegend: false,
      enableAnimation: false,
    )));
    await tester.pumpAndSettle();
    expect(controller.isAttached, isTrue);

    await tester.dragFrom(const Offset(80, 150), const Offset(150, 0));
    await tester.pumpAndSettle();
    expect(controller.isZoomed, isTrue);
    expect(find.byIcon(Icons.zoom_out_map), findsOneWidget);

    controller.resetZoom();
    await tester.pumpAndSettle();
    expect(controller.isZoomed, isFalse);
    expect(find.byIcon(Icons.zoom_out_map), findsNothing);

    final png = await tester.runAsync(() => controller.toPngBytes(pixelRatio: 1));
    expect(png, isNotNull);
    // PNG signature
    expect(png!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });

  testWidgets('legendPosition.right puts the legend beside the plot', (tester) async {
    await tester.pumpWidget(_host(const LineChart2D(
      legendPosition: ChartLegendPosition.right,
      enableAnimation: false,
      series: [
        XySeries(name: 'A', color: Colors.blue, data: [ChartPoint(x: 0, y: 1), ChartPoint(x: 1, y: 2)]),
      ],
    )));
    await tester.pumpAndSettle();
    final legend = tester.getRect(find.byType(Chart2DLegend));
    expect(legend.left, greaterThan(300));
    expect(legend.top, lessThan(200));
  });

  testWidgets('horizontal BarChart2D hit-tests bars along the y-axis', (tester) async {
    String? category;
    double? value;
    await tester.pumpWidget(_host(BarChart2D(
      horizontal: true,
      categories: const ['A', 'B'],
      series: const [CategorySeries(name: 'S', color: Colors.teal, values: [10, 5])],
      showLegend: false,
      enableAnimation: false,
      onBarTap: (_, c, v) {
        category = c;
        value = v;
      },
    )));
    await tester.pumpAndSettle();

    // Category A is the top half of the plot (y 12..134); its bar runs the
    // full width since 10 is the axis max. B's bar only reaches half way.
    await tester.tapAt(const Offset(300, 73));
    await tester.pump();
    expect((category, value), ('A', 10));

    category = null;
    await tester.tapAt(const Offset(300, 195));
    await tester.pump();
    expect(category, isNull, reason: 'B (value 5) ends around x 218');
  });

  testWidgets('BarChart2D value labels and reference lines render', (tester) async {
    await tester.pumpWidget(_host(const BarChart2D(
      categories: ['A', 'B', 'C'],
      series: [CategorySeries(name: 'S', color: Colors.teal, values: [3, -2, 7])],
      showValueLabels: true,
      referenceLines: [ChartReferenceLine.y(5, label: 'Target')],
      referenceBands: [ChartReferenceBand.y(0, 2)],
      enableAnimation: false,
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('ComboChart2D shows every series for the hovered category', (tester) async {
    String? tapped;
    await tester.pumpWidget(_host(ComboChart2D(
      categories: const ['Jan', 'Feb', 'Mar', 'Apr'],
      series: const [
        ComboSeries(name: 'Revenue', color: Colors.blue, values: [120, 150, 170, 160]),
        ComboSeries.line(name: 'Growth', color: Colors.orange, values: [4, 25, 13, -6], secondaryAxis: true),
      ],
      secondaryYAxisTitle: 'Growth %',
      showLegend: false,
      enableAnimation: false,
      onCategoryTap: (c, _) => tapped = c,
    )));
    await tester.pumpAndSettle();

    // With a secondary axis the plot is (48, 12) -> (348, 256): 4 slots of 75px.
    await tester.tapAt(const Offset(48 + 75 * 1.5, 150));
    await tester.pump();
    expect(tapped, 'Feb');
    expect(find.text('Revenue'), findsOneWidget);
    expect(find.text('Growth'), findsOneWidget);
    expect(find.text('150'), findsOneWidget);
    expect(find.text('25'), findsOneWidget);
  });

  testWidgets('PieChart2D ignores zero and negative slices', (tester) async {
    await tester.pumpWidget(_host(const PieChart2D(
      slices: [
        PieSlice(label: 'A', value: 10, color: Colors.red),
        PieSlice(label: 'B', value: -5, color: Colors.green),
        PieSlice(label: 'C', value: 0, color: Colors.blue),
      ],
      enableAnimation: false,
    )));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(CustomPaint).last));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
