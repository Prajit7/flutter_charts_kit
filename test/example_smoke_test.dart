import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The example app isn't a dependency of the package, so import it by path.
// This keeps the showcase compiling and rendering cleanly as the API grows.
// ignore: avoid_relative_lib_imports
import '../example/lib/main.dart';

/// The example has live (timer-driven) demos, so it never "settles";
/// pump a bounded amount of time instead of pumpAndSettle.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  for (final size in [const Size(1280, 900), const Size(390, 844), const Size(320, 640)]) {
    testWidgets('example app renders every chart at $size without errors', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const ChartsDemoApp());
      await _settle(tester);

      // Scroll through the whole 2D page so every chart builds and paints.
      for (int i = 0; i < 30; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -400));
        await _settle(tester);
        final error = tester.takeException();
        if (error != null) fail('after scroll step $i: $error');
      }

      await tester.tap(find.byTooltip('Toggle theme'));
      await _settle(tester);
      await tester.tap(find.byIcon(Icons.view_in_ar).first);
      await _settle(tester);
      expect(tester.takeException(), isNull);
      // Every 3D view.
      for (final label in ['Wireframe', 'Bars', 'Scatter', 'Surface']) {
        await tester.tap(find.text(label));
        await _settle(tester);
        final error = tester.takeException();
        if (error != null) fail('3D view $label: $error');
      }

      // "More charts" tab: scroll through every specialty chart too.
      await tester.tap(find.byIcon(Icons.dashboard_customize_outlined));
      await _settle(tester);
      for (int i = 0; i < 30; i++) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -400));
        await _settle(tester);
        final error = tester.takeException();
        if (error != null) fail('more charts, scroll step $i: $error');
      }

      // "Business" tab.
      await tester.tap(find.byIcon(Icons.business_center_outlined));
      await _settle(tester);
      for (int i = 0; i < 30; i++) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -400));
        await _settle(tester);
        final error = tester.takeException();
        if (error != null) fail('business charts, scroll step $i: $error');
      }

      // "Graphs & maps" tab (network graph animates, so pump a bounded time).
      await tester.tap(find.byIcon(Icons.hub_outlined));
      await _settle(tester);
      for (int i = 0; i < 12; i++) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -300));
        await _settle(tester);
        final error = tester.takeException();
        if (error != null) fail('graphs & maps, scroll step $i: $error');
      }

      // "Options & trading" tab (the depth demo ticks on a timer).
      await tester.tap(find.byIcon(Icons.candlestick_chart_outlined));
      await _settle(tester);
      for (int i = 0; i < 10; i++) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -300));
        await _settle(tester);
        final error = tester.takeException();
        if (error != null) fail('options & trading, scroll step $i: $error');
      }

      // "Stories" tab.
      await tester.tap(find.byIcon(Icons.auto_graph));
      await _settle(tester);
      for (int i = 0; i < 12; i++) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -300));
        await _settle(tester);
        final error = tester.takeException();
        if (error != null) fail('stories, scroll step $i: $error');
      }

      // Every demo card in the newer tabs shows its code.
      final code = find.text('Code').hitTestable();
      if (code.evaluate().isNotEmpty) {
        await tester.tap(code.first);
        await _settle(tester);
        expect(find.text('Copy'), findsOneWidget);
        expect(find.byType(SelectableText), findsOneWidget);
        await tester.tap(find.byIcon(Icons.close));
        await _settle(tester);
      }
    });
  }
}
