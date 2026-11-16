import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_charts_kit/flutter_charts_kit.dart';

import 'code_card.dart';

/// Seventh tab of the demo: bump, slope, Marimekko, streamgraph, beeswarm,
/// ridgeline, tree and timeline charts.
class StoryChartsPage extends StatelessWidget {
  const StoryChartsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final padding = width < 600 ? 8.0 : (width < 1024 ? 16.0 : 24.0);
    Widget card(Widget child, String code, {double height = 380}) => CodeCard(code: snippets[code]!, height: height, child: child);
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: 16),
      children: [
        card(bumpDemo(), 'bump'),
        card(slopeDemo(), 'slope'),
        card(marimekkoDemo(), 'marimekko'),
        card(tableDemo(), 'table'),
        card(streamDemo(), 'stream'),
        card(beeswarmDemo(), 'beeswarm'),
        card(ridgelineDemo(), 'ridgeline', height: 440),
        card(treeDemo(), 'tree', height: 440),
        card(timelineDemo(), 'timeline', height: 420),
      ],
    );
  }
}

Widget bumpDemo({bool animate = true}) => BumpChart2D(
      title: 'App store ranking',
      subtitle: 'Rank by downloads each quarter · hover a line',
      enableAnimation: animate,
      periods: const ['Q1', 'Q2', 'Q3', 'Q4', 'Q1 ’26', 'Q2 ’26'],
      series: const [
        CategorySeries(name: 'Zepto', color: Color(0xFF8E24AA), values: [40, 52, 61, 70, 74, 80]),
        CategorySeries(name: 'Blinkit', color: Color(0xFFFFB300), values: [72, 70, 68, 66, 71, 76]),
        CategorySeries(name: 'Swiggy', color: Color(0xFFF4511E), values: [80, 74, 66, 60, 58, 57]),
        CategorySeries(name: 'BigBasket', color: Color(0xFF43A047), values: [55, 50, 47, 52, 49, 45]),
        CategorySeries(name: 'JioMart', color: Color(0xFF1E88E5), values: [30, 35, 50, 48, 54, 50]),
      ],
    );

Widget slopeDemo({bool animate = true}) => SlopeChart2D(
      title: 'Conversion rate by channel',
      subtitle: 'Before vs after the checkout redesign',
      startLabel: 'Before',
      endLabel: 'After',
      enableAnimation: animate,
      valueFormatter: (v) => '${v.toStringAsFixed(1)}%',
      items: const [
        SlopeItem(label: 'Organic', start: 3.1, end: 4.2),
        SlopeItem(label: 'Paid search', start: 2.4, end: 2.9),
        SlopeItem(label: 'Email', start: 5.6, end: 5.1),
        SlopeItem(label: 'Social', start: 1.2, end: 1.9),
        SlopeItem(label: 'Referral', start: 3.8, end: 3.6),
        SlopeItem(label: 'Direct', start: 4.4, end: 5.3),
      ],
    );

Widget marimekkoDemo({bool animate = true}) => MarimekkoChart2D(
      title: 'Market share by segment',
      subtitle: 'Column width = segment size · height = share within it',
      enableAnimation: animate,
      valueFormatter: (v) => '₹${v.round()}Cr',
      categories: const ['Retail', 'SMB', 'Mid-market', 'Enterprise'],
      series: const [
        CategorySeries(name: 'Us', color: Color(0xFF3949AB), values: [120, 210, 160, 90]),
        CategorySeries(name: 'Rival A', color: Color(0xFF00897B), values: [300, 140, 120, 260]),
        CategorySeries(name: 'Rival B', color: Color(0xFFF4511E), values: [180, 90, 60, 150]),
        CategorySeries(name: 'Others', color: Color(0xFF9E9E9E), values: [200, 120, 50, 40]),
      ],
    );

Widget streamDemo({bool animate = true}) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  List<double> wave(double base, double amp, double phase, double trend) =>
      [for (int i = 0; i < 12; i++) math.max(0, base + amp * math.sin(i / 2 + phase) + trend * i)];
  return StreamgraphChart2D(
    title: 'Listening by genre',
    subtitle: 'Hours streamed per month · tap a legend chip to hide a layer',
    enableAnimation: animate,
    labels: months,
    series: [
      CategorySeries(name: 'Pop', color: const Color(0xFFEC407A), values: wave(40, 10, 0, 1)),
      CategorySeries(name: 'Hip-hop', color: const Color(0xFF7E57C2), values: wave(30, 12, 1, 2)),
      CategorySeries(name: 'Bollywood', color: const Color(0xFFFFA726), values: wave(45, 15, 2, -1)),
      CategorySeries(name: 'Indie', color: const Color(0xFF26A69A), values: wave(15, 6, 3, 1.5)),
      CategorySeries(name: 'Classical', color: const Color(0xFF5C6BC0), values: wave(10, 4, 4, 0)),
    ],
  );
}

Widget beeswarmDemo({bool animate = true}) {
  final rnd = math.Random(9);
  List<double> times(double mean, double sd, int n) =>
      [for (int i = 0; i < n; i++) math.max(20, mean + sd * (rnd.nextDouble() + rnd.nextDouble() + rnd.nextDouble() - 1.5) * 1.4)];
  return BeeswarmChart2D(
    title: 'API latency by region',
    subtitle: 'Every request as a dot · bar = median',
    enableAnimation: animate,
    valueFormatter: (v) => '${v.round()} ms',
    groups: [
      BeeswarmGroup(label: 'Mumbai', color: const Color(0xFF3949AB), values: times(120, 30, 70)),
      BeeswarmGroup(label: 'Singapore', color: const Color(0xFF00897B), values: times(180, 40, 70)),
      BeeswarmGroup(label: 'Frankfurt', color: const Color(0xFFF4511E), values: [...times(260, 45, 66), 520, 610, 480]),
    ],
  );
}

