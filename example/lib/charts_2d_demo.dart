import 'package:flutter/material.dart';
import 'package:surface_3d_chart/surface_3d_chart.dart';

// Run this file specifically to see all four 2D chart types:
//   flutter run -t lib/charts_2d_demo.dart

void main() => runApp(const Charts2DDemoApp());

class Charts2DDemoApp extends StatefulWidget {
  const Charts2DDemoApp({super.key});
  @override
  State<Charts2DDemoApp> createState() => _Charts2DDemoAppState();
}

class _Charts2DDemoAppState extends State<Charts2DDemoApp> {
  bool _dark = false;

  @override
  Widget build(BuildContext context) {
    return ChartThemeScope(
      theme: _dark ? ChartTheme.dark : ChartTheme.light,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
        home: Charts2DDemoScreen(
          isDark: _dark,
          onToggleTheme: () => setState(() => _dark = !_dark),
        ),
      ),
    );
  }
}

class Charts2DDemoScreen extends StatelessWidget {
  final bool isDark;
  final VoidCallback onToggleTheme;

  const Charts2DDemoScreen({super.key, required this.isDark, required this.onToggleTheme});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('2D Chart Types'),
        actions: [
          IconButton(
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
            tooltip: 'Toggle theme',
            onPressed: onToggleTheme,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(height: 280, child: _buildLineChart()),
          const SizedBox(height: 32),
          SizedBox(height: 280, child: _buildBarChart(stacked: false)),
          const SizedBox(height: 32),
          SizedBox(height: 280, child: _buildBarChart(stacked: true)),
          const SizedBox(height: 32),
          SizedBox(height: 300, child: _buildPieChart(donut: false)),
          const SizedBox(height: 32),
          SizedBox(height: 300, child: _buildPieChart(donut: true)),
          const SizedBox(height: 32),
          SizedBox(height: 300, child: _buildScatterChart()),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildLineChart() {
    return LineChart2D(
      title: 'Monthly Revenue',
      subtitle: 'Revenue vs. costs, in thousands USD — drag to zoom, reset button to undo',
      filled: true,
      onPointTap: (series, point) {
        if (point != null) debugPrint('Tapped $series at ${point.label}: ${point.y}');
      },
      series: [
        XySeries(
          name: 'Revenue',
          color: Colors.indigo,
          data: const [
            ChartPoint(x: 1, y: 120, label: 'Jan'),
            ChartPoint(x: 2, y: 180, label: 'Feb'),
            ChartPoint(x: 3, y: 150, label: 'Mar'),
            ChartPoint(x: 4, y: 220, label: 'Apr'),
            ChartPoint(x: 5, y: 260, label: 'May'),
            ChartPoint(x: 6, y: 240, label: 'Jun'),
          ],
        ),
        XySeries(
          name: 'Costs',
          color: Colors.redAccent,
          data: const [
            ChartPoint(x: 1, y: 80, label: 'Jan'),
            ChartPoint(x: 2, y: 95, label: 'Feb'),
            ChartPoint(x: 3, y: 100, label: 'Mar'),
            ChartPoint(x: 4, y: 110, label: 'Apr'),
            ChartPoint(x: 5, y: 130, label: 'May'),
            ChartPoint(x: 6, y: 125, label: 'Jun'),
          ],
        ),
      ],
      xAxisTitle: 'Month',
      yAxisTitle: 'USD (thousands)',
    );
  }

  Widget _buildBarChart({required bool stacked}) {
    return BarChart2D(
      title: stacked ? 'Units Sold (Stacked)' : 'Units Sold (Grouped)',
      subtitle: 'Drag horizontally to zoom into a category range',
      stacked: stacked,
      onBarTap: (series, category, value) => debugPrint('Tapped $series/$category: $value'),
      categories: const ['Q1', 'Q2', 'Q3', 'Q4'],
      series: const [
        CategorySeries(name: 'North', color: Colors.teal, values: [40, 55, 48, 62]),
        CategorySeries(name: 'South', color: Colors.amber, values: [30, 35, 42, 38]),
        CategorySeries(name: 'East', color: Colors.deepPurple, values: [20, 28, 25, 33]),
      ],
      xAxisTitle: 'Quarter',
      yAxisTitle: 'Units sold',
    );
  }

  Widget _buildPieChart({required bool donut}) {
    return PieChart2D(
      title: donut ? 'Browser Share (Donut)' : 'Browser Share (Pie)',
      subtitle: 'Pinch or scroll to zoom, drag to pan',
      innerRadiusRatio: donut ? 0.6 : 0,
      onSliceTap: (slice) => debugPrint('Tapped slice: ${slice?.label}'),
      slices: const [
        PieSlice(label: 'Chrome', value: 64, color: Colors.blue),
        PieSlice(label: 'Safari', value: 19, color: Colors.orange),
        PieSlice(label: 'Edge', value: 9, color: Colors.green),
        PieSlice(label: 'Firefox', value: 5, color: Colors.deepOrange),
        PieSlice(label: 'Other', value: 3, color: Colors.grey),
      ],
      valueFormatter: (v) => '${v.toStringAsFixed(0)}%',
    );
  }

  Widget _buildScatterChart() {
    return ScatterChart2D(
      title: 'Practice vs. Score',
      subtitle: 'Drag a rectangle to zoom into both axes',
      onPointTap: (series, point) {
        if (point != null) debugPrint('Tapped $series: ${point.label}');
      },
      series: [
        XySeries(
          name: 'Cohort A',
          color: Colors.blue,
          data: const [
            ChartPoint(x: 2.1, y: 65, label: 'User 1'),
            ChartPoint(x: 4.5, y: 78, label: 'User 2'),
            ChartPoint(x: 6.2, y: 85, label: 'User 3'),
            ChartPoint(x: 3.0, y: 70, label: 'User 4'),
            ChartPoint(x: 8.1, y: 92, label: 'User 5'),
          ],
        ),
        XySeries(
          name: 'Cohort B',
          color: Colors.pink,
          data: const [
            ChartPoint(x: 1.5, y: 55, label: 'User 6'),
            ChartPoint(x: 5.0, y: 60, label: 'User 7'),
            ChartPoint(x: 7.4, y: 68, label: 'User 8'),
            ChartPoint(x: 3.8, y: 58, label: 'User 9'),
          ],
        ),
      ],
      xAxisTitle: 'Hours practiced',
      yAxisTitle: 'Score',
    );
  }
}
