import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_charts_kit/flutter_charts_kit.dart';
import 'package:flutter_charts_kit/src/painter.dart' show contourSegments;

Widget _host(Widget chart, {Size size = const Size(500, 400)}) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: size.width, height: size.height, child: chart),
        ),
      ),
    );

void main() {
  test('turntable projection keeps vertical lines vertical at any angle', () {
    for (final (rx, ry) in [(0.3, 0.0), (0.6, -0.7), (1.2, 2.5), (0.05, -3.0)]) {
      final p = Projector(rotationX: rx, rotationY: ry, zoom: 20, center: Offset.zero);
      // Before perspective, a vertical model line has a constant screen x.
      final bottom = p.rotate(const Point3D(40, -25, 0));
      final top = p.rotate(const Point3D(40, -25, 120));
      expect(top.x, closeTo(bottom.x, 1e-9));
      expect(top.y, lessThan(bottom.y), reason: '+z is up on screen');
    }
  });

  test('fitProjector keeps the model inside the area at the fit angle', () {
    const area = Rect.fromLTWH(10, 20, 400, 300);
    final p = fitProjector(
      area: area,
      rotationX: 0.6,
      rotationY: -0.7,
      zoom: 16,
      xMin: -200,
      xMax: 200,
      yMin: -120,
      yMax: 120,
      zMin: 0,
      zMax: 150,
      margin: 20,
    );
    for (final x in [-200.0, 200.0]) {
      for (final y in [-120.0, 120.0]) {
        for (final z in [0.0, 150.0]) {
          expect(area.deflate(19).contains(p.project(Point3D(x, y, z))), isTrue);
        }
      }
    }
    // A big model gets a camera far enough back to avoid extreme perspective.
    final big = fitProjector(
        area: area, rotationX: 0.6, rotationY: -0.7, zoom: 16, xMin: -2000, xMax: 2000, yMin: -2000, yMax: 2000, zMin: 0, zMax: 500);
    expect(big.cameraDistance, greaterThan(2000 * 3 * 0.9));
  });

  test('contourSegments finds where a ramp crosses the level', () {
    final segments = contourSegments([
      [0, 10],
      [0, 10],
    ], 5);
    expect(segments, hasLength(1));
    final (a, b) = segments.single;
    // A vertical line halfway across the cell, top to bottom.
    expect(a.dx, closeTo(0.5, 1e-9));
    expect(b.dx, closeTo(0.5, 1e-9));
    expect({a.dy, b.dy}, {0.0, 1.0});
    expect(contourSegments([[0, 1], [1, 0]], 5), isEmpty);
  });

  testWidgets('Surface3DChart renders in wireframe with contours, and without fit-to-size', (tester) async {
    final data = [
      for (int r = 0; r < 6; r++) [for (int c = 0; c < 6; c++) (r * c).toDouble()],
    ];
    for (final fit in [true, false]) {
      await tester.pumpWidget(_host(Surface3DChart(
        data: data,
        xLabels: [for (int c = 0; c < 6; c++) '$c'],
        yLabels: [for (int r = 0; r < 6; r++) '$r'],
        xAxisTitle: 'X',
        yAxisTitle: 'Y',
        zAxisTitle: 'Z',
        valueFormatter: (v) => '$v',
        gradient: const [Colors.blue, Colors.red],
        renderMode: SurfaceRenderMode.wireframe,
        showContours: true,
        fitToSize: fit,
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Bar3DChart taps a bar and resets the view via controller', (tester) async {
    final controller = Surface3DChartController();
    Surface3DHit? hit;
    await tester.pumpWidget(_host(Bar3DChart(
      data: const [
        [50]
      ],
      xLabels: const ['A'],
      yLabels: const ['R'],
      controller: controller,
      enableAnimation: false,
      onBarTap: (h) => hit = h,
    )));
    await tester.pumpAndSettle();

    // A single bar is centred on the floor, which fitProjector centres in the
    // chart; its body spans the middle of the box.
    await tester.tapAt(const Offset(250, 200));
    await tester.pump();
    expect((hit?.xLabel, hit?.yLabel, hit?.value), ('A', 'R', 50));

    await tester.drag(find.byType(Bar3DChart), const Offset(120, 0));
    await tester.pumpAndSettle();
    controller.resetView();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Scatter3DChart hit-tests points and toggles series from its legend', (tester) async {
    Scatter3DHit? hit;
    await tester.pumpWidget(_host(Scatter3DChart(
      enableAnimation: false,
      onPointTap: (h) => hit = h,
      series: const [
        Scatter3DSeries(name: 'A', color: Colors.blue, points: [
          Scatter3DPoint(x: 0, y: 0, z: 0),
          Scatter3DPoint(x: 10, y: 10, z: 10, label: 'far corner'),
        ]),
        Scatter3DSeries(name: 'B', color: Colors.red, points: [Scatter3DPoint(x: 5, y: 5, z: 5, label: 'middle')]),
      ],
    )));
    await tester.pumpAndSettle();

    // The middle point is the model's centre, which lands near the middle of
    // the chart (perspective shifts it a few pixels), so search around there.
    Future<Offset?> findMiddle() async {
      for (double dy = -24; dy <= 24; dy += 4) {
        for (double dx = -24; dx <= 24; dx += 4) {
          hit = null;
          await tester.tapAt(Offset(250 + dx, 200 + dy));
          await tester.pump();
          if (hit?.point.label == 'middle') return Offset(250 + dx, 200 + dy);
        }
      }
      return null;
    }

    final at = await findMiddle();
    expect(at, isNotNull);

    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    hit = null;
    await tester.tapAt(at!);
    await tester.pump();
    expect(hit?.point.label, isNot('middle'), reason: 'series B is hidden');
  });
}
