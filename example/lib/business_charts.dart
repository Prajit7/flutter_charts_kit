import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_charts_kit/flutter_charts_kit.dart';

/// Fourth tab of the demo: waterfall, bullet, calendar heatmap, sunburst,
/// rose and radial bars, range charts, lollipops and a Gantt chart.
class BusinessChartsPage extends StatelessWidget {
  const BusinessChartsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final padding = width < 600 ? 8.0 : (width < 1024 ? 16.0 : 24.0);
    Widget card(Widget child, {double height = 320}) => Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: SizedBox(height: height, child: child),
        );
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: 16),
      children: [
        card(const WaterfallChart2D(
          title: 'Revenue to net profit',
          subtitle: 'Each bar adds or removes from the running total',
          steps: [
            WaterfallStep(label: 'Revenue', value: 420),
            WaterfallStep(label: 'COGS', value: -180),
            WaterfallStep.total('Gross'),
            WaterfallStep(label: 'Opex', value: -110),
            WaterfallStep(label: 'Other', value: 18),
            WaterfallStep(label: 'Tax', value: -32),
            WaterfallStep.total('Net'),
          ],
        )),
        card(const _BulletPanel(), height: 260),
        card(_calendar(), height: 240),
        card(const SunburstChart2D(
          title: 'Budget',
          subtitle: 'Tap a ring to zoom in, the centre to zoom out',
          nodes: [
            TreemapNode(label: 'Engineering', children: [
              TreemapNode(label: 'Salaries', value: 820),
              TreemapNode(label: 'Cloud', children: [
                TreemapNode(label: 'Compute', value: 150),
                TreemapNode(label: 'Storage', value: 90),
                TreemapNode(label: 'Network', value: 40),
              ]),
              TreemapNode(label: 'Tools', value: 90),
            ]),
            TreemapNode(label: 'Marketing', children: [
              TreemapNode(label: 'Ads', value: 300),
              TreemapNode(label: 'Events', value: 120),
              TreemapNode(label: 'Content', value: 70),
            ]),
            TreemapNode(label: 'Sales', value: 380),
            TreemapNode(label: 'Office', value: 150),
          ],
        ), height: 380),
        card(const PolarBarChart2D(
          title: 'Orders by hour',
          subtitle: 'Rose chart — wedge area ∝ orders',
          categories: ['0', '2', '4', '6', '8', '10', '12', '14', '16', '18', '20', '22'],
          series: [
            CategorySeries(name: 'Online', color: Color(0xFF3949AB), values: [8, 4, 2, 5, 18, 30, 34, 31, 28, 36, 30, 18]),
            CategorySeries(name: 'Store', color: Color(0xFF26A69A), values: [0, 0, 0, 2, 10, 22, 26, 24, 20, 14, 4, 0]),
          ],
        ), height: 360),
        card(const PolarBarChart2D(
          title: 'Quarterly goals',
          style: PolarBarStyle.radial,
          max: 100,
          showLegend: false,
          valueFormatter: _percent,
          categories: ['Sales', 'Leads', 'Retention', 'NPS', 'Hiring'],
          series: [CategorySeries(name: 'Progress', color: Color(0xFF00897B), values: [86, 64, 92, 48, 71])],
        )),
        card(RangeChart2D(
          title: 'Daily temperature range',
          subtitle: 'Floating bars from low to high',
          valueFormatter: (v) => '${v.round()}°',
          categories: const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'],
          series: const [
            RangeSeries(name: 'Range', color: Color(0xFFF4511E), values: [
              RangeValue(14, 29), RangeValue(16, 31), RangeValue(19, 34), RangeValue(23, 37), RangeValue(25, 38), RangeValue(24, 33),
              RangeValue(23, 30), RangeValue(22, 30), RangeValue(22, 31), RangeValue(20, 32), RangeValue(17, 31), RangeValue(14, 29),
            ]),
          ],
        )),
        card(const RangeChart2D(
          title: 'Median salary, 2025 to 2026',
          subtitle: 'Dumbbells: first value faded, second solid',
          style: RangeChartStyle.dumbbell,
          categories: ['Eng', 'Design', 'Sales', 'Ops', 'Support'],
          series: [
            RangeSeries(name: 'Change', color: Color(0xFF3949AB), values: [
              RangeValue(92, 104), RangeValue(78, 83), RangeValue(70, 81), RangeValue(64, 66), RangeValue(52, 58),
            ]),
          ],
        )),
        card(_forecast()),
        card(const BarChart2D(
          title: 'Feature usage',
          subtitle: 'Lollipop style',
          barStyle: BarStyle.lollipop,
          showLegend: false,
          showValueLabels: true,
          horizontal: true,
          categories: ['Search', 'Export', 'Filters', 'Sharing', 'Dark mode', 'Alerts'],
          series: [CategorySeries(name: 'Users', color: Color(0xFF7E57C2), values: [82, 41, 66, 23, 58, 35])],
        )),
        card(_gantt(), height: 340),
      ],
    );
  }

  static String _percent(double v) => '${v.round()}%';

  Widget _calendar() {
    final rnd = math.Random(3);
    final today = DateTime.now();
    final start = DateTime(today.year, today.month - 11, 1);
    return CalendarHeatmap(
      title: 'Daily activity',
      subtitle: 'Last 12 months',
      start: start,
      end: today,
      values: {
        for (var d = start; !d.isAfter(today); d = DateTime(d.year, d.month, d.day + 1))
          if (d.weekday < 6 && rnd.nextDouble() > 0.2) d: (rnd.nextDouble() * 12).roundToDouble(),
      },
    );
  }

  Widget _forecast() {
    return RangeChart2D(
      title: 'Demand forecast',
      subtitle: 'Band = 80% interval, line = expected',
      style: RangeChartStyle.area,
      categories: [for (int w = 1; w <= 12; w++) 'W$w'],
      series: [
        RangeSeries(name: 'Demand', color: const Color(0xFF00897B), values: [
          for (int w = 0; w < 12; w++)
            RangeValue(100 + w * 2 - w * 1.4, 100 + w * 2 + w * 1.8, mid: 100 + w * 2.0 + math.sin(w / 2) * 2),
        ]),
      ],
    );
  }

  Widget _gantt() {
    final today = DateTime.now();
    final d0 = DateTime(today.year, today.month, today.day - 20);
    DateTime at(int days) => DateTime(d0.year, d0.month, d0.day + days);
    return GanttChart2D(
      title: 'Release plan',
      subtitle: 'Drag to scroll, pinch or wheel to zoom',
      tasks: [
        GanttTask(id: 'spec', label: 'Spec', group: 'Plan', start: at(0), end: at(6), progress: 1),
        GanttTask(id: 'design', label: 'Design', group: 'Plan', start: at(4), end: at(16), progress: 1, dependsOn: const ['spec']),
        GanttTask(id: 'api', label: 'API', group: 'Build', start: at(14), end: at(32), progress: 0.6, dependsOn: const ['design']),
        GanttTask(id: 'app', label: 'App', group: 'Build', start: at(17), end: at(38), progress: 0.3, dependsOn: const ['design']),
        GanttTask(id: 'qa', label: 'QA', group: 'Ship', start: at(34), end: at(44), dependsOn: const ['api', 'app']),
        GanttTask.milestone(label: 'Launch', group: 'Ship', at: at(46), dependsOn: const ['qa']),
      ],
    );
  }
}

class _BulletPanel extends StatelessWidget {
  const _BulletPanel();

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const ChartHeader(title: 'KPIs vs target', subtitle: 'Bullet charts: bar = actual, line = target'),
      for (final (label, sub, v, t) in [
        ('Revenue', 'USD k', 270.0, 250.0),
        ('Profit', '%', 22.0, 26.0),
        ('NPS', 'score', 48.0, 40.0),
      ])
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: BulletChart(
              label: label,
              sublabel: sub,
              value: v,
              target: t,
              ranges: [BulletRange(t * 0.6), BulletRange(t * 0.9), BulletRange(t * 1.2)],
            ),
          ),
        ),
    ]);
  }
}
