import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_charts_kit/flutter_charts_kit.dart';

Widget _host(Widget chart, {double w = 600, double h = 400}) => MaterialApp(
      home: Scaffold(body: Align(alignment: Alignment.topLeft, child: SizedBox(width: w, height: h, child: chart))),
    );

Future<void> _hover(WidgetTester tester, Offset at) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: at);
  await mouse.moveTo(at);
  await tester.pump();
}

List<Candle> _candles(int n, {double start = 100, double step = 1}) => [
      for (int i = 0; i < n; i++)
        Candle(
          time: DateTime(2026, 1, 1).add(Duration(days: i)),
          open: start + i * step,
          high: start + i * step + 2,
          low: start + i * step - 2,
          close: start + (i + 1) * step,
          volume: 1000,
        ),
    ];

void main() {
  group('OptionMath', () {
    test('Black-Scholes matches textbook values and put-call parity', () {
      expect(OptionMath.normCdf(0), closeTo(0.5, 1e-9));
      expect(OptionMath.normCdf(1.96), closeTo(0.975, 1e-4));
      final call = OptionMath.blackScholes(type: OptionType.call, spot: 100, strike: 100, years: 1, volatility: 0.2, rate: 0.05);
      final put = OptionMath.blackScholes(type: OptionType.put, spot: 100, strike: 100, years: 1, volatility: 0.2, rate: 0.05);
      expect(call, closeTo(10.4506, 1e-3));
      expect(put, closeTo(5.5735, 1e-3));
      expect(call - put, closeTo(100 - 100 * 0.951229, 1e-3), reason: 'C - P = S - K·e^(-rT)');
      final g = OptionMath.greeks(type: OptionType.call, spot: 100, strike: 100, years: 1, volatility: 0.2, rate: 0.05);
      expect(g.delta, closeTo(0.6368, 1e-3));
      expect(g.gamma, closeTo(0.01876, 1e-4));
      expect(g.vega, closeTo(0.3752, 1e-3));
      // At expiry: intrinsic only.
      expect(OptionMath.blackScholes(type: OptionType.put, spot: 90, strike: 100, years: 0, volatility: 0.2), 10);
    });

    test('implied volatility round-trips and rejects impossible prices', () {
      for (final v in [0.08, 0.2, 0.65]) {
        final p = OptionMath.blackScholes(type: OptionType.put, spot: 24480, strike: 24000, years: 20 / 365, volatility: v);
        expect(OptionMath.impliedVolatility(price: p, type: OptionType.put, spot: 24480, strike: 24000, years: 20 / 365),
            closeTo(v, 1e-5));
      }
      expect(OptionMath.impliedVolatility(price: 0.5, type: OptionType.call, spot: 120, strike: 100, years: 0.5), isNull,
          reason: 'below intrinsic');
    });

    test('strategy payoff, breakevens and extremes', () {
      const straddle = [
        OptionLeg.call(strike: 100, premium: 6, quantity: -1, lotSize: 10),
        OptionLeg.put(strike: 100, premium: 4, quantity: -1, lotSize: 10),
      ];
      expect(OptionMath.payoffAtExpiry(straddle, 100), 100);
      expect(OptionMath.breakevens(straddle), [90, 110]);
      expect(OptionMath.maxProfit(straddle), 100);
      expect(OptionMath.maxLoss(straddle), isNull, reason: 'naked short call: unlimited loss');
      expect(OptionMath.netPremium(straddle), 100, reason: 'credit');

      const bullCall = [
        OptionLeg.call(strike: 100, premium: 5, quantity: 1),
        OptionLeg.call(strike: 110, premium: 2, quantity: -1),
      ];
      expect(OptionMath.maxProfit(bullCall), 7);
      expect(OptionMath.maxLoss(bullCall), -3);
      expect(OptionMath.breakevens(bullCall), [103]);

      const longStock = [OptionLeg.underlying(price: 50)];
      expect(OptionMath.maxProfit(longStock), isNull);
      expect(OptionMath.maxLoss(longStock), -50);
      expect(OptionMath.breakevens(longStock), [50]);

      // Before expiry a long call is worth more than its intrinsic value.
      const long = [OptionLeg.call(strike: 100, premium: 0)];
      expect(OptionMath.payoffBeforeExpiry(long, 100, daysToExpiry: 30, volatility: 0.2), greaterThan(0));
    });

    test('max pain and expected move', () {
      expect(OptionMath.maxPain([(90, 10, 500), (100, 200, 200), (110, 500, 10)]), 100);
      final (lo, hi) = OptionMath.expectedMove(100, 0.2, 365);
      expect(lo, closeTo(81.87, 0.01));
      expect(hi, closeTo(122.14, 0.01));
    });
  });

  group('candle types', () {
    test('Heikin-Ashi averages bars', () {
      final ha = CandleTransforms.heikinAshi(_candles(3));
      expect(ha.first.close, (100 + 102 + 98 + 101) / 4);
      expect(ha.first.open, (100 + 101) / 2);
      expect(ha[1].open, (ha[0].open + ha[0].close) / 2);
      for (final c in ha) {
        expect(c.high, greaterThanOrEqualTo(c.open > c.close ? c.open : c.close));
      }
    });

    test('Renko bricks need a full box, reversals two', () {
      Candle c(int day, double close) => Candle(time: DateTime(2026, 1, day), open: close, high: close, low: close, close: close);
      final bricks = CandleTransforms.renko([c(1, 100), c(2, 104), c(3, 112), c(4, 107), c(5, 99)], boxSize: 5);
      // 100 → 105 → 110 (up), then 107 doesn't reverse, 99 reverses: 105 → 100.
      expect([for (final b in bricks) (b.open, b.close)], [(100, 105), (105, 110), (105, 100)]);
      expect(bricks.last.time, DateTime(2026, 1, 5));
      expect(CandleTransforms.defaultRenkoBox(_candles(30)), 5, reason: 'ATR 4 → nice 5');
    });

    test('line break reverses only past the last lines', () {
      Candle c(int day, double close) => Candle(time: DateTime(2026, 1, day), open: close, high: close, low: close, close: close);
      final lines = CandleTransforms.lineBreak([c(1, 10), c(2, 11), c(3, 12), c(4, 13), c(5, 11.5), c(6, 9.5)]);
      expect([for (final l in lines) (l.open, l.close)], [(10, 11), (11, 12), (12, 13), (12, 9.5)]);
    });

    testWidgets('candlestick chart renders each type', (tester) async {
      for (final type in CandleType.values) {
        await tester.pumpWidget(_host(CandlestickChart2D(candles: _candles(40), candleType: type, enableAnimation: false)));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$type');
      }
      expect(find.bySemanticsLabel(RegExp('Line break chart')), findsOneWidget);
    });
  });

  test('volume profile: point of control and value area', () {
    final candles = [
      for (int i = 0; i < 10; i++)
        Candle(time: DateTime(2026, 1, i + 1), open: 100, high: 101, low: 99, close: 100.5, volume: 100),
      Candle(time: DateTime(2026, 1, 20), open: 109, high: 110, low: 108, close: 108.5, volume: 50),
    ];
    final r = VolumeProfileResult.compute(candles, low: 98, high: 110, bins: 12)!;
    expect(r.pointOfControl, inInclusiveRange(99, 101));
    expect(r.totalVolume, closeTo(1050, 1e-6));
    var inside = 0.0;
    for (int b = r.valueAreaLowIndex; b <= r.valueAreaHighIndex; b++) {
      inside += r.bins[b].volume;
    }
    expect(inside, greaterThanOrEqualTo(0.7 * 1050));
    expect(r.bins[11].downVolume, greaterThan(0), reason: 'the down candle at 108–110');
  });

  testWidgets('payoff chart: summary and hover read-out', (tester) async {
    await tester.pumpWidget(_host(const OptionPayoffChart2D(
      spot: 100,
      daysToExpiry: 10,
      enableAnimation: false,
      legs: [
        OptionLeg.call(strike: 100, premium: 5, quantity: 1),
        OptionLeg.call(strike: 110, premium: 2, quantity: -1),
      ],
    )));
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('max profit \\+7, max loss -3.*breakevens 103')), findsOneWidget);
    await _hover(tester, const Offset(300, 200));
    expect(find.textContaining('Expiry'), findsOneWidget);
    expect(find.textContaining('Today'), findsOneWidget);
    await tester.pumpWidget(_host(const OptionPayoffChart2D(spot: 100, legs: [])));
    expect(find.text('Add a leg to see the payoff'), findsOneWidget);
  });

  testWidgets('open interest: summary, tap, sideways scroll', (tester) async {
    OptionStrikeData? tapped;
    final strikes = [
      for (int i = 0; i < 40; i++)
        OptionStrikeData(strike: 1000 + i * 10.0, callOI: 100.0 + i, putOI: 140.0 - i, callOIChange: 5, putOIChange: -3),
    ];
    await tester.pumpWidget(_host(OpenInterestChart2D(
      strikes: strikes,
      spot: 1195,
      visibleStrikes: 10,
      onStrikeTap: (s) => tapped = s,
    )));
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('40 strikes.*PCR')), findsOneWidget);
    // The default window is centred on the strike nearest spot (1190/1200).
    await tester.tapAt(const Offset(320, 200));
    await tester.pump();
    expect(tapped!.strike, inInclusiveRange(1180, 1210));
    expect(find.text('Strike ${tapped!.strike.toInt()}'), findsOneWidget);
    final before = tapped!.strike;
    await tester.drag(find.byType(OpenInterestChart2D), const Offset(300, 0));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(320, 200));
    await tester.pump();
    expect(tapped!.strike, lessThan(before), reason: 'dragging right reveals lower strikes');

    await tester.pumpWidget(_host(OpenInterestChart2D(strikes: strikes, view: OpenInterestView.change)));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('market depth: sides, spread and hover', (tester) async {
    await tester.pumpWidget(_host(const MarketDepthChart2D(
      enableAnimation: false,
      bids: [DepthLevel(99, 10), DepthLevel(98, 20), DepthLevel(97, 30)],
      asks: [DepthLevel(103, 30), DepthLevel(101, 10), DepthLevel(102, 20)],
    )));
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('mid 100.*spread 2.*bids 60 over 3 levels.*asks 60')), findsOneWidget);
    await _hover(tester, const Offset(42, 300)); // left edge: beyond the deepest bid
    expect(find.textContaining('Bid'), findsOneWidget);
    expect(find.textContaining('Total 60'), findsOneWidget);
    await tester.pumpWidget(_host(const MarketDepthChart2D(bids: [], asks: [])));
    expect(find.text('Order book is empty'), findsOneWidget);
  });

  testWidgets('volatility smile skips invalid IVs', (tester) async {
    await tester.pumpWidget(_host(VolatilitySmileChart2D(
      spot: 100,
      enableAnimation: false,
      smiles: [
        VolatilitySmile(label: 'W', color: Colors.blue, points: {90: 0.2, 100: 0.15, 110: null, 120: double.nan, 130: 0.18}),
      ],
    )));
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('W: 3 values')), findsOneWidget);
  });

  group('drawing tools', () {
    Future<ChartDrawingController> pumpChart(WidgetTester tester) async {
      final c = ChartDrawingController();
      addTearDown(c.dispose);
      await tester.pumpWidget(_host(CandlestickChart2D(
        candles: _candles(40),
        drawingController: c,
        enableAnimation: false,
      )));
      await tester.pump();
      return c;
    }

    testWidgets('drag draws a trend line; tap selects; Delete removes', (tester) async {
      final c = await pumpChart(tester);
      c.startDrawing(DrawingTool.trendLine);
      await tester.dragFrom(const Offset(120, 250), const Offset(200, -100));
      await tester.pump();
      expect(c.drawings, hasLength(1));
      final d = c.drawings.single;
      expect(d.tool, DrawingTool.trendLine);
      expect(d.points, hasLength(2));
      expect(d.points[1].price, greaterThan(d.points[0].price), reason: 'dragged upward');
      expect(d.points[1].time.isAfter(d.points[0].time), isTrue);
      expect(c.activeTool, isNull, reason: 'one drawing per arm by default');
      expect(c.selectedId, d.id);

      // Tap empty space deselects; tapping the line's middle selects it.
      await tester.tapAt(const Offset(500, 60));
      await tester.pump();
      expect(c.selectedId, isNull);
      await tester.tapAt(const Offset(220, 200));
      await tester.pump();
      expect(c.selectedId, d.id);

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(c.drawings, isEmpty);
    });

    testWidgets('click-click draws; one click places a level; drag moves', (tester) async {
      final c = await pumpChart(tester);
      c.startDrawing(DrawingTool.fibonacci);
      await tester.tapAt(const Offset(100, 280));
      await tester.pump();
      expect(c.drawings, isEmpty, reason: 'waiting for the second point');
      await tester.tapAt(const Offset(300, 80));
      await tester.pump();
      expect(c.drawings.single.tool, DrawingTool.fibonacci);
      final fib = c.drawings.single;
      expect(fib.fibonacciPrice(0), fib.points[1].price);
      expect(fib.fibonacciPrice(1), fib.points[0].price);

      c.startDrawing(DrawingTool.horizontalLine);
      await tester.tapAt(const Offset(250, 150));
      await tester.pump();
      expect(c.drawings, hasLength(2));
      final level = c.drawings.last;

      // Drag the level's body down: its price drops.
      await tester.dragFrom(const Offset(400, 150), const Offset(0, 60));
      await tester.pump();
      expect(c.drawings.last.points.single.price, lessThan(level.points.single.price));
      expect(c.drawings.first.points, fib.points, reason: 'other drawings untouched');
    });

    testWidgets('Escape cancels; JSON round-trips', (tester) async {
      final c = await pumpChart(tester);
      c.startDrawing(DrawingTool.rectangle);
      await tester.tapAt(const Offset(100, 100));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(c.activeTool, isNull);
      await tester.tapAt(const Offset(300, 200));
      await tester.pump();
      expect(c.drawings, isEmpty);

      c.add(ChartDrawing(
        id: 'r1',
        tool: DrawingTool.ray,
        color: const Color(0xFF123456),
        points: [DrawingPoint(DateTime(2026, 1, 5), 104.5), DrawingPoint(DateTime(2026, 3, 1), 150)],
      ));
      final saved = jsonEncode(c.toJson());
      final restored = ChartDrawingController()..loadJson(jsonDecode(saved) as List);
      addTearDown(restored.dispose);
      final r = restored.drawings.single;
      expect((r.id, r.tool, r.color), ('r1', DrawingTool.ray, const Color(0xFF123456)));
      expect(r.points, c.drawings.single.points);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'a point beyond the last candle extrapolates');
    });
  });
}
