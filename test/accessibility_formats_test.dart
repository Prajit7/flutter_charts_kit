import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_charts_kit/flutter_charts_kit.dart';

Widget _host(Widget chart, {double w = 600, double h = 400}) => MaterialApp(
      home: Scaffold(body: Align(alignment: Alignment.topLeft, child: SizedBox(width: w, height: h, child: chart))),
    );

Future<void> _focusPlot(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pump();
}

void main() {
  group('keyboard navigation', () {
    testWidgets('bar chart: arrows step through bars, Enter taps', (tester) async {
      String? tapped;
      await tester.pumpWidget(_host(BarChart2D(
        enableAnimation: false,
        showLegend: false,
        categories: const ['Jan', 'Feb', 'Mar'],
        series: const [CategorySeries(name: 'Sales', color: Colors.blue, values: [3, 5, 4])],
        onBarTap: (_, c, __) => tapped = c,
      )));
      await tester.pump();
      await _focusPlot(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(find.text('Jan'), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(tapped, 'Feb');
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(tapped, 'Mar');
      // Wraps around.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(tapped, 'Jan');
    });

    testWidgets('line, pie and a HoverPlot chart respond to arrows', (tester) async {
      ChartPoint? linePoint;
      await tester.pumpWidget(_host(LineChart2D(
        enableAnimation: false,
        series: const [XySeries(name: 'a', color: Colors.red, data: [ChartPoint(x: 0, y: 1), ChartPoint(x: 1, y: 2)])],
        onPointTap: (_, p) => linePoint = p,
      )));
      await tester.pump();
      await _focusPlot(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(linePoint?.x, 0);

      String? slice;
      await tester.pumpWidget(_host(PieChart2D(
        enableAnimation: false,
        slices: const [PieSlice(label: 'A', value: 1, color: Colors.red), PieSlice(label: 'B', value: 3, color: Colors.blue)],
        onSliceTap: (s) => slice = s?.label,
      )));
      await tester.pump();
      await _focusPlot(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(slice, isNotNull);

      FunnelStage? stage;
      await tester.pumpWidget(_host(FunnelChart2D(
        enableAnimation: false,
        stages: const [FunnelStage(label: 'Visit', value: 100), FunnelStage(label: 'Buy', value: 10)],
        onStageTap: (s, _) => stage = s,
      )));
      await tester.pump();
      await _focusPlot(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(stage, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('data table', () {
    testWidgets('from category series, with a chart toggle', (tester) async {
      const series = [CategorySeries(name: 'Sales', color: Colors.blue, values: [3, 5.5])];
      await tester.pumpWidget(_host(ChartWithTable(
        chart: const BarChart2D(categories: ['Jan', 'Feb'], series: series, enableAnimation: false),
        table: ChartDataTable.fromCategorySeries(categories: const ['Jan', 'Feb'], series: series),
      )));
      await tester.pump();
      expect(find.byType(DataTable), findsNothing);
      await tester.tap(find.byIcon(Icons.table_rows_outlined));
      await tester.pump();
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('5.5'), findsOneWidget);
      expect(find.text('Sales'), findsOneWidget);
    });

    test('xy series align by x; slices get shares', () {
      final t = ChartDataTable.fromXySeries(series: const [
        XySeries(name: 'a', color: Colors.red, data: [ChartPoint(x: 1, y: 10), ChartPoint(x: 2, y: 20)]),
        XySeries(name: 'b', color: Colors.blue, data: [ChartPoint(x: 2, y: 5)]),
      ]);
      expect(t.rows, [
        ['1', '10', '–'],
        ['2', '20', '5'],
      ]);
      final p = ChartDataTable.fromSlices(slices: const [
        PieSlice(label: 'x', value: 1, color: Colors.red),
        PieSlice(label: 'y', value: 3, color: Colors.blue),
      ]);
      expect(p.rows.last, ['y', '3', '75.0%']);
    });
  });

  group('ChartLocale', () {
    test('grouping and decimals', () {
      expect(ChartLocale.english.number(1234567.891), '1,234,567.89');
      expect(ChartLocale.indian.number(1234567.891), '12,34,567.89');
      expect(ChartLocale.german.number(1234567.5), '1.234.567,5');
      expect(ChartLocale.french.number(-1234.5), '-1 234,5');
      expect(ChartLocale.english.number(-0.001), '0', reason: 'no "-0"');
    });

    test('compact, currency, percent, dates', () {
      expect(ChartLocale.english.compact(1234567), '1.2M');
      expect(ChartLocale.indian.compact(1234567), '12.3L');
      expect(ChartLocale.indian.compact(45000000), '4.5Cr');
      expect(ChartLocale.indian.currency(1234567, decimals: 0), '₹12,34,567');
      expect(ChartLocale.german.currency(-12.5), '-12,50 €');
      expect(ChartLocale.english.percent(0.1234), '12.3%');
      expect(ChartLocale.german.percent(0.1234), '12,3 %');
      expect(ChartLocale.english.date(DateTime(2026, 11, 16)), 'Nov 16, 2026');
      expect(ChartLocale.indian.date(DateTime(2026, 11, 16), year: false), '16 Nov');
      expect(ChartLocale.indian.dateTime(DateTime(2026, 11, 16, 9, 5)), '16 Nov 2026 09:05');
    });

    testWidgets('picked from the app locale', (tester) async {
      late ChartLocale picked;
      await tester.pumpWidget(Localizations(
        locale: const Locale('en', 'IN'),
        delegates: const [DefaultWidgetsLocalizations.delegate],
        child: Builder(builder: (context) {
          picked = ChartLocale.of(context);
          return const SizedBox();
        }),
      ));
      expect(picked, same(ChartLocale.indian));
      expect(ChartLocale.forLocale(const Locale('de')), same(ChartLocale.german));
      expect(ChartLocale.forLocale(const Locale('ja')), same(ChartLocale.english));
    });
  });

  group('value morphing', () {
    testWidgets('pie slices glide to new values instead of replaying the entrance', (tester) async {
      final c = ChartController();
      addTearDown(c.dispose);
      Widget pie(double b) => _host(PieChart2D(
            controller: c,
            showLegend: false,
            animationDuration: const Duration(milliseconds: 400),
            slices: [const PieSlice(label: 'A', value: 1, color: Colors.red), PieSlice(label: 'B', value: b, color: Colors.blue)],
          ));
      await tester.pumpWidget(pie(1));
      await tester.pumpAndSettle();
      final before = c.toSvg()!;
      await tester.pumpWidget(pie(3));
      await tester.pump(const Duration(milliseconds: 200));
      final mid = c.toSvg()!;
      await tester.pumpAndSettle();
      final after = c.toSvg()!;
      expect(mid, isNot(before));
      expect(mid, isNot(after));
    });

    testWidgets('radar polygons morph between datasets', (tester) async {
      final c = ChartController();
      addTearDown(c.dispose);
      Widget radar(double v) => _host(RadarChart2D(
            controller: c,
            axes: const ['a', 'b', 'c'],
            max: 10,
            animationDuration: const Duration(milliseconds: 400),
            series: [CategorySeries(name: 's', color: Colors.teal, values: [v, 5, 5])],
          ));
      await tester.pumpWidget(radar(2));
      await tester.pumpAndSettle();
      final before = c.toSvg()!;
      await tester.pumpWidget(radar(9));
      await tester.pump(const Duration(milliseconds: 200));
      final mid = c.toSvg()!;
      await tester.pumpAndSettle();
      expect(mid, isNot(before));
      expect(mid, isNot(c.toSvg()!));
    });
  });
}