Widget ridgelineDemo({bool animate = true}) {
  final rnd = math.Random(3);
  double normal() => (rnd.nextDouble() + rnd.nextDouble() + rnd.nextDouble() + rnd.nextDouble() - 2) * 1.7;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  // Daily max temperatures in Bengaluru-ish shapes.
  const means = [28.0, 31, 33, 34, 33, 29, 27, 27, 28, 28, 27, 27];
  return RidgelineChart2D(
    title: 'Daily max temperature',
    subtitle: 'Distribution per month · line = median',
    enableAnimation: animate,
    valueFormatter: (v) => '${v.round()}°C',
    groups: [
      for (int m = 0; m < 12; m++)
        RidgelineGroup(label: months[m], values: [for (int d = 0; d < 30; d++) means[m] + normal() * (m >= 5 && m <= 8 ? 1.2 : 1.6)]),
    ],
  );
}

Widget treeDemo() => const TreeChart2D(
      title: 'Organisation',
      // A wide, shallow org reads better growing sideways.
      orientation: TreeOrientation.leftToRight,
      subtitle: 'Tap a node to collapse or expand · drag to pan, pinch or scroll to zoom',
      initialDepth: 2,
      root: TreeChartNode(label: 'Ananya Rao', subtitle: 'CEO', children: [
        TreeChartNode(label: 'Vikram Shah', subtitle: 'CTO', children: [
          TreeChartNode(label: 'Platform', subtitle: '12 engineers', children: [
            TreeChartNode(label: 'Infra', subtitle: '5'),
            TreeChartNode(label: 'Data', subtitle: '7'),
          ]),
          TreeChartNode(label: 'Mobile', subtitle: '8 engineers'),
          TreeChartNode(label: 'Web', subtitle: '6 engineers'),
        ]),
        TreeChartNode(label: 'Meera Iyer', subtitle: 'CFO', children: [
          TreeChartNode(label: 'Accounts', subtitle: '4'),
          TreeChartNode(label: 'Legal', subtitle: '2'),
        ]),
        TreeChartNode(label: 'Rohan Das', subtitle: 'COO', children: [
          TreeChartNode(label: 'Support', subtitle: '15'),
          TreeChartNode(label: 'Ops', subtitle: '9'),
          TreeChartNode(label: 'Sales', subtitle: '11'),
        ]),
      ]),
    );

Widget timelineDemo() => TimelineChart2D(
      title: 'Product history',
      subtitle: 'Moments on stems, periods as bars · hover for details',
      dateFormatter: (t) {
        const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return '${t.day} ${m[t.month - 1]} ${t.year}';
      },
      events: [
        TimelineEvent(start: DateTime(2025, 1, 15), title: 'Founded', description: 'Two founders, one laptop.'),
        TimelineEvent(start: DateTime(2025, 2, 1), end: DateTime(2025, 6, 30), title: 'Beta', color: const Color(0xFF9E9E9E)),
        TimelineEvent(start: DateTime(2025, 4, 10), title: 'Seed round', description: '₹8 Cr from angels.'),
        TimelineEvent(start: DateTime(2025, 7, 1), title: 'v1.0 launch', description: 'Public launch on web and Android.'),
        TimelineEvent(start: DateTime(2025, 8, 20), title: 'Outage', color: const Color(0xFFE53935), description: '3-hour database outage.'),
        TimelineEvent(start: DateTime(2025, 9, 1), end: DateTime(2026, 2, 28), title: 'iOS app', color: const Color(0xFF00897B)),
        TimelineEvent(start: DateTime(2025, 11, 5), title: '100k users'),
        TimelineEvent(start: DateTime(2026, 1, 20), title: 'Series A', description: '₹60 Cr led by a VC fund.'),
        TimelineEvent(start: DateTime(2026, 3, 15), title: 'v2.0', description: 'Redesign and offline mode.'),
      ],
    );

/// The same Marimekko data with a chart ⇄ table toggle and Indian-locale
/// currency formatting.
Widget tableDemo() {
  const segments = ['Retail', 'SMB', 'Mid-market', 'Enterprise'];
  const series = [
    CategorySeries(name: 'Us', color: Color(0xFF3949AB), values: [1.2e7, 2.1e7, 1.6e7, 9e6]),
    CategorySeries(name: 'Rival A', color: Color(0xFF00897B), values: [3e7, 1.4e7, 1.2e7, 2.6e7]),
    CategorySeries(name: 'Rival B', color: Color(0xFFF4511E), values: [1.8e7, 9e6, 6e6, 1.5e7]),
  ];
  return Builder(builder: (context) {
    const f = ChartLocale.indian;
    String money(double v) => f.currency(v, compactForm: true);
    return ChartWithTable(
      chart: MarimekkoChart2D(
        title: 'Revenue by segment (table toggle, top right)',
        subtitle: 'Indian number format: ₹1.2Cr, ₹90L',
        categories: segments,
        series: series,
        valueFormatter: money,
      ),
      table: ChartDataTable.fromCategorySeries(categories: segments, series: series, categoryLabel: 'Segment', valueFormatter: money),
    );
  });
}
