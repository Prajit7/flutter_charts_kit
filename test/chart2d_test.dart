import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_charts_kit/flutter_charts_kit.dart';

void main() {
  final sampleSeries = [
    XySeries(
      name: 'A',
      color: Colors.blue,
      data: List.generate(10, (i) => ChartPoint(x: i.toDouble(), y: (i * i).toDouble())),
    ),
  ];

  testWidgets('LineChart2D renders without throwing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 400, height: 300, child: LineChart2D(series: sampleSeries)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LineChart2D), findsOneWidget);
  });

  testWidgets('LineChart2D shows empty state for no data', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 400, height: 300, child: LineChart2D(series: [])),
        ),
      ),
    );
    expect(find.byType(ChartEmptyState), findsOneWidget);
  });

  testWidgets('LineChart2D drag-to-zoom shows a reset button, which clears zoom on tap', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: LineChart2D(series: sampleSeries, enableAnimation: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No reset button before any zoom interaction.
    expect(find.byIcon(Icons.zoom_out_map), findsNothing);

    // Drag a selection box across roughly the middle of the plot area.
    final chartFinder = find.byType(LineChart2D);
    final topLeft = tester.getTopLeft(chartFinder);
    await tester.dragFrom(topLeft + const Offset(80, 150), const Offset(150, 0));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.zoom_out_map), findsOneWidget);

    // Tapping reset clears the zoom window again.
    await tester.tap(find.byIcon(Icons.zoom_out_map));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.zoom_out_map), findsNothing);
  });

  testWidgets('ScatterChart2D renders without throwing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 400, height: 300, child: ScatterChart2D(series: sampleSeries)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ScatterChart2D), findsOneWidget);
  });

  testWidgets('BarChart2D renders and legend toggles a series', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: BarChart2D(
              categories: ['Jan', 'Feb', 'Mar'],
              series: [
                CategorySeries(name: 'A', color: Colors.blue, values: [1, 2, 3]),
                CategorySeries(name: 'B', color: Colors.red, values: [3, 2, 1]),
              ],
              enableAnimation: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BarChart2D), findsOneWidget);
    expect(find.text('A'), findsOneWidget);

    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    // legend entry should still be present (struck through), chart shouldn't crash
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('PieChart2D renders and shows tooltip on tap', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 300,
            child: PieChart2D(
              slices: [
                PieSlice(label: 'X', value: 60, color: Colors.blue),
                PieSlice(label: 'Y', value: 40, color: Colors.orange),
              ],
              enableAnimation: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PieChart2D), findsOneWidget);

    final center = tester.getCenter(find.byType(PieChart2D));
    await tester.tapAt(center + const Offset(0, -60));
    await tester.pumpAndSettle();
    // one of the slice labels should now be visible in the center tooltip
    expect(find.textContaining(RegExp('X|Y')), findsWidgets);
  });
}
