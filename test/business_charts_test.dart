import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_charts_kit/flutter_charts_kit.dart';

// Plot area for a 400x300 Cartesian chart without title/legend:
// (48, 12) -> (388, 256).
Widget _host(Widget chart, {Size size = const Size(400, 300)}) => MaterialApp(
      home: Scaffold(
        body: Align(alignment: Alignment.topLeft, child: SizedBox(width: size.width, height: size.height, child: chart)),
      ),
    );

void main() {
  test('WaterfallBar.layout keeps a running total; totals show it', () {
    final bars = WaterfallBar.layout(const [
      WaterfallStep(label: 'a', value: 100),
      WaterfallStep(label: 'b', value: -30),
      WaterfallStep.total('t'),
      WaterfallStep(label: 'c', value: 5),
    ]);
    expect([for (final b in bars) (b.start, b.end)], [(0, 100), (100, 70), (0, 70), (70, 75)]);
    expect(bars[1].delta, -30);
    expect(bars[2].delta, 70);
  });

  testWidgets('WaterfallChart2D tap reports the step', (tester) async {
    WaterfallBar? tapped;
    await tester.pumpWidget(_host(WaterfallChart2D(
      enableAnimation: false,
      onStepTap: (b) => tapped = b,
      steps: const [WaterfallStep(label: 'a', value: 100), WaterfallStep(label: 'b', value: -30)],
    )));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(48 + 340 * 0.75, 100)); // second slot
    await tester.pump();
    expect(tapped?.step.label, 'b');
  });

  testWidgets('BulletChart describes itself against its target', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(const BulletChart(label: 'Revenue', value: 270, target: 250), size: const Size(400, 60)));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Revenue, 270, target 250, on target'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('CalendarHeatmap taps report the day and its value', (tester) async {
    CalendarDay? tapped;
    // 7 weeks starting on a Sunday (1 Mar 2026), Sunday-first rows.
    await tester.pumpWidget(_host(CalendarHeatmap(
      start: DateTime(2026, 3, 1),
      end: DateTime(2026, 4, 18),
      values: {DateTime(2026, 3, 4, 15, 30): 7}, // time of day is ignored
      showWeekdayLabels: false,
      showMonthLabels: false,
      showLegend: false,
      onDayTap: (d) => tapped = d,
    )));
    await tester.pumpAndSettle();
    // 7 columns over 400px = 57px cells (height-limited: 300/7 ≈ 42.9px).
    const cell = 300 / 7;
    await tester.tapAt(const Offset(cell / 2, cell * 3.5)); // week 0, Wednesday 4 Mar
    await tester.pump();
    expect(tapped?.date, DateTime(2026, 3, 4));
    expect(tapped?.value, 7);
  });

  testWidgets('SunburstChart2D drills into a branch and back out', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(const SunburstChart2D(
      enableAnimation: false,
      nodes: [
        TreemapNode(label: 'A', children: [TreemapNode(label: 'A1', value: 1), TreemapNode(label: 'A2', value: 1)]),
        TreemapNode(label: 'B', value: 2),
      ],
    )));
    await tester.pumpAndSettle();
    // A covers the right half (12 → 6 o'clock); its ring is just outside the hole.
    await tester.tapAt(const Offset(200 + 60, 150));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('zoomed into A')), findsOneWidget);
    await tester.tapAt(const Offset(200, 150)); // centre = zoom out
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('zoomed into')), findsNothing);
    handle.dispose();
  });

  testWidgets('PolarBarChart2D and RangeChart2D hit-test their bars', (tester) async {
    PolarBarHit? polar;
    await tester.pumpWidget(_host(PolarBarChart2D(
      enableAnimation: false,
      showLegend: false,
      categories: const ['N', 'E', 'S', 'W'],
      series: const [CategorySeries(name: 'S', color: Colors.teal, values: [10, 10, 10, 10])],
      onBarTap: (h) => polar = h,
    )));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(200 + 40, 150 - 40)); // north-east quadrant = 'N' wedge
    await tester.pump();
    expect(polar?.category, 'N');

    RangeHit? range;
    await tester.pumpWidget(_host(RangeChart2D(
      enableAnimation: false,
      categories: const ['a', 'b'],
      series: const [RangeSeries(name: 'r', color: Colors.blue, values: [RangeValue(1, 5), RangeValue(2, 9)])],
      onRangeTap: (h) => range = h,
    )));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(48 + 340 * 0.75, 120));
    await tester.pump();
    expect((range?.category, range?.value.high), ('b', 9));
  });

  testWidgets('BarChart2D lollipops still hit-test', (tester) async {
    double? value;
    await tester.pumpWidget(_host(BarChart2D(
      barStyle: BarStyle.lollipop,
      enableAnimation: false,
      showLegend: false,
      categories: const ['a', 'b'],
      series: const [CategorySeries(name: 's', color: Colors.blue, values: [5, 10])],
      onBarTap: (_, __, v) => value = v,
    )));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(48 + 340 * 0.75, 200));
    await tester.pump();
    expect(value, 10);
  });

  testWidgets('GanttChart2D: tap a task, drag to scroll, scroll-wheel to zoom', (tester) async {
    final controller = ChartController();
    addTearDown(controller.dispose);
    GanttTask? tapped;
    final tasks = [
      GanttTask(label: 'One', start: DateTime(2026, 3, 1), end: DateTime(2026, 3, 10)),
      GanttTask(label: 'Two', start: DateTime(2026, 3, 5), end: DateTime(2026, 3, 20), dependsOn: const ['One']),
    ];
    await tester.pumpWidget(_host(GanttChart2D(tasks: tasks, showToday: false, controller: controller, onTaskTap: (t) => tapped = t)));
    await tester.pumpAndSettle();
    // Header 24px, then rows of 30px: row 1 is "Two".
    await tester.tapAt(const Offset(300, 24 + 45));
    await tester.pump();
    expect(tapped?.label, 'Two');

    await tester.timedDragFrom(const Offset(300, 40), const Offset(-80, 0), const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(controller.isZoomed, isTrue);
    controller.resetZoom();
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(300, 60));
    tester.binding.handlePointerEvent(const PointerScrollEvent(position: Offset(300, 60), scrollDelta: Offset(0, -200)));
    await tester.pumpAndSettle();
    expect(controller.isZoomed, isTrue);
    expect(tester.takeException(), isNull);
  });
}
