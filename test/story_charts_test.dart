import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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

void main() {
  group('bump', () {
    test('ranks per period; unranked skipped; lower-is-better', () {
      const s = [
        CategorySeries(name: 'a', color: Colors.red, values: [10, 30]),
        CategorySeries(name: 'b', color: Colors.blue, values: [20, double.nan]),
        CategorySeries(name: 'c', color: Colors.green, values: [5, 25]),
      ];
      expect(BumpChart2D.rank(s, 2), [
        [2, 1],
        [1, null],
        [3, 2],
      ]);
      expect(BumpChart2D.rank(s, 2, higherIsBetter: false)[2], [1, 1], reason: 'lowest value ranks first');
      expect(BumpChart2D.rank(s, 2, higherIsBetter: false)[0], [2, 2]);
    });

    testWidgets('hover shows rank and movement', (tester) async {
      await tester.pumpWidget(_host(const BumpChart2D(
        enableAnimation: false,
        periods: ['A', 'B'],
        series: [
          CategorySeries(name: 'X', color: Colors.red, values: [1, 3]),
          CategorySeries(name: 'Y', color: Colors.blue, values: [2, 2]),
        ],
      )));
      await tester.pump();
      expect(find.bySemanticsLabel(RegExp('X: rank 2 in A to 1 in B')), findsOneWidget);
    });
  });

  testWidgets('slope: labels for both sides and tooltip change', (tester) async {
    SlopeItem? tapped;
    await tester.pumpWidget(_host(SlopeChart2D(
      enableAnimation: false,
      items: const [SlopeItem(label: 'North', start: 10, end: 15), SlopeItem(label: 'South', start: 12, end: 8)],
      onItemTap: (i) => tapped = i,
    )));
    await tester.pump();
    // Lines run x 150 → 450 over plot y 30 → 388; North is at 12.5 midway (y ≈ 163).
    await tester.tapAt(const Offset(300, 163));
    await tester.pump();
    expect(tapped, isNotNull);
    expect(find.textContaining('(+50.0%)').evaluate().length + find.textContaining('(-33.3%)').evaluate().length, 1);
  });

  testWidgets('Marimekko: column widths follow totals; tooltip shares', (tester) async {
    await tester.pumpWidget(_host(const MarimekkoChart2D(
      enableAnimation: false,
      showLegend: false,
      categories: ['Big', 'Small'],
      series: [
        CategorySeries(name: 'Us', color: Colors.indigo, values: [30, 10]),
        CategorySeries(name: 'Them', color: Colors.orange, values: [50, 10]),
      ],
    )));
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('Big: 80% of total; Small: 20% of total')), findsOneWidget);
    // Plot spans x 42 → 592: 'Big' takes 80%. Bottom cell of Big = Us (37.5%).
    await _hover(tester, const Offset(200, 330));
    expect(find.textContaining('37.5% of Big'), findsOneWidget);
  });

  group('streamgraph', () {
    test('silhouette is centred on zero; layers stack without gaps', () {
      final l = StreamgraphChart2D.stack([
        [10, 20],
        [5, 10],
      ], StreamBaseline.silhouette);
      expect(l[0][0], (-7.5, 2.5));
      expect(l[1][0], (2.5, 7.5));
      expect(l[1][1].$2, -l[0][1].$1);
      final z = StreamgraphChart2D.stack([
        [10, 20],
        [5, 10],
      ], StreamBaseline.zero);
      expect(z[0][1], (0, 20));
      expect(z[1][1], (20, 30));
    });

    testWidgets('hover lists every layer; legend hides one', (tester) async {
      await tester.pumpWidget(_host(const StreamgraphChart2D(
        enableAnimation: false,
        labels: ['a', 'b', 'c'],
        series: [
          CategorySeries(name: 'Pop', color: Colors.pink, values: [10, 20, 30]),
          CategorySeries(name: 'Rock', color: Colors.blue, values: [5, 5, 5]),
        ],
      )));
      await tester.pump();
      await _hover(tester, const Offset(300, 150));
      expect(find.textContaining('Total 25'), findsOneWidget);
      await tester.tap(find.text('Rock'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('beeswarm', () {
    test('swarm keeps dots apart and as central as possible', () {
      final xs = <double>[100, 100, 100, 150];
      final off = BeeswarmChart2D.swarm(xs, 4);
      expect(off[3], 0, reason: 'a lone dot stays on the centre line');
      for (int i = 0; i < 3; i++) {
        for (int j = i + 1; j < 3; j++) {
          expect((off[i] - off[j]).abs(), greaterThanOrEqualTo(8));
        }
      }
      expect(off.take(3).map((o) => o.abs()).reduce((a, b) => a < b ? a : b), 0);
    });

    testWidgets('renders groups with medians', (tester) async {
      await tester.pumpWidget(_host(const BeeswarmChart2D(
        enableAnimation: false,
        groups: [BeeswarmGroup(label: 'G', color: Colors.teal, values: [1, 2, 3, 4, 100])],
      )));
      await tester.pump();
      expect(find.bySemanticsLabel(RegExp('median 3')), findsOneWidget);
    });
  });

  test('ridgeline density integrates to ~1', () {
    final xs = [for (int i = 0; i <= 400; i++) -10 + i * 0.05];
    final d = RidgelineChart2D.density([0, 1, 2, 1.5, 0.5, 3, -1], xs);
    final area = d.fold(0.0, (s, v) => s + v * 0.05);
    expect(area, closeTo(1, 0.01));
  });

  testWidgets('ridgeline renders', (tester) async {
    await tester.pumpWidget(_host(const RidgelineChart2D(
      enableAnimation: false,
      groups: [RidgelineGroup(label: 'A', values: [1, 2, 3, 2.5]), RidgelineGroup(label: 'B', values: [4, 5, 6])],
    )));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('tree: tap toggles collapse; initialDepth hides deeper nodes', (tester) async {
    const leaf = TreeChartNode(label: 'Leaf');
    const mid = TreeChartNode(label: 'Mid', children: [leaf]);
    TreeChartNode? tapped;
    await tester.pumpWidget(_host(TreeChart2D(
      root: const TreeChartNode(label: 'Root', children: [mid]),
      initialDepth: 1,
      onNodeTap: (n) => tapped = n,
    )));
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('3 nodes, root Root; 1 collapsed')), findsOneWidget);
    // Two visible boxes stacked top-down, centred: Root above Mid.
    await tester.tapAt(const Offset(300, 240));
    await tester.pump();
    expect(tapped?.label, 'Mid');
    expect(find.bySemanticsLabel(RegExp(r'3 nodes, root Root\.$')), findsOneWidget, reason: 'expanded');
  });

  testWidgets('timeline: events placed, tap reports', (tester) async {
    TimelineEvent? tapped;
    final events = [
      TimelineEvent(start: DateTime(2026, 1, 1), title: 'Start', description: 'kick-off'),
      TimelineEvent(start: DateTime(2026, 2, 1), end: DateTime(2026, 3, 1), title: 'Build'),
      TimelineEvent(start: DateTime(2026, 4, 1), title: 'Ship'),
    ];
    await tester.pumpWidget(_host(TimelineChart2D(events: events, onEventTap: (e) => tapped = e)));
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('3 events')), findsOneWidget);
    // The last moment sits near the right end of the axis (vertical centre).
    final box = tester.getRect(find.byType(CustomPaint).last);
    await tester.tapAt(Offset(box.left + box.width * 0.94, box.center.dy));
    await tester.pump();
    expect(tapped?.title, 'Ship');
    await tester.pumpWidget(_host(const TimelineChart2D(events: [])));
    expect(find.text('No events'), findsOneWidget);
  });
}
