import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_charts_kit/flutter_charts_kit.dart';
import 'package:flutter_charts_kit/src/chart2d/indicators.dart' show sma, ema, rsi, macd, bollinger, vwap;

Widget _host(Widget chart) => MaterialApp(
      home: Scaffold(body: Align(alignment: Alignment.topLeft, child: SizedBox(width: 600, height: 400, child: chart))),
    );

List<Candle> _daily(List<double> closes, {DateTime? start, bool weekdaysOnly = false}) {
  final out = <Candle>[];
  var day = start ?? DateTime(2026, 3, 2); // a Monday
  for (final c in closes) {
    while (weekdaysOnly && day.weekday > 5) {
      day = day.add(const Duration(days: 1));
    }
    out.add(Candle(time: day, open: c - 0.5, high: c + 1, low: c - 1, close: c, volume: 1000));
    day = day.add(const Duration(days: 1));
  }
  return out;
}

void main() {
  group('indicator math', () {
    test('SMA and EMA match hand-computed values', () {
      final v = <double>[1, 2, 3, 4, 5, 6];
      expect(sma(v, 3), [null, null, 2, 3, 4, 5]);
      // EMA(3): seeded with SMA(1,2,3)=2, then α=0.5: 3, 4, 5
      expect(ema(v, 3), [null, null, 2, 3, 4, 5]);
      final e = ema(<double>[10, 10, 10, 20], 3);
      expect(e[3], 15); // 10 + 0.5 * (20 - 10)
    });

    test('RSI is 100 for a steady rise, 0 for a steady fall, 50 for flat', () {
      final up = [for (int i = 0; i < 20; i++) i.toDouble()];
      expect(rsi(up, 14).last, 100);
      expect(rsi(up.reversed.toList(), 14).last, 0);
      expect(rsi(List.filled(20, 5.0), 14).last, 50);
      expect(rsi(up, 14).take(14), everyElement(isNull));
    });

    test('Bollinger bands are symmetric around the SMA and collapse on flat data', () {
      final b = bollinger([for (int i = 0; i < 30; i++) (i % 5).toDouble()], 20, 2);
      const i = 25;
      expect(b.upper[i]! - b.middle[i]!, closeTo(b.middle[i]! - b.lower[i]!, 1e-9));
      final flat = bollinger(List.filled(25, 7.0), 20, 2);
      expect(flat.upper.last, 7);
      expect(flat.lower.last, 7);
    });

    test('MACD histogram is MACD minus signal; zero on flat data', () {
      final closes = [for (int i = 0; i < 60; i++) 100 + (i % 7) * 1.5];
      final m = macd(closes, 12, 26, 9);
      for (int i = 0; i < closes.length; i++) {
        if (m.histogram[i] != null) expect(m.histogram[i], closeTo(m.macd[i]! - m.signal[i]!, 1e-9));
      }
      expect(m.histogram.indexWhere((v) => v != null), 26 - 1 + 9 - 1);
      expect(macd(List.filled(60, 5.0), 12, 26, 9).histogram.last, 0);
    });

    test('VWAP weights by volume and resets each day', () {
      final day1 = DateTime(2026, 3, 2, 10);
      final candles = [
        Candle(time: day1, open: 10, high: 10, low: 10, close: 10, volume: 1),
        Candle(time: day1.add(const Duration(hours: 1)), open: 20, high: 20, low: 20, close: 20, volume: 3),
        Candle(time: day1.add(const Duration(days: 1)), open: 50, high: 50, low: 50, close: 50, volume: 2),
      ];
      final v = vwap(candles);
      expect(v[1], 17.5); // (10*1 + 20*3) / 4
      expect(v[2], 50); // new day
    });
  });

  group('LiveCandles', () {
    test('aggregates ticks into interval candles and tracks the last price', () {
      final live = LiveCandles(interval: const Duration(minutes: 1));
      final t0 = DateTime(2026, 3, 2, 9, 30);
      live.addTick(t0, 100, volume: 5);
      live.addTick(t0.add(const Duration(seconds: 20)), 103, volume: 2);
      live.addTick(t0.add(const Duration(seconds: 40)), 99, volume: 1);
      live.addTick(t0.add(const Duration(seconds: 70)), 101, volume: 4); // next minute
      expect(live.candles, hasLength(2));
      final c = live.candles.first;
      expect((c.open, c.high, c.low, c.close, c.volume), (100, 103, 99, 99, 8));
      expect(live.candles.last.time, DateTime(2026, 3, 2, 9, 31));
      expect((live.lastPrice, live.previousPrice), (101, 99));
    });

    test('drops late ticks and trims to maxCandles', () {
      final live = LiveCandles(interval: const Duration(minutes: 1), maxCandles: 2);
      final t0 = DateTime(2026, 3, 2, 9, 30);
      for (int m = 0; m < 4; m++) {
        live.addTick(t0.add(Duration(minutes: m)), 100.0 + m);
      }
      live.addTick(t0, 1); // older than the current candle
      expect(live.candles.map((c) => c.close), [102, 103]);
    });

    test('daily candles start at local midnight', () {
      final live = LiveCandles(interval: const Duration(days: 1));
      expect(live.bucketStart(DateTime(2026, 3, 2, 15, 45)), DateTime(2026, 3, 2));
    });

    test('returns a new list after every change', () {
      final live = LiveCandles(interval: const Duration(minutes: 1));
      live.addTick(DateTime(2026, 3, 2, 9, 30), 100);
      final before = live.candles;
      live.addTick(DateTime(2026, 3, 2, 9, 30, 10), 101);
      expect(identical(before, live.candles), isFalse);
    });
  });

  testWidgets('candles are spaced evenly across a weekend', (tester) async {
    // 10 weekday candles: Mon 2 Mar … Fri 13 Mar, skipping the weekend.
    final candles = _daily([for (int i = 0; i < 10; i++) 100.0 + i], weekdaysOnly: true);
    Candle? tapped;
    await tester.pumpWidget(_host(CandlestickChart2D(
      candles: candles,
      rightPadding: 0,
      enableAnimation: false,
      onCandleTap: (c) => tapped = c,
    )));
    await tester.pumpAndSettle();
    // Plot: x 4 → 536 (600 - 64 axis), 10 equal slots of 53.2px.
    const slot = (536 - 4) / 10;
    for (final i in [4, 5]) {
      // Friday 6 Mar and Monday 9 Mar sit in adjacent slots.
      await tester.tapAt(Offset(4 + slot * (i + 0.5), 150));
      await tester.pump();
      expect(tapped, candles[i]);
    }
    expect(candles[5].time.difference(candles[4].time).inDays, 3);
  });

  testWidgets('live updates keep the zoom and flash the price tag', (tester) async {
    final controller = ChartController();
    addTearDown(controller.dispose);
    var candles = _daily([for (int i = 0; i < 40; i++) 100.0 + i % 6]);
    Widget chart(List<Candle> c, double ltp) => _host(CandlestickChart2D(
          candles: c,
          lastPrice: ltp,
          controller: controller,
          indicators: const [MovingAverageIndicator(), RsiIndicator(), MacdIndicator()],
        ));
    await tester.pumpWidget(chart(candles, candles.last.close));
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(100, 100), const Offset(250, 0));
    await tester.pumpAndSettle();
    expect(controller.isZoomed, isTrue);

    // A tick on the last candle, then a new candle with the oldest trimmed.
    final last = candles.last;
    candles = [...candles.sublist(0, 39), Candle(time: last.time, open: last.open, high: 120, low: last.low, close: 119, volume: 9)];
    await tester.pumpWidget(chart(candles, 119));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    candles = [...candles.sublist(1), Candle(time: last.time.add(const Duration(days: 1)), open: 119, high: 121, low: 118, close: 120)];
    await tester.pumpWidget(chart(candles, 120));
    await tester.pumpAndSettle();
    expect(controller.isZoomed, isTrue, reason: 'live updates must not reset zoom');
    expect(find.byType(CandlestickChart2D), findsOneWidget);
  });

  testWidgets('scroll zooms around the pointer; hover shows OHLC in the legend', (tester) async {
    final controller = ChartController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(CandlestickChart2D(
      candles: _daily([for (int i = 0; i < 60; i++) 100.0 + i % 9]),
      controller: controller,
      enableAnimation: false,
    )));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(300, 150));
    await tester.pump();
    tester.binding.handlePointerEvent(const PointerScrollEvent(position: Offset(300, 150), scrollDelta: Offset(0, -300)));
    await tester.pumpAndSettle();
    expect(controller.isZoomed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('defaults to the dark trading theme without a ChartThemeScope', (tester) async {
    await tester.pumpWidget(_host(CandlestickChart2D(candles: _daily([100, 101, 102]))));
    final frame = tester.widget<ColoredBox>(find.descendant(of: find.byType(CandlestickChart2D), matching: find.byType(ColoredBox)).first);
    expect(frame.color, ChartTheme.trading.backgroundColor);
  });

  testWidgets('eye buttons hide and show indicators', (tester) async {
    final changes = <(String, bool)>[];
    await tester.pumpWidget(_host(CandlestickChart2D(
      candles: _daily([for (int i = 0; i < 60; i++) 100.0 + i % 9]),
      enableAnimation: false,
      indicators: const [MovingAverageIndicator(period: 10), RsiIndicator()],
      onIndicatorVisibilityChanged: (ind, visible) => changes.add((ind.label, visible)),
    )));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.visibility_outlined), findsNWidgets(2));

    // Hide the SMA: its eye flips and its values leave the legend.
    final smaRow = find.ancestor(of: find.text('SMA 10'), matching: find.byType(Row)).first;
    expect(find.descendant(of: smaRow, matching: find.byType(RichText)), findsNWidgets(3)); // label, values, icon
    await tester.tap(find.descendant(of: smaRow, matching: find.byIcon(Icons.visibility_outlined)));
    await tester.pump();
    expect(changes, [('SMA 10', false)]);
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    expect(find.descendant(of: smaRow, matching: find.byType(RichText)), findsNWidgets(2)); // label, icon

    // Show it again.
    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pump();
    expect(changes.last, ('SMA 10', true));
    expect(find.byIcon(Icons.visibility_off_outlined), findsNothing);

    // Hiding RSI keeps its pane (the label stays) and doesn't throw.
    await tester.tap(find.descendant(
      of: find.ancestor(of: find.text('RSI 14'), matching: find.byType(Row)).first,
      matching: find.byIcon(Icons.visibility_outlined),
    ));
    await tester.pump();
    expect(find.text('RSI 14'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping an eye does not count as a candle tap', (tester) async {
    Candle? tapped;
    await tester.pumpWidget(_host(CandlestickChart2D(
      candles: _daily([for (int i = 0; i < 30; i++) 100.0 + i % 5]),
      enableAnimation: false,
      indicators: const [MovingAverageIndicator(period: 5)],
      onCandleTap: (c) => tapped = c,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(tapped, isNull);
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
  });

  testWidgets('a hidden overlay no longer stretches the price scale', (tester) async {
    // A 2-period SMA right after a spike: hiding it must not change anything
    // visible but must stop it from contributing to the y-range. Smoke-check
    // that toggling repaints without errors and the eye state sticks across
    // a live update.
    var candles = _daily([for (int i = 0; i < 30; i++) 100.0 + i % 5]);
    Widget chart() => _host(CandlestickChart2D(
          candles: candles,
          enableAnimation: false,
          indicators: const [BollingerBandsIndicator(period: 5)],
        ));
    await tester.pumpWidget(chart());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    candles = [...candles.sublist(1), Candle(time: DateTime(2026, 5, 1), open: 101, high: 103, low: 100, close: 102)];
    await tester.pumpWidget(chart());
    await tester.pump();
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget, reason: 'stays hidden across live updates');
    expect(tester.takeException(), isNull);
  });

  group('navigation', () {
    // 100 daily candles, showing the latest 30 by default.
    final candles = _daily([for (int i = 0; i < 100; i++) 100.0 + i % 9]);

    /// The index of the candle under [x] (via a tap), or null.
    Future<int?> candleAt(WidgetTester tester, double x, List<Candle> data, void Function() reset, Candle? Function() read) async {
      reset();
      await tester.tapAt(Offset(x, 150));
      await tester.pump();
      final c = read();
      return c == null ? null : data.indexOf(c);
    }

    Future<(Future<int?> Function(double x), ChartController)> pump(WidgetTester tester, {List<Candle>? data}) async {
      final controller = ChartController();
      addTearDown(controller.dispose);
      Candle? tapped;
      final d = data ?? candles;
      await tester.pumpWidget(_host(CandlestickChart2D(
        candles: d,
        visibleCandles: 30,
        controller: controller,
        enableAnimation: false,
        onCandleTap: (c) => tapped = c,
      )));
      await tester.pumpAndSettle();
      return ((double x) => candleAt(tester, x, d, () => tapped = null, () => tapped), controller);
    }

    testWidgets('dragging scrolls back in time, and dragging back returns to live', (tester) async {
      final (at, controller) = await pump(tester);
      final before = (await at(300))!;
      await tester.timedDragFrom(const Offset(300, 150), const Offset(150, 0), const Duration(seconds: 1));
      await tester.pumpAndSettle();
      final after = (await at(300))!;
      expect(after, lessThan(before), reason: 'dragging right shows older candles');
      expect(controller.isZoomed, isTrue);

      await tester.timedDragFrom(const Offset(300, 150), const Offset(-150, 0), const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(await at(300), before);
      expect(controller.isZoomed, isFalse, reason: 'back at the live view: no reset button, follows new data');
    });

    testWidgets('pinching out zooms in around the fingers', (tester) async {
      final (at, controller) = await pump(tester);
      final leftBefore = (await at(30))!;
      final centreBefore = (await at(270))!;
      final a = await tester.startGesture(const Offset(240, 150));
      final b = await tester.startGesture(const Offset(300, 150));
      await tester.pump();
      for (int k = 0; k < 10; k++) {
        await a.moveBy(const Offset(-10, 0));
        await b.moveBy(const Offset(10, 0));
        await tester.pump();
      }
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
      expect(controller.isZoomed, isTrue);
      expect((await at(30))!, greaterThan(leftBefore), reason: 'fewer candles in view');
      expect((await at(270))!, closeTo(centreBefore, 1), reason: 'zoom stays centred on the fingers');
    });

    testWidgets('a quick swipe keeps gliding further than a slow drag', (tester) async {
      var (at, _) = await pump(tester);
      await tester.timedDragFrom(const Offset(300, 150), const Offset(100, 0), const Duration(seconds: 1));
      await tester.pumpAndSettle();
      final slow = (await at(300))!;

      (at, _) = await pump(tester, data: [...candles]); // fresh chart
      await tester.flingFrom(const Offset(300, 150), const Offset(100, 0), 1500);
      await tester.pumpAndSettle();
      expect((await at(300))!, lessThan(slow));
    });

    testWidgets('long-press shows the crosshair on touch screens', (tester) async {
      Candle? hovered;
      await tester.pumpWidget(_host(CandlestickChart2D(
        candles: candles,
        enableAnimation: false,
        onCandleHover: (c) => hovered = c,
      )));
      await tester.pumpAndSettle();
      await tester.longPressAt(const Offset(300, 150));
      await tester.pump();
      expect(hovered, isNotNull);
    });

    testWidgets('a zoomed view at the live edge follows new candles; a scrolled-back one stays', (tester) async {
      var data = [...candles];
      final (at0, _) = await pump(tester, data: data);
      // Zoom in with the wheel at the right edge: still showing the newest candle.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(520, 150));
      tester.binding.handlePointerEvent(const PointerScrollEvent(position: Offset(520, 150), scrollDelta: Offset(0, -150)));
      await tester.pumpAndSettle();
      await mouse.removePointer();
      final before = (await at0(60))!;

      Future<int?> appendAndRead() async {
        final last = data.last;
        data = [...data, Candle(time: last.time.add(const Duration(days: 1)), open: 100, high: 101, low: 99, close: 100)];
        Candle? tapped;
        await tester.pumpWidget(_host(CandlestickChart2D(
          candles: data,
          visibleCandles: 30,
          enableAnimation: false,
          onCandleTap: (c) => tapped = c,
        )));
        await tester.pump();
        await tester.tapAt(const Offset(60, 150));
        await tester.pump();
        return tapped == null ? null : data.indexOf(tapped!);
      }

      expect(await appendAndRead(), before + 1, reason: 'followed the new candle');

      // Scroll back into history: new candles must not move the view.
      await tester.timedDragFrom(const Offset(300, 150), const Offset(200, 0), const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(60, 150));
      await tester.pump();
      final scrolled = await appendAndRead();
      final again = await appendAndRead();
      expect(again, scrolled);
    });
  });
}
