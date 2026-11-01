import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_charts_kit/flutter_charts_kit.dart';
import 'package:flutter_charts_kit/src/chart2d/downsample.dart';

Widget _host(Widget chart) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 400, height: 300, child: chart),
        ),
      ),
    );

XySeries _bigSeries(int n) => XySeries(
      name: 'Big',
      color: Colors.blue,
      data: [for (int i = 0; i < n; i++) ChartPoint(x: i.toDouble(), y: math.sin(i / 500) * 100 + (i % 97 == 0 ? 80 : 0))],
    );

/// The picture layer under the repaint boundary around a chart's data layer
/// (the first CustomPaint inside [chart]). Repainting the boundary replaces
/// it; reusing the cached paint keeps the same instance.
Layer? _dataLayerPicture(WidgetTester tester, Finder chart) {
  final dataPaint = find.descendant(of: chart, matching: find.byType(CustomPaint)).first;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.ancestor(of: dataPaint, matching: find.byType(RepaintBoundary)).first,
  );
  return boundary.debugLayer?.firstChild;
}

void main() {
  group('lttbIndices', () {
    test('keeps the ends, returns the threshold count, ascending', () {
      final ys = [for (int i = 0; i < 1000; i++) math.sin(i / 20)];
      final idx = lttbIndices(ys.length, (i) => i.toDouble(), (i) => ys[i], 100);
      expect(idx, hasLength(100));
      expect(idx.first, 0);
      expect(idx.last, 999);
      for (int i = 1; i < idx.length; i++) {
        expect(idx[i], greaterThan(idx[i - 1]));
      }
    });

    test('keeps isolated spikes that every-nth sampling would drop', () {
      final ys = List<double>.filled(10000, 0)..[5003] = 100..[7777] = -100;
      final idx = lttbIndices(ys.length, (i) => i.toDouble(), (i) => ys[i], 200);
      expect(idx, containsAll([5003, 7777]));
    });

    test('returns everything when already under the threshold', () {
      expect(lttbIndices(5, (i) => i.toDouble(), (i) => 0, 10), [0, 1, 2, 3, 4]);
    });
  });

  testWidgets('LineChart2D renders 200k points and hover still finds them', (tester) async {
    ChartPoint? hovered;
    await tester.pumpWidget(_host(LineChart2D(
      series: [_bigSeries(200000)],
      showLegend: false,
      enableAnimation: false,
      onPointHover: (_, p) => hovered = p,
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(200, 134));
    await mouse.moveTo(const Offset(220, 134));
    await tester.pump();
    expect(hovered, isNotNull);
  });

  testWidgets('hovering repaints only the overlay, not the data layer', (tester) async {
    for (final chart in <Widget>[
      LineChart2D(series: [_bigSeries(5000)], showLegend: false, enableAnimation: false),
      ScatterChart2D(series: [_bigSeries(5000)], showLegend: false, enableAnimation: false),
    ]) {
      await tester.pumpWidget(_host(chart));
      await tester.pumpAndSettle();
      final finder = find.byWidget(chart);
      final before = _dataLayerPicture(tester, finder);
      expect(before, isNotNull);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(100, 100));
      for (int x = 100; x < 300; x += 20) {
        await mouse.moveTo(Offset(x.toDouble(), 134));
        await tester.pump();
      }
      await mouse.removePointer();
      expect(identical(_dataLayerPicture(tester, finder), before), isTrue,
          reason: '${chart.runtimeType} repainted its data on hover');
    }
  });

  group('updateAnimation', () {
    Widget line(List<double> ys, ChartUpdateAnimation mode) => _host(LineChart2D(
          updateAnimation: mode,
          showLegend: false,
          series: [
            XySeries(name: 'A', color: Colors.blue, data: [
              for (int i = 0; i < ys.length; i++) ChartPoint(x: i.toDouble(), y: ys[i]),
            ]),
          ],
        ));

    Future<void> zoomIn(WidgetTester tester) async {
      await tester.dragFrom(const Offset(80, 150), const Offset(200, 0));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.zoom_out_map), findsOneWidget);
    }

    testWidgets('morph and none keep the zoom when data changes', (tester) async {
      for (final mode in [ChartUpdateAnimation.morph, ChartUpdateAnimation.none]) {
        await tester.pumpWidget(line([1, 5, 3, 8, 4, 9, 2, 7], mode));
        await tester.pumpAndSettle();
        await zoomIn(tester);
        await tester.pumpWidget(line([2, 6, 4, 9, 5, 10, 3, 8], mode));
        await tester.pump(const Duration(milliseconds: 200)); // mid-morph
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.zoom_out_map), findsOneWidget, reason: '$mode');
        await tester.pumpWidget(const SizedBox()); // fresh state for the next mode
      }
    });

    testWidgets('replay resets the zoom, as before', (tester) async {
      await tester.pumpWidget(line([1, 5, 3, 8, 4, 9, 2, 7], ChartUpdateAnimation.replay));
      await tester.pumpAndSettle();
      await zoomIn(tester);
      await tester.pumpWidget(line([2, 6, 4, 9, 5, 10, 3, 8], ChartUpdateAnimation.replay));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.zoom_out_map), findsNothing);
    });

    testWidgets('BarChart2D morphs to new values', (tester) async {
      double? tapped;
      Widget bars(List<double> v) => _host(BarChart2D(
            categories: const ['A', 'B'],
            series: [CategorySeries(name: 'S', color: Colors.teal, values: v)],
            showLegend: false,
            onBarTap: (_, __, value) => tapped = value,
          ));
      await tester.pumpWidget(bars([4, 8]));
      await tester.pumpAndSettle();
      await tester.pumpWidget(bars([10, 2]));
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(130, 200)); // bar A, low on the plot
      await tester.pump();
      expect(tapped, 10);
    });
  });

  testWidgets('liveWindow shows only the latest x-range', (tester) async {
    ChartPoint? tapped;
    await tester.pumpWidget(_host(LineChart2D(
      liveWindow: 10,
      updateAnimation: ChartUpdateAnimation.none,
      showLegend: false,
      enableAnimation: false,
      onPointTap: (_, p) => tapped = p,
      series: [
        XySeries(name: 'A', color: Colors.blue, data: [
          for (int i = 0; i <= 100; i++) ChartPoint(x: i.toDouble(), y: 5),
        ]),
      ],
    )));
    await tester.pumpAndSettle();
    // The plot's left edge is the window start: x = 90.
    await tester.tapAt(const Offset(50, 134));
    await tester.pump();
    expect(tapped?.x, 90);
    // No reset button: a live window isn't a user zoom.
    expect(find.byIcon(Icons.zoom_out_map), findsNothing);
  });
}
