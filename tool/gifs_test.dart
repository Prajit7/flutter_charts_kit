// Records the README's animated GIFs by driving real charts with simulated
// input. Run with: flutter test tool/gifs_test.dart   (writes doc/media/*.gif)
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_charts_kit/flutter_charts_kit.dart';

import 'gif_encoder.dart';
// ignore: avoid_relative_lib_imports
import '../example/lib/options_charts.dart' show sampleCandles;

Future<void> _loadFonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts';
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      final bytes = File('$dir/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await family('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
}

const _size = Size(720, 420);
const _shot = ValueKey('gif');

Widget _stage(Widget child, {bool dark = false}) {
  final theme = dark ? ChartTheme.trading.copyWith(fontFamily: 'Roboto') : const ChartTheme(fontFamily: 'Roboto');
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(fontFamily: 'Roboto'),
    home: ChartThemeScope(
      theme: theme,
      child: Scaffold(
        body: RepaintBoundary(
          key: _shot,
          child: ColoredBox(
            color: dark ? theme.backgroundColor : Colors.white,
            child: Padding(padding: const EdgeInsets.all(12), child: child),
          ),
        ),
      ),
    ),
  );
}

/// Collects frames from the stage boundary.
class _Recorder {
  final WidgetTester tester;
  final GifEncoder gif = GifEncoder(_size.width.toInt(), _size.height.toInt(), delay: 5);
  _Recorder(this.tester);

  Future<void> frame([int repeat = 1]) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_shot));
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
      image.dispose();
      for (int i = 0; i < repeat; i++) {
        gif.addFrame(bytes);
      }
    });
  }

  void save(String name) {
    Directory('doc/media').createSync(recursive: true);
    File('doc/media/$name').writeAsBytesSync(gif.encode());
  }
}

Future<void> _prepare(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = _size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('drawing tools', (tester) async {
    final drawings = ChartDrawingController(magnet: true);
    await _prepare(
      tester,
      _stage(
        CandlestickChart2D(
          title: 'Drawing tools',
          subtitle: 'Trend line, Fibonacci retracement and a price level',
          candles: sampleCandles(count: 90),
          enableAnimation: false,
          showVolume: true,
          drawingController: drawings,
          priceFormatter: (v) => v.toStringAsFixed(0),
        ),
        dark: true,
      ),
    );
    final rec = _Recorder(tester);
    await rec.frame(8);
    Future<void> drag(Offset from, Offset to, int steps) async {
      final g = await tester.startGesture(from);
      await tester.pump();
      for (int i = 1; i <= steps; i++) {
        await g.moveTo(Offset.lerp(from, to, i / steps)!);
        await tester.pump();
        await rec.frame();
      }
      await g.up();
      await tester.pump();
      await rec.frame(8);
    }

    drawings.startDrawing(DrawingTool.trendLine);
    await tester.pump();
    await drag(const Offset(90, 330), const Offset(560, 175), 14);
    drawings.startDrawing(DrawingTool.fibonacci);
    await tester.pump();
    await drag(const Offset(170, 335), const Offset(470, 120), 14);
    drawings.startDrawing(DrawingTool.horizontalLine);
    await tester.tapAt(const Offset(400, 140));
    await tester.pump();
    await rec.frame(14);
    rec.save('drawing_tools.gif');
    await tester.pumpWidget(const SizedBox());
    drawings.dispose();
  });

  testWidgets('linked crosshairs', (tester) async {
    final sync = ChartCrosshairSync();
    final start = DateTime(2026, 1, 5);
    List<ChartPoint> wave(double base, double trend, double amp, double phase) => [
          for (int d = 0; d < 60; d++)
            ChartPoint.at(start.add(Duration(days: d)), y: base + trend * d / 60 + amp * math.sin(d / 5 + phase)),
        ];
    await _prepare(
      tester,
      _stage(Column(children: [
        Expanded(
          child: LineChart2D(
            title: 'Linked crosshairs',
            subtitle: 'Hover one chart; the other follows',
            crosshairSync: sync,
            xAxisType: ChartAxisType.time,
            showPoints: false,
            showLegend: false,
            enableAnimation: false,
            includeZero: false,
            series: [XySeries(name: 'Revenue', color: Colors.indigo, data: wave(120, 80, 18, 0))],
          ),
        ),
        Expanded(
          child: LineChart2D(
            crosshairSync: sync,
            xAxisType: ChartAxisType.time,
            showPoints: false,
            showLegend: false,
            enableAnimation: false,
            includeZero: false,
            series: [XySeries(name: 'Margin %', color: Colors.teal, data: wave(22, -6, 2.5, 1.5))],
          ),
        ),
      ])),
    );
    final rec = _Recorder(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(80, 140));
    for (int i = 0; i <= 30; i++) {
      final top = i < 16;
      final x = 80 + (i % 16) * 36.0;
      await mouse.moveTo(Offset(x, top ? 140 : 320));
      await tester.pump();
      await rec.frame();
    }
    await rec.frame(6);
    rec.save('linked_crosshairs.gif');
    await tester.pumpWidget(const SizedBox());
    sync.dispose();
  });

  testWidgets('sunburst drill-down', (tester) async {
    await _prepare(
      tester,
      _stage(const SunburstChart2D(
        title: 'Drill-down',
        subtitle: 'Tap a ring to zoom in, the centre to zoom out',
        animationDuration: Duration(milliseconds: 500),
        nodes: [
          TreemapNode(label: 'Engineering', children: [
            TreemapNode(label: 'Salaries', value: 820),
            TreemapNode(label: 'Cloud', children: [
              TreemapNode(label: 'Compute', value: 150),
              TreemapNode(label: 'Storage', value: 90),
              TreemapNode(label: 'Network', value: 40),
            ]),
            TreemapNode(label: 'Tools', value: 90),
          ]),
          TreemapNode(label: 'Marketing', children: [
            TreemapNode(label: 'Ads', value: 300),
            TreemapNode(label: 'Events', value: 120),
          ]),
          TreemapNode(label: 'Sales', value: 380),
        ],
      )),
    );
    final rec = _Recorder(tester);
    await rec.frame(10);
    Future<void> tapAndRecord(Offset at) async {
      await tester.tapAt(at);
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 45));
        await rec.frame();
      }
      await tester.pumpAndSettle();
      await rec.frame(12);
    }

    // The inner ring's Engineering segment sits to the upper right of centre.
    final centre = tester.getCenter(find.byType(SunburstChart2D)) + const Offset(0, 24);
    await tapAndRecord(centre + const Offset(70, -10));
    await tapAndRecord(centre);
    rec.save('sunburst_drilldown.gif');
  });
}
