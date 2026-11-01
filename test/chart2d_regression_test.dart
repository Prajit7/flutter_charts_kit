import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_charts_kit/flutter_charts_kit.dart';

// Plot geometry for a 400x300 chart with no title and no legend:
// Cartesian2DAxes.computePlotArea pads left 48, right 12, top 12, bottom 44,
// giving a plot area of (48, 12) -> (388, 256).

Widget _host(Widget chart) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 400, height: 300, child: chart),
        ),
      ),
    );

void main() {
  testWidgets('BarChart2D tap on a series shorter than categories does not throw', (tester) async {
    String? tappedSeries;
    double? tappedValue;
    await tester.pumpWidget(_host(BarChart2D(
      categories: const ['A', 'B'],
      series: const [CategorySeries(name: 'S', color: Colors.blue, values: [5])],
      showLegend: false,
      enableAnimation: false,
      onBarTap: (s, c, v) {
        tappedSeries = s;
        tappedValue = v;
      },
    )));
    await tester.pumpAndSettle();

    // Category 'B' has no value, so its bar is a zero-height rect on the
    // baseline (y = 256). Slot 1 spans x 218..388; its bar is centred ~303.
    await tester.tapAt(const Offset(303, 255.5));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(tappedSeries, 'S');
    expect(tappedValue, 0);
  });

  testWidgets('ScatterChart2D tap picks the nearest point, not the last one in range', (tester) async {
    ChartPoint? tapped;
    await tester.pumpWidget(_host(ScatterChart2D(
      series: const [
        XySeries(name: 'S', color: Colors.blue, data: [
          ChartPoint(x: 0, y: 0, label: 'first'),
          ChartPoint(x: 1, y: 0, label: 'second'),
          ChartPoint(x: 100, y: 100, label: 'far'),
        ]),
      ],
      showLegend: false,
      enableAnimation: false,
      onPointTap: (_, p) => tapped = p,
    )));
    await tester.pumpAndSettle();

    // Bounds are padded 8%: x and y both span -8..108. Point (0, 0) lands at
    // (48 + 8/116*340, 256 - 8/116*244) ≈ (71.4, 239.2); (1, 0) is ~3px right.
    await tester.tapAt(const Offset(71.4, 239.2));
    await tester.pump();

    expect(tapped?.label, 'first');
  });

  testWidgets('LineChart2D keeps its zoom when the parent rebuilds with equal data', (tester) async {
    late StateSetter rebuildParent;
    await tester.pumpWidget(_host(StatefulBuilder(builder: (context, setState) {
      rebuildParent = setState;
      // A fresh-but-equal list every build, as with inline `series: [...]`.
      return LineChart2D(
        series: [
          XySeries(
            name: 'A',
            color: Colors.blue,
            data: List.generate(10, (i) => ChartPoint(x: i.toDouble(), y: (i * i).toDouble())),
          ),
        ],
        showLegend: false,
        enableAnimation: false,
      );
    })));
    await tester.pumpAndSettle();

    await tester.dragFrom(const Offset(80, 150), const Offset(150, 0));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.zoom_out_map), findsOneWidget);

    rebuildParent(() {});
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.zoom_out_map), findsOneWidget);
  });

  testWidgets('ScatterChart2D x-zoom ignores a short drag', (tester) async {
    await tester.pumpWidget(_host(ScatterChart2D(
      series: [
        XySeries(
          name: 'S',
          color: Colors.blue,
          data: List.generate(10, (i) => ChartPoint(x: i.toDouble(), y: i.toDouble())),
        ),
      ],
      showLegend: false,
      enableAnimation: false,
      zoomMode: ChartZoomMode.x,
    )));
    await tester.pumpAndSettle();

    // 6px wide, under the 12px threshold — must not zoom.
    await tester.dragFrom(const Offset(150, 150), const Offset(6, 40));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.zoom_out_map), findsNothing);
  });

  test('models compare by value', () {
    expect(const ChartPoint(x: 1, y: 2), const ChartPoint(x: 1, y: 2));
    expect(
      const XySeries(name: 'a', color: Colors.red, data: [ChartPoint(x: 1, y: 2)]),
      const XySeries(name: 'a', color: Colors.red, data: [ChartPoint(x: 1, y: 2)]),
    );
    expect(
      const CategorySeries(name: 'a', color: Colors.red, values: [1, 2]),
      isNot(const CategorySeries(name: 'a', color: Colors.red, values: [1, 3])),
    );
  });
}
