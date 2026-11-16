import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_charts_kit/flutter_charts_kit.dart';
import 'package:flutter_charts_kit/src/chart2d/cartesian_axes.dart';
import 'package:flutter_charts_kit/src/chart2d/crosshair_sync.dart' show SyncCrosshairPainter, SyncBandPainter;

// Plot area for a 400x300 Cartesian chart without title/legend:
// (48, 12) -> (388, 256).
Widget _host(Widget chart) => MaterialApp(
      home: Scaffold(body: Align(alignment: Alignment.topLeft, child: SizedBox(width: 400, height: 300, child: chart))),
    );

/// Hovers [at] with a mouse and returns the gesture (for later moves).
Future<TestGesture> _hover(WidgetTester tester, Offset at) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: at);
  await mouse.moveTo(at);
  await tester.pump();
  return mouse;
}

void main() {
  group('log scale', () {
    test('ticks are powers of ten, with 2/5 steps over narrow ranges', () {
      expect(Cartesian2DAxes.logTicks(10, 10000), [10, 100, 1000, 10000]);
      expect(Cartesian2DAxes.logTicks(1, 50), [1, 2, 5, 10, 20, 50]);
      expect(Cartesian2DAxes.logExtent(12, 9100), (10, 10000));
    });

    test('maps each decade to equal space', () {
      final axes = Cartesian2DAxes(
          plotArea: const Rect.fromLTWH(0, 0, 300, 300), minX: 0, maxX: 1, minY: 1, maxY: 1000, logY: true);
      expect(axes.toScreenY(10), closeTo(200, 1e-9));
      expect(axes.toScreenY(100), closeTo(100, 1e-9));
      expect(axes.toDataY(100), closeTo(100, 1e-9));
      expect(axes.toScreenY(0), 300, reason: 'non-positive values pin to the axis minimum');
    });

    testWidgets('line and scatter charts render log axes, skipping values ≤ 0', (tester) async {
      const data = [ChartPoint(x: 1, y: 0), ChartPoint(x: 2, y: 40), ChartPoint(x: 3, y: 9100), ChartPoint(x: 4, y: -5)];
      await tester.pumpWidget(_host(const LineChart2D(
        yAxisScale: ChartAxisScale.logarithmic,
        enableAnimation: false,
        series: [XySeries(name: 'a', color: Colors.blue, data: data)],
      )));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_host(const ScatterChart2D(
        xAxisScale: ChartAxisScale.logarithmic,
        yAxisScale: ChartAxisScale.logarithmic,
        enableAnimation: false,
        series: [XySeries(name: 'a', color: Colors.blue, data: data)],
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('100% stacked', () {
    testWidgets('bars report real values and shares', (tester) async {
      double? tapped;
      await tester.pumpWidget(_host(BarChart2D(
        percentStacked: true,
        showLegend: false,
        enableAnimation: false,
        categories: const ['Q1'],
        series: const [
          CategorySeries(name: 'Web', color: Colors.blue, values: [30]),
          CategorySeries(name: 'App', color: Colors.teal, values: [10]),
        ],
        onBarTap: (_, __, v) => tapped = v,
      )));
      await tester.pumpAndSettle();
      // Web is 75% of the bar: the bottom three quarters (y 73 → 256).
      await tester.tapAt(const Offset(218, 200));
      await tester.pump();
      expect(tapped, 30);
      expect(find.text('30 (75.0%)'), findsOneWidget);
    });

    testWidgets('lines report each point\'s own value and share', (tester) async {
      await tester.pumpWidget(_host(const LineChart2D(
        percentStacked: true,
        showLegend: false,
        enableAnimation: false,
        series: [
          XySeries(name: 'A', color: Colors.blue, data: [ChartPoint(x: 0, y: 1), ChartPoint(x: 1, y: 1)]),
          XySeries(name: 'B', color: Colors.red, data: [ChartPoint(x: 0, y: 3), ChartPoint(x: 1, y: 3)]),
        ],
      )));
      await tester.pumpAndSettle();
      // A tops out at 25% of the 0–100 axis.
      await tester.tapAt(const Offset(48, 256 - 244 * 0.25));
      await tester.pump();
      expect(find.text('1 (25.0%)'), findsOneWidget);
    });
  });

  group('annotations and labels', () {
    testWidgets('appear on every supporting chart (checked via SVG export)', (tester) async {
      final charts = <String, Widget Function(ChartController)>{
        'line': (c) => LineChart2D(
              controller: c,
              enableAnimation: false,
              showValueLabels: true,
              annotations: const [ChartAnnotation(x: 1, y: 5, text: 'Peak')],
              series: const [XySeries(name: 'a', color: Colors.blue, data: [ChartPoint(x: 0, y: 2), ChartPoint(x: 1, y: 5)])],
            ),
        'scatter': (c) => ScatterChart2D(
              controller: c,
              enableAnimation: false,
              showPointLabels: true,
              annotations: const [ChartAnnotation(x: 1, y: 5, text: 'Peak')],
              series: const [XySeries(name: 'a', color: Colors.blue, data: [ChartPoint(x: 0, y: 2, label: 'P0'), ChartPoint(x: 1, y: 5)])],
            ),
        'bar': (c) => BarChart2D(
              controller: c,
              enableAnimation: false,
              annotations: const [ChartAnnotation(x: 1, y: 5, text: 'Peak')],
              categories: const ['a', 'b'],
              series: const [CategorySeries(name: 's', color: Colors.blue, values: [2, 5])],
            ),
        'combo': (c) => ComboChart2D(
              controller: c,
              enableAnimation: false,
              annotations: const [ChartAnnotation(x: 1, y: 5, text: 'Peak')],
              categories: const ['a', 'b'],
              series: const [ComboSeries(name: 's', color: Colors.blue, values: [2, 5])],
            ),
        'candlestick': (c) => CandlestickChart2D(
              controller: c,
              enableAnimation: false,
              annotations: [ChartAnnotation.at(DateTime(2026, 3, 3), y: 103, text: 'Peak')],
              candles: [
                for (int i = 0; i < 5; i++)
                  Candle(time: DateTime(2026, 3, 2 + i), open: 100, high: 104, low: 98, close: 102),
              ],
            ),
      };
      for (final entry in charts.entries) {
        final c = ChartController();
        await tester.pumpWidget(_host(entry.value(c)));
        await tester.pumpAndSettle();
        final svg = c.toSvg()!;
        expect(svg, contains('>Peak<'), reason: '${entry.key} annotation');
        if (entry.key == 'line') expect(svg, contains('>5<'), reason: 'value label');
        if (entry.key == 'scatter') expect(svg, contains('>P0<'), reason: 'point label');
        c.dispose();
      }
    });
  });

  group('crosshair sync', () {
    testWidgets('hovering one line chart shows the crosshair on the other', (tester) async {
      final sync = ChartCrosshairSync();
      addTearDown(sync.dispose);
      const data = [ChartPoint(x: 0, y: 1), ChartPoint(x: 1, y: 4), ChartPoint(x: 2, y: 2)];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            for (final name in ['top', 'bottom'])
              SizedBox(
                width: 400,
                height: 300,
                child: LineChart2D(
                  crosshairSync: sync,
                  showLegend: false,
                  enableAnimation: false,
                  series: [XySeries(name: name, color: Colors.blue, data: data)],
                ),
              ),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
      Iterable<SyncCrosshairPainter> synced() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<SyncCrosshairPainter>();
      expect(synced(), isEmpty);

      // Top chart: the point x = 1 has y = 4, the top of the 0–4 axis (y ≈ 12).
      final mouse = await _hover(tester, const Offset(48 + 340 / 2, 16));
      expect(sync.x, 1);
      expect(synced(), hasLength(1), reason: 'only the other chart mirrors it');
      expect(synced().single.x, 1);
      expect(synced().single.dots, hasLength(1));

      await mouse.moveTo(const Offset(398, 700)); // off both charts
      await tester.pump();
      expect(sync.x, isNull);
      expect(synced(), isEmpty);
    });

    testWidgets('bar charts highlight the synced category; candlesticks follow time', (tester) async {
      final sync = ChartCrosshairSync();
      addTearDown(sync.dispose);
      await tester.pumpWidget(_host(BarChart2D(
        crosshairSync: sync,
        enableAnimation: false,
        categories: const ['a', 'b', 'c'],
        series: const [CategorySeries(name: 's', color: Colors.blue, values: [1, 2, 3])],
      )));
      sync.update('elsewhere', 1);
      await tester.pump();
      expect(tester.widgetList<CustomPaint>(find.byType(CustomPaint)).map((w) => w.painter).whereType<SyncBandPainter>(),
          hasLength(1));

      Candle? hovered;
      final candles = [
        for (int i = 0; i < 5; i++) Candle(time: DateTime(2026, 3, 2 + i), open: 100, high: 104, low: 98, close: 102),
      ];
      await tester.pumpWidget(_host(CandlestickChart2D(
        crosshairSync: sync,
        enableAnimation: false,
        candles: candles,
        onCandleHover: (c) => hovered = c,
      )));
      sync.update('elsewhere', DateTime(2026, 3, 4).millisecondsSinceEpoch.toDouble());
      await tester.pump();
      expect(tester.takeException(), isNull);
      // Our own hover publishes the hovered candle's time.
      await _hover(tester, const Offset(200, 120));
      expect(hovered, isNotNull);
      expect(sync.x, hovered!.time.millisecondsSinceEpoch.toDouble());
    });
  });

  testWidgets('SVG export: well-formed document with text, shapes and clips', (tester) async {
    final c = ChartController();
    addTearDown(c.dispose);
    await tester.pumpWidget(_host(LineChart2D(
      controller: c,
      title: 'Revenue & costs',
      enableAnimation: false,
      series: const [
        XySeries(name: 'Revenue', color: Colors.indigo, data: [ChartPoint(x: 0, y: 2), ChartPoint(x: 1, y: 5)]),
      ],
    )));
    await tester.pumpAndSettle();
    final svg = c.toSvg(background: Colors.white)!;
    expect(svg, startsWith('<svg xmlns="http://www.w3.org/2000/svg" width="400" height="300"'));
    expect(svg.trimRight(), endsWith('</svg>'));
    expect(svg, contains('>Revenue &amp; costs<'), reason: 'title, XML-escaped');
    expect(svg, contains('>Revenue<'), reason: 'legend label');
    expect(svg, contains('<path d="M'), reason: 'the series line');
    expect(svg, contains('<circle'), reason: 'points / legend dot');
    expect(svg, contains('<clipPath'), reason: 'the plot clip');
    expect('<g '.allMatches(svg).length, '</g>'.allMatches(svg).length);
    expect(ChartController().toSvg(), isNull, reason: 'unattached controller');
  });
}
