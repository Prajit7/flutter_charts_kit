// Rough performance numbers for the README. Run with:
//   flutter test tool/benchmark_test.dart      (writes doc/benchmarks.md)
//
// flutter_test runs in debug mode (JIT) and does not rasterise on a GPU, so
// these measure build + layout + paint recording only, and are pessimistic
// compared with a release build; use them to compare sizes, not as
// absolute frame times.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_charts_kit/flutter_charts_kit.dart';
import 'package:flutter_charts_kit/src/chart2d/downsample.dart' show lttbIndices;

final _rows = <(String, String, String)>[];

double _median(List<double> v) => (v..sort())[v.length ~/ 2];

Widget _host(Widget chart) => MaterialApp(home: Scaffold(body: SizedBox(width: 1000, height: 500, child: chart)));

/// Median wall time (ms) of [frames] pumps after [action], each forcing a
/// full rebuild + layout + paint of the chart.
Future<double> _time(WidgetTester tester, Future<void> Function(int i) action, {int frames = 7}) async {
  final times = <double>[];
  for (int i = 0; i < frames; i++) {
    final sw = Stopwatch()..start();
    await action(i);
    sw.stop();
    times.add(sw.elapsedMicroseconds / 1000);
  }
  return _median(times);
}

List<ChartPoint> _walk(int n) {
  final rnd = math.Random(1);
  var y = 100.0;
  return [for (int i = 0; i < n; i++) ChartPoint(x: i.toDouble(), y: y += rnd.nextDouble() - 0.5)];
}

void main() {
  tearDownAll(() {
    final b = StringBuffer()
      ..writeln('# Benchmarks')
      ..writeln()
      ..writeln('Measured with `flutter test tool/benchmark_test.dart` on ${Platform.operatingSystem} '
          '(Dart ${Platform.version.split(' ').first}, debug/JIT, no GPU rasterisation).')
      ..writeln('Each figure is the median of 7 runs of build + layout + paint recording for a 1000×500 chart.')
      ..writeln('Release builds are several times faster; compare rows, not absolute numbers.')
      ..writeln()
      ..writeln('| Scenario | Size | Median time |')
      ..writeln('|---|---|---|');
    for (final (a, n, t) in _rows) {
      b.writeln('| $a | $n | $t |');
    }
    Directory('doc').createSync(recursive: true);
    File('doc/benchmarks.md').writeAsStringSync(b.toString());
  });

  for (final n in [1000, 10000, 100000, 1000000]) {
    testWidgets('line chart, $n points', (tester) async {
      final series = [XySeries(name: 'walk', color: Colors.indigo, data: _walk(n))];
      // Alternate between two identical-but-distinct lists so every pump
      // is a genuine data update (no caching shortcuts).
      final copies = [series, [XySeries(name: 'walk', color: Colors.indigo, data: [...series.first.data])]];
      final t = await _time(tester, (i) async {
        await tester.pumpWidget(_host(LineChart2D(series: copies[i % 2], enableAnimation: false, showPoints: false)));
      });
      _rows.add(('Line chart: first paint / data update', '${_fmt(n)} points', '${t.toStringAsFixed(1)} ms'));

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(200, 200));
      final h = await _time(tester, (i) async {
        await mouse.moveTo(Offset(200.0 + i * 37, 220));
        await tester.pump();
      });
      _rows.add(('Line chart: hover (tooltip + crosshair)', '${_fmt(n)} points', '${h.toStringAsFixed(1)} ms'));
    });
  }

  testWidgets('scatter, 50k points', (tester) async {
    final rnd = math.Random(2);
    final data = [for (int i = 0; i < 50000; i++) ChartPoint(x: rnd.nextDouble() * 100, y: rnd.nextDouble() * 100)];
    final t = await _time(tester, (i) async {
      await tester.pumpWidget(_host(ScatterChart2D(
        enableAnimation: false,
        series: [XySeries(name: 's$i', color: Colors.teal, data: data)],
      )));
    });
    _rows.add(('Scatter chart: first paint', '50k points', '${t.toStringAsFixed(1)} ms'));
  });

  testWidgets('candlestick, 5k candles + indicators', (tester) async {
    final rnd = math.Random(3);
    var p = 100.0;
    final candles = [
      for (int i = 0; i < 5000; i++)
        () {
          final o = p, c = p += rnd.nextDouble() - 0.5;
          return Candle(
            time: DateTime(2020).add(Duration(hours: i)),
            open: o,
            high: math.max(o, c) + rnd.nextDouble(),
            low: math.min(o, c) - rnd.nextDouble(),
            close: c,
            volume: 1000 + rnd.nextDouble() * 500,
          );
        }(),
    ];
    const indicators = [MovingAverageIndicator(), BollingerBandsIndicator(), RsiIndicator(), MacdIndicator()];
    final t = await _time(tester, (i) async {
      await tester.pumpWidget(_host(CandlestickChart2D(
        candles: i.isEven ? candles : [...candles],
        showVolume: true,
        enableAnimation: false,
        visibleCandles: 300,
        indicators: indicators,
      )));
    });
    _rows.add(('Candlestick: data update (indicators recomputed)', '5k candles, 4 indicators', '${t.toStringAsFixed(1)} ms'));

    final pan = await _time(tester, (i) async {
      await tester.drag(find.byType(CandlestickChart2D), Offset(i.isEven ? 60 : -60, 0));
      await tester.pump();
    });
    _rows.add(('Candlestick: pan (drag gesture + repaint)', '5k candles, 300 visible', '${pan.toStringAsFixed(1)} ms'));
  });

  test('LTTB downsampling', () {
    final data = _walk(1000000);
    final t = <double>[];
    for (int i = 0; i < 5; i++) {
      final sw = Stopwatch()..start();
      lttbIndices(data.length, (i) => data[i].x, (i) => data[i].y, 2000);
      t.add(sw.elapsedMicroseconds / 1000);
    }
    _rows.add(('LTTB downsampling (used by line charts)', '1M → 2,000 points', '${_median(t).toStringAsFixed(1)} ms'));
  });
}

String _fmt(int n) => n >= 1000000 ? '${n ~/ 1000000}M' : (n >= 1000 ? '${n ~/ 1000}k' : '$n');
