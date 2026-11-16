import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_charts_kit/flutter_charts_kit.dart';

Widget _host(Widget chart, {double w = 400, double h = 400}) => MaterialApp(
      home: Scaffold(body: Align(alignment: Alignment.topLeft, child: SizedBox(width: w, height: h, child: chart))),
    );

const _square = '''
{"type":"FeatureCollection","features":[
 {"type":"Feature","properties":{"name":"West"},"geometry":{"type":"Polygon","coordinates":[[[0,0],[10,0],[10,10],[0,10],[0,0]]]}},
 {"type":"Feature","properties":{"name":"East"},"geometry":{"type":"MultiPolygon","coordinates":[[[[10,0],[20,0],[20,10],[10,10],[10,0]],[[12,2],[18,2],[18,8],[12,8],[12,2]]]]}},
 {"type":"Feature","properties":{"name":"Dot"},"geometry":{"type":"Point","coordinates":[5,5]}}
]}''';

void main() {
  group('GeoFeature.parse', () {
    test('reads polygons, multipolygons and holes; skips other geometry', () {
      final f = GeoFeature.parse(_square);
      expect(f.map((e) => e.id), ['West', 'East']);
      expect(f[1].polygons.single, hasLength(2), reason: 'outer ring + hole');
      expect(f[0].bounds, const Rect.fromLTRB(0, 0, 10, 10));
      expect(() => GeoFeature.parse('[1]'), throwsFormatException);
    });
  });

  testWidgets('choropleth: hover a region, holes are not part of it', (tester) async {
    GeoFeature? tapped;
    double? tappedValue;
    await tester.pumpWidget(_host(
      ChoroplethMap2D(
        features: GeoFeature.parse(_square),
        projection: MapProjection.equirectangular,
        values: const {'West': 5, 'East': 9},
        showLegend: false,
        onRegionTap: (f, v) {
          tapped = f;
          tappedValue = v;
        },
      ),
      h: 206,
    ));
    // 20°x10° of map fit into 388x194 (6px padding): 19.4px per degree.
    await tester.tapAt(const Offset(6 + 19.4 * 5, 6 + 19.4 * 5));
    await tester.pump();
    expect(tapped?.id, 'West');
    expect(tappedValue, 5);
    expect(find.text('West'), findsOneWidget);
    tapped = null;
    await tester.tapAt(const Offset(6 + 19.4 * 15, 6 + 19.4 * 5)); // inside East's hole
    await tester.pump();
    expect(tapped, isNull);
    await tester.tapAt(const Offset(6 + 19.4 * 11, 6 + 19.4 * 1));
    await tester.pump();
    expect(tapped?.id, 'East');
    expect(find.text('9'), findsOneWidget);
  });

  testWidgets('network graph settles deterministically and reports taps', (tester) async {
    GraphNode? tapped;
    final nodes = [for (final id in ['a', 'b', 'c', 'd']) GraphNode(id: id, group: id == 'a' ? 'hub' : 'leaf')];
    const edges = [GraphEdge('a', 'b'), GraphEdge('a', 'c'), GraphEdge('a', 'd')];
    await tester.pumpWidget(_host(NetworkGraph2D(
      nodes: nodes,
      edges: edges,
      enableAnimation: false,
      onNodeTap: (n) => tapped = n,
    )));
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('4 nodes, 3 links')), findsOneWidget);
    // Find the hub by sweeping taps across the plot.
    for (double y = 4; y < 400 && tapped?.id != 'a'; y += 6) {
      for (double x = 4; x < 400 && tapped?.id != 'a'; x += 6) {
        await tester.tapAt(Offset(x, y));
      }
    }
    await tester.pump();
    expect(tapped?.id, 'a');
    expect(find.text('3 connections'), findsOneWidget);
    // Animated mode runs the ticker and stops once it cools down.
    await tester.pumpWidget(_host(NetworkGraph2D(nodes: nodes, edges: edges)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('chord: group and ribbon tooltips show both directions', (tester) async {
    ChordHit? hit;
    await tester.pumpWidget(_host(ChordChart2D(
      labels: const ['A', 'B'],
      matrix: const [
        [0, 30],
        [10, 0],
      ],
      enableAnimation: false,
      onTap: (h) => hit = h,
    )));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(200, 200)); // centre: the only ribbon
    await tester.pump();
    expect(hit, const ChordHit(0, 1));
    expect(find.text('30 / 10'), findsOneWidget);
    // A's arc starts at 12 o'clock (radius 154, ring ~11).
    await tester.tapAt(const Offset(230, 200 - 150));
    await tester.pump();
    expect(hit, const ChordHit(0));
    expect(find.text('30 out'), findsOneWidget);
    // Mismatched matrix → message, not a crash.
    await tester.pumpWidget(_host(const ChordChart2D(labels: ['A', 'B'], matrix: [[1]])));
    expect(find.text('Matrix must be 2x2'), findsOneWidget);
  });

  testWidgets('parallel coordinates: brushing an axis filters records', (tester) async {
    List<ParallelRecord>? selection;
    const records = [
      ParallelRecord([0, 10], label: 'low'),
      ParallelRecord([5, 5], label: 'mid'),
      ParallelRecord([10, 0], label: 'high'),
    ];
    await tester.pumpWidget(_host(ParallelCoordinatesChart2D(
      axes: const [ParallelAxis('X', min: 0, max: 10), ParallelAxis('Y', min: 0, max: 10)],
      records: records,
      onSelectionChanged: (s) => selection = s,
    )));
    // Plot: x axis at left = 36, y from 22 to 378. Brush the top 40% of X.
    final g = await tester.startGesture(const Offset(36, 20));
    await g.moveBy(const Offset(0, 20));
    await g.moveTo(const Offset(36, 22 + 356 * 0.4));
    await g.up();
    await tester.pump();
    expect(selection?.map((r) => r.label), ['high']);
    // Tap the axis to clear.
    await tester.tapAt(const Offset(36, 200));
    await tester.pump();
    expect(selection, hasLength(3));

    // Hovering a line shows its values.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(200, 200)); // 'mid' crosses the middle
    await mouse.moveTo(const Offset(200, 200));
    await tester.pump();
    expect(find.text('mid'), findsOneWidget);
  });
}
