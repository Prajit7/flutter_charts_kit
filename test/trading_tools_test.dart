import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_charts_kit/flutter_charts_kit.dart';

Widget _host(Widget chart, {double w = 600, double h = 400}) => MaterialApp(
      home: Scaffold(body: Align(alignment: Alignment.topLeft, child: SizedBox(width: w, height: h, child: chart))),
    );

/// A steady uptrend: each day opens at the previous close, +1.
List<Candle> _trend(int n, {double step = 1, DateTime? start}) => [
      for (int i = 0; i < n; i++)
        Candle(
          time: (start ?? DateTime(2026, 1, 5)).add(Duration(days: i)),
          open: 100 + i * step,
          high: 100 + i * step + 1.5 * step.abs(),
          low: 100 + i * step - 0.5 * step.abs(),
          close: 100 + (i + 1) * step,
          volume: 1000,
        ),
    ];

void main() {
  group('indicators', () {
    test('ATR and true range', () {
      final c = _trend(30);
      expect(trueRange(c).first, 2);
      // Each bar: high − low = 2, gaps ≤ 1.5 → TR = 2 everywhere.
      expect(atr(c, 14)[13], closeTo(2, 1e-9));
      expect(atr(c, 14)[29], closeTo(2, 1e-9));
      expect(atr(c, 14)[12], isNull);
    });

    test('Supertrend sits below price in an uptrend and flips on a crash', () {
      final up = _trend(40);
      final st = supertrend(up, 10, 3);
      expect(st.up.last, isTrue);
      expect(st.line.last, lessThan(up.last.close));
      final crash = [...up, for (int i = 0; i < 5; i++) Candle(time: DateTime(2026, 3, 1 + i), open: 120.0 - i * 15, high: 121.0 - i * 15, low: 100.0 - i * 15, close: 105.0 - i * 15)];
      final st2 = supertrend(crash, 10, 3);
      expect(st2.up.last, isFalse);
      expect(st2.line.last, greaterThan(crash.last.close));
    });

    test('Stochastic, ADX stay in 0–100; a steady rise reads high', () {
      final c = _trend(60);
      final s = stochastic(c, 14, 3, 3);
      final a = adx(c, 14);
      for (final v in [...s.k, ...s.d, ...a.adx, ...a.plusDi, ...a.minusDi].whereType<double>()) {
        expect(v, inInclusiveRange(0, 100));
      }
      expect(s.k.last, greaterThan(80));
      expect(a.plusDi.last, greaterThan(a.minusDi.last!));
      expect(a.adx.last, greaterThan(25), reason: 'a strong trend');
    });

    test('Ichimoku spans shift forward, lagging span back', () {
      final c = _trend(80);
      final r = ichimoku(c);
      expect(r.spanA[30], isNull, reason: 'needs 26 + 26 bars of history');
      expect(r.spanB[76], isNull);
      expect(r.spanB[77], isNotNull, reason: '52 bars, then 26 forward');
      expect(r.lagging[0], c[26].close);
      expect(r.lagging.last, isNull);
      expect(r.conversion[8], (c.sublist(0, 9).map((x) => x.high).reduce((a, b) => a > b ? a : b) + c[0].low) / 2);
    });

    test('pivot points from the previous day', () {
      final day1 = [
        Candle(time: DateTime(2026, 1, 5, 10), open: 100, high: 110, low: 95, close: 105),
        Candle(time: DateTime(2026, 1, 5, 11), open: 105, high: 108, low: 98, close: 99),
      ];
      final day2 = [Candle(time: DateTime(2026, 1, 6, 10), open: 99, high: 101, low: 97, close: 100)];
      final p = pivotPoints([...day1, ...day2], PivotPeriod.day);
      expect(p.pivot[0], isNull);
      const pp = (110 + 95 + 99) / 3;
      expect(p.pivot[2], closeTo(pp, 1e-9));
      expect(p.r1[2], closeTo(2 * pp - 95, 1e-9));
      expect(p.s1[2], closeTo(2 * pp - 110, 1e-9));
    });

    testWidgets('every new indicator renders on the chart', (tester) async {
      await tester.pumpWidget(_host(CandlestickChart2D(
        candles: _trend(90),
        enableAnimation: false,
        indicators: const [
          SupertrendIndicator(),
          IchimokuIndicator(),
          PivotPointsIndicator(period: PivotPeriod.week),
          AtrIndicator(),
          StochasticIndicator(),
          AdxIndicator(),
        ],
      ), h: 700));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('ADX 14'), findsOneWidget);
      expect(find.text('Stoch 14 3 3'), findsOneWidget);
    });
  });

  group('alerts', () {
    testWidgets('fire when the price crosses an alert line', (tester) async {
      final alerts = <DrawingAlert>[];
      final candles = _trend(30);
      final c = ChartDrawingController(drawings: [
        ChartDrawing(
          id: 'h',
          tool: DrawingTool.horizontalLine,
          color: Colors.orange,
          alert: true,
          points: [DrawingPoint(candles.first.time, 131)],
        ),
        ChartDrawing(
          id: 'quiet',
          tool: DrawingTool.horizontalLine,
          color: Colors.grey,
          points: [DrawingPoint(candles.first.time, 131)],
        ),
      ]);
      addTearDown(c.dispose);
      Widget chart(double price) => _host(CandlestickChart2D(
            candles: candles,
            lastPrice: price,
            drawingController: c,
            enableAnimation: false,
            onAlert: alerts.add,
          ));
      await tester.pumpWidget(chart(130));
      await tester.pumpWidget(chart(130.5));
      expect(alerts, isEmpty);
      await tester.pumpWidget(chart(131.2));
      await tester.pump();
      expect(alerts, hasLength(1), reason: 'only the line with alert on');
      expect(alerts.single.crossedUp, isTrue);
      expect(alerts.single.level, 131);
      await tester.pumpWidget(chart(130.9));
      await tester.pump();
      expect(alerts.last.crossedUp, isFalse);
    });

    test('trend line alerts only inside the line\'s span; toggling via setAlert', () {
      final c = ChartDrawingController(drawings: [
        ChartDrawing(id: 't', tool: DrawingTool.trendLine, color: Colors.blue, points: [
          DrawingPoint(DateTime(2026, 1, 5), 100),
          DrawingPoint(DateTime(2026, 1, 10), 110),
        ]),
      ]);
      c.setAlert('t', true);
      expect(c.drawings.single.alert, isTrue);
      expect(DrawingTool.trendLine.supportsAlerts, isTrue);
      expect(DrawingTool.fibonacci.supportsAlerts, isFalse);
      expect(ChartDrawing.fromJson(c.drawings.single.toJson()).alert, isTrue);
      c.dispose();
    });
  });

  group('new drawing tools', () {
    Future<ChartDrawingController> pump(WidgetTester tester, {bool magnet = false}) async {
      final c = ChartDrawingController(magnet: magnet, noteText: 'Support');
      addTearDown(c.dispose);
      await tester.pumpWidget(_host(CandlestickChart2D(candles: _trend(40), drawingController: c, enableAnimation: false)));
      await tester.pump();
      return c;
    }

    testWidgets('channel gets a third point; measure and note', (tester) async {
      final c = await pump(tester);
      c.startDrawing(DrawingTool.parallelChannel);
      await tester.dragFrom(const Offset(100, 300), const Offset(300, -150));
      await tester.pump();
      final ch = c.drawings.single;
      expect(ch.points, hasLength(3));
      expect(ch.points[2].price, lessThan(ch.points[0].price), reason: 'offset line starts below');

      c.startDrawing(DrawingTool.measure);
      await tester.tapAt(const Offset(150, 250));
      await tester.tapAt(const Offset(350, 120));
      await tester.pump();
      expect(c.drawings.last.tool, DrawingTool.measure);

      c.startDrawing(DrawingTool.text);
      await tester.tapAt(const Offset(200, 200));
      await tester.pump();
      expect(c.drawings.last.text, 'Support');
      expect(c.drawings.last.points, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('magnet snaps to the candle\'s nearest O/H/L/C', (tester) async {
      final c = await pump(tester, magnet: true);
      c.startDrawing(DrawingTool.horizontalLine);
      await tester.tapAt(const Offset(300, 180));
      await tester.pump();
      final p = c.drawings.single.points.single;
      final candle = _trend(40).firstWhere((x) => x.time == p.time);
      expect([candle.open, candle.high, candle.low, candle.close], contains(p.price));
    });
  });

  testWidgets('comparison: rebased line with % change labels', (tester) async {
    await tester.pumpWidget(_host(CandlestickChart2D(
      title: 'MAIN',
      candles: _trend(30),
      enableAnimation: false,
      compare: [CandleComparison(label: 'OTHER', candles: _trend(30, step: 2), color: Colors.orange)],
    )));
    await tester.pump();
    final c = ChartController();
    addTearDown(c.dispose);
    await tester.pumpWidget(_host(CandlestickChart2D(
      title: 'MAIN',
      controller: c,
      candles: _trend(30),
      enableAnimation: false,
      compare: [CandleComparison(label: 'OTHER', candles: _trend(30, step: 2), color: Colors.orange)],
    )));
    await tester.pump();
    final svg = c.toSvg()!;
    expect(svg, contains('MAIN  +'));
    expect(svg, contains('OTHER  +'));
  });

  group('options analytics', () {
    test('position Greeks sum legs with quantity and lot size', () {
      const legs = [
        OptionLeg.call(strike: 100, premium: 5, quantity: 2, lotSize: 10),
        OptionLeg.underlying(price: 100, quantity: -1, lotSize: 10),
      ];
      final g = OptionMath.positionGreeks(legs, 100, daysToExpiry: 30, volatility: 0.2);
      final single = OptionMath.greeks(type: OptionType.call, spot: 100, strike: 100, years: 30 / 365, volatility: 0.2);
      expect(g.delta, closeTo(20 * single.delta - 10, 1e-9));
      expect(g.gamma, closeTo(20 * single.gamma, 1e-12));
      expect(g.theta, closeTo(20 * single.theta, 1e-9));
    });

    testWidgets('Greeks and OI trend charts render', (tester) async {
      await tester.pumpWidget(_host(const OptionGreeksChart2D(
        spot: 100,
        daysToExpiry: 10,
        enableAnimation: false,
        legs: [OptionLeg.call(strike: 100, premium: 2, quantity: -1)],
      ), h: 600));
      await tester.pump();
      expect(find.textContaining(RegExp(r'^Delta ')), findsWidgets);
      expect(find.textContaining('Vega'), findsOneWidget);
      await tester.pumpWidget(_host(OpenInterestTrendChart2D(
        enableAnimation: false,
        snapshots: [
          for (int i = 0; i < 10; i++)
            OpenInterestSnapshot(time: DateTime(2026, 1, 5, 10, i * 5), callOI: 1000.0 + i * 10, putOI: 900.0 + i * 20),
        ],
      ), h: 600));
      await tester.pump();
      expect(find.textContaining('PCR 0.99'), findsOneWidget); // last: 1080 / 1090
      expect(tester.takeException(), isNull);
    });
  });
}
