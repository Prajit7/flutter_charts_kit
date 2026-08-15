import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_charts_kit/flutter_charts_kit.dart';

void main() {
  testWidgets('Surface3DChart renders without throwing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 400,
            child: Surface3DChart(
              data: const [
                [1, 2, 3],
                [4, 5, 6],
                [7, 8, 9],
              ],
              xLabels: const ['A', 'B', 'C'],
              yLabels: const ['X', 'Y', 'Z'],
              xAxisTitle: 'X',
              yAxisTitle: 'Y',
              zAxisTitle: 'Z',
              valueFormatter: (v) => v.toStringAsFixed(1),
              gradient: const [Colors.blue, Colors.red],
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Surface3DChart), findsOneWidget);
  });

  testWidgets('Surface3DChartController.resetView resets zoom', (tester) async {
    final controller = Surface3DChartController();
    final key = GlobalKey<Surface3DChartState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 400,
            child: Surface3DChart(
              key: key,
              controller: controller,
              data: const [
                [1, 2],
                [3, 4],
              ],
              xLabels: const ['A', 'B'],
              yLabels: const ['X', 'Y'],
              xAxisTitle: 'X',
              yAxisTitle: 'Y',
              zAxisTitle: 'Z',
              valueFormatter: (v) => v.toString(),
              gradient: const [Colors.blue, Colors.red],
              initialZoom: 16,
            ),
          ),
        ),
      ),
    );

    // simulate a drag to change rotation, then reset
    await tester.drag(find.byType(Surface3DChart), const Offset(50, 50));
    await tester.pump();

    controller.resetView();
    await tester.pump();

    expect(key.currentState!.zoom, 16);
  });
}
