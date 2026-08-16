import 'package:flutter/material.dart';
import 'package:flutter_charts_kit/flutter_charts_kit.dart';

void main() => runApp(const ChartsDemoApp());

class ChartsDemoApp extends StatefulWidget {
  const ChartsDemoApp({super.key});

  @override
  State<ChartsDemoApp> createState() => _ChartsDemoAppState();
}

class _ChartsDemoAppState extends State<ChartsDemoApp> {
  bool _dark = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: Colors.indigo,
      ),

      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.indigo,
      ),

      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,

      home: ChartThemeScope(
        theme: _dark ? ChartTheme.dark : ChartTheme.light,
        child: ChartsDemoScreen(
          isDark: _dark,
          onToggleTheme: () {
            setState(() {
              _dark = !_dark;
            });
          },
        ),
      ),
    );
  }
}

// ============================================================
// RESPONSIVE HELPERS
// ============================================================

class Responsive {
  static bool isMobile(BuildContext context) {
    return MediaQuery.sizeOf(context).width < 600;
  }

  static bool isTablet(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= 600 && width < 1024;
  }

  static bool isDesktop(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= 1024;
  }

  static double horizontalPadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    if (width < 600) {
      return 8;
    }

    if (width < 1024) {
      return 16;
    }

    return 24;
  }
}

// ============================================================
// MAIN SCREEN
// ============================================================

class ChartsDemoScreen extends StatelessWidget {
  final bool isDark;
  final VoidCallback onToggleTheme;

  const ChartsDemoScreen({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Flutter Charts Kit'),
          actions: [
            IconButton(
              icon: Icon(
                isDark ? Icons.light_mode : Icons.dark_mode,
              ),
              tooltip: 'Toggle theme',
              onPressed: onToggleTheme,
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(
                icon: const Icon(Icons.bar_chart),
                text: isMobile ? '2D' : '2D Charts',
              ),
              Tab(
                icon: const Icon(Icons.view_in_ar),
                text: isMobile ? '3D' : '3D Chart',
              ),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            Charts2DPage(),
            Surface3DPage(),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 2D CHARTS
// ============================================================

class Charts2DPage extends StatelessWidget {
  const Charts2DPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final horizontalPadding =
        Responsive.horizontalPadding(context);

    final chartHeight = isMobile ? 320.0 : 280.0;
    final pieHeight = isMobile ? 330.0 : 300.0;

    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 16,
      ),
      children: [
        SizedBox(
          height: chartHeight,
          child: _buildLineChart(),
        ),

        const SizedBox(height: 24),

        SizedBox(
          height: chartHeight,
          child: _buildBarChart(
            stacked: false,
          ),
        ),

        const SizedBox(height: 24),

        SizedBox(
          height: chartHeight,
          child: _buildBarChart(
            stacked: true,
          ),
        ),

        const SizedBox(height: 24),

        SizedBox(
          height: pieHeight,
          child: _buildPieChart(
            donut: false,
          ),
        ),

        const SizedBox(height: 24),

        SizedBox(
          height: pieHeight,
          child: _buildPieChart(
            donut: true,
          ),
        ),

        const SizedBox(height: 24),

        SizedBox(
          height: chartHeight,
          child: _buildScatterChart(),
        ),

        const SizedBox(height: 24),
      ],
    );
  }

  // ==========================================================
  // LINE CHART
  // ==========================================================

  Widget _buildLineChart() {
    return LineChart2D(
      title: 'Monthly Revenue',
      subtitle:
          'Revenue vs. costs, in thousands USD — drag to zoom, reset button to undo',
      filled: true,

      onPointTap: (series, point) {
        if (point != null) {
          debugPrint(
            'Tapped $series at ${point.label}: ${point.y}',
          );
        }
      },

      series: [
        XySeries(
          name: 'Revenue',
          color: Colors.indigo,
          data: const [
            ChartPoint(
              x: 1,
              y: 120,
              label: 'Jan',
            ),
            ChartPoint(
              x: 2,
              y: 180,
              label: 'Feb',
            ),
            ChartPoint(
              x: 3,
              y: 150,
              label: 'Mar',
            ),
            ChartPoint(
              x: 4,
              y: 220,
              label: 'Apr',
            ),
            ChartPoint(
              x: 5,
              y: 260,
              label: 'May',
            ),
            ChartPoint(
              x: 6,
              y: 240,
              label: 'Jun',
            ),
          ],
        ),

        XySeries(
          name: 'Costs',
          color: Colors.redAccent,
          data: const [
            ChartPoint(
              x: 1,
              y: 80,
              label: 'Jan',
            ),
            ChartPoint(
              x: 2,
              y: 95,
              label: 'Feb',
            ),
            ChartPoint(
              x: 3,
              y: 100,
              label: 'Mar',
            ),
            ChartPoint(
              x: 4,
              y: 110,
              label: 'Apr',
            ),
            ChartPoint(
              x: 5,
              y: 130,
              label: 'May',
            ),
            ChartPoint(
              x: 6,
              y: 125,
              label: 'Jun',
            ),
          ],
        ),
      ],

      xAxisTitle: 'Month',
      yAxisTitle: 'USD (thousands)',
    );
  }

  // ==========================================================
  // BAR CHART
  // ==========================================================

  Widget _buildBarChart({
    required bool stacked,
  }) {
    return BarChart2D(
      title: stacked
          ? 'Units Sold (Stacked)'
          : 'Units Sold (Grouped)',

      subtitle:
          'Drag horizontally to zoom into a category range',

      stacked: stacked,

      onBarTap: (
        series,
        category,
        value,
      ) {
        debugPrint(
          'Tapped $series/$category: $value',
        );
      },

      categories: const [
        'Q1',
        'Q2',
        'Q3',
        'Q4',
      ],

      series: const [
        CategorySeries(
          name: 'North',
          color: Colors.teal,
          values: [
            40,
            55,
            48,
            62,
          ],
        ),
        CategorySeries(
          name: 'South',
          color: Colors.amber,
          values: [
            30,
            35,
            42,
            38,
          ],
        ),
        CategorySeries(
          name: 'East',
          color: Colors.deepPurple,
          values: [
            20,
            28,
            25,
            33,
          ],
        ),
      ],

      xAxisTitle: 'Quarter',
      yAxisTitle: 'Units sold',
    );
  }

  // ==========================================================
  // PIE / DONUT CHART
  // ==========================================================

  Widget _buildPieChart({
    required bool donut,
  }) {
    return PieChart2D(
      title: donut
          ? 'Browser Share (Donut)'
          : 'Browser Share (Pie)',

      subtitle:
          'Pinch or scroll to zoom, drag to pan',

      innerRadiusRatio: donut ? 0.6 : 0,

      onSliceTap: (slice) {
        debugPrint(
          'Tapped slice: ${slice?.label}',
        );
      },

      slices: const [
        PieSlice(
          label: 'Chrome',
          value: 64,
          color: Colors.blue,
        ),
        PieSlice(
          label: 'Safari',
          value: 19,
          color: Colors.orange,
        ),
        PieSlice(
          label: 'Edge',
          value: 9,
          color: Colors.green,
        ),
        PieSlice(
          label: 'Firefox',
          value: 5,
          color: Colors.deepOrange,
        ),
        PieSlice(
          label: 'Other',
          value: 3,
          color: Colors.grey,
        ),
      ],

      valueFormatter: (v) =>
          '${v.toStringAsFixed(0)}%',
    );
  }

  // ==========================================================
  // SCATTER CHART
  // ==========================================================

  Widget _buildScatterChart() {
    return ScatterChart2D(
      title: 'Practice vs. Score',
      subtitle:
          'Drag a rectangle to zoom into both axes',

      onPointTap: (series, point) {
        if (point != null) {
          debugPrint(
            'Tapped $series: ${point.label}',
          );
        }
      },

      series: [
        XySeries(
          name: 'Cohort A',
          color: Colors.blue,
          data: const [
            ChartPoint(
              x: 2.1,
              y: 65,
              label: 'User 1',
            ),
            ChartPoint(
              x: 4.5,
              y: 78,
              label: 'User 2',
            ),
            ChartPoint(
              x: 6.2,
              y: 85,
              label: 'User 3',
            ),
            ChartPoint(
              x: 3.0,
              y: 70,
              label: 'User 4',
            ),
            ChartPoint(
              x: 8.1,
              y: 92,
              label: 'User 5',
            ),
          ],
        ),

        XySeries(
          name: 'Cohort B',
          color: Colors.pink,
          data: const [
            ChartPoint(
              x: 1.5,
              y: 55,
              label: 'User 6',
            ),
            ChartPoint(
              x: 5.0,
              y: 60,
              label: 'User 7',
            ),
            ChartPoint(
              x: 7.4,
              y: 68,
              label: 'User 8',
            ),
            ChartPoint(
              x: 3.8,
              y: 58,
              label: 'User 9',
            ),
          ],
        ),
      ],

      xAxisTitle: 'Hours practiced',
      yAxisTitle: 'Score',
    );
  }
}

// ============================================================
// 3D SURFACE CHART
// ============================================================

class Surface3DPage extends StatelessWidget {
  const Surface3DPage({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    final isMobile = size.width < 600;
    final isTablet =
        size.width >= 600 && size.width < 1024;

    const data = [
      [12.0, 18.0, 9.0, 22.0],
      [15.0, 20.0, 11.0, 25.0],
      [19.0, 24.0, 14.0, 30.0],
      [23.0, 29.0, 17.0, 35.0],
    ];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(
          isMobile
              ? 8
              : isTablet
                  ? 16
                  : 24,
        ),
        child: LayoutBuilder(
          builder: (
            context,
            constraints,
          ) {
            final availableHeight =
                constraints.maxHeight;

            final chartHeight = isMobile
                ? availableHeight * 0.75
                : isTablet
                    ? availableHeight * 0.82
                    : availableHeight * 0.85;

            return Center(
              child: SizedBox(
                width: constraints.maxWidth,
                height: chartHeight,
                child: Surface3DChart(
                  data: data,

                  xLabels: const [
                    'North',
                    'South',
                    'East',
                    'West',
                  ],

                  yLabels: const [
                    'Jan',
                    'Feb',
                    'Mar',
                    'Apr',
                  ],

                  xAxisTitle: 'Region',
                  yAxisTitle: 'Month',
                  zAxisTitle: 'Sales',

                  valueFormatter: (v) =>
                      '\$${v.toStringAsFixed(0)}k',

                  gradient: const [
                    Colors.teal,
                    Colors.amber,
                    Colors.deepOrange,
                  ],

                  showLegend: true,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
