import 'dart:math' as math;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_charts_kit/flutter_charts_kit.dart';

/// Third tab of the demo: heatmap, gauges, sparklines, radar, candlestick,
/// histogram, box plot, funnel, treemap and Sankey.
class SpecialtyChartsPage extends StatelessWidget {
  const SpecialtyChartsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final padding = width < 600 ? 8.0 : (width < 1024 ? 16.0 : 24.0);
    const h = 320.0;
    Widget card(Widget child, {double height = h}) => Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: SizedBox(height: height, child: child),
        );

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: 16),
      children: [
        card(const _KpiRow(), height: 132),
        card(const _GaugesDemo(), height: 220),
        card(_heatmap()),
        card(const LiveTradingDemo(), height: 520),
        card(_radar()),
        card(_histogram()),
        card(_boxPlot()),
        card(_funnel()),
        card(_treemap()),
        card(_sankey(), height: 360),
      ],
    );
  }

  Widget _heatmap() {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return HeatmapChart2D(
      title: 'Support tickets by hour',
      subtitle: 'Hover a cell for its count',
      legendTitle: 'Tickets',
      gradient: const [Color(0xFFE8F5E9), Color(0xFF43A047), Color(0xFF1B5E20)],
      xLabels: [for (int hr = 8; hr <= 20; hr++) '$hr'],
      yLabels: days,
      data: [
        for (int d = 0; d < 7; d++)
          [
            for (int hr = 8; hr <= 20; hr++)
              d >= 5 && hr < 10 ? null : ((math.sin(hr / 3.0) + 1.3) * (d >= 5 ? 4 : 12) + (d * 3 + hr) % 5).roundToDouble(),
          ],
      ],
    );
  }

  Widget _radar() => const RadarChart2D(
        title: 'Product comparison',
        axes: ['Speed', 'Battery', 'Camera', 'Display', 'Price', 'Build'],
        max: 10,
        series: [
          CategorySeries(name: 'Phone X', color: Colors.indigo, values: [9, 6, 8, 9, 4, 8]),
          CategorySeries(name: 'Phone Y', color: Colors.orange, values: [7, 9, 6, 7, 8, 6]),
        ],
      );

  Widget _histogram() {
    final rnd = math.Random(3);
    // Roughly log-normal latencies.
    final values = [for (int i = 0; i < 800; i++) math.exp(4.6 + 0.35 * _gaussian(rnd))];
    return Histogram2D(
      title: 'API latency',
      subtitle: '800 requests, auto-binned',
      xAxisTitle: 'ms',
      yAxisTitle: 'Requests',
      values: values,
      showMean: true,
      valueFormatter: (v) => v.toStringAsFixed(0),
    );
  }

  static double _gaussian(math.Random r) =>
      math.sqrt(-2 * math.log(1 - r.nextDouble())) * math.cos(2 * math.pi * r.nextDouble());

  Widget _boxPlot() {
    final rnd = math.Random(11);
    List<double> sample(double mean, double sd, int n) => [for (int i = 0; i < n; i++) mean + sd * _gaussian(rnd)];
    return BoxPlot2D(
      title: 'Ticket resolution time',
      yAxisTitle: 'Hours',
      groups: [
        BoxPlotGroup(label: 'Tier 1', values: [...sample(6, 2, 60), 19, 22]),
        BoxPlotGroup(label: 'Tier 2', values: sample(14, 4, 40), color: Colors.teal),
        BoxPlotGroup(label: 'Tier 3', values: [...sample(30, 8, 25), 70], color: Colors.deepOrange),
      ],
      valueFormatter: (v) => v.toStringAsFixed(1),
    );
  }

  Widget _funnel() => const FunnelChart2D(
        title: 'Signup funnel',
        subtitle: 'Hover a stage for step-to-step conversion',
        stages: [
          FunnelStage(label: 'Visited site', value: 24000),
          FunnelStage(label: 'Viewed pricing', value: 9600),
          FunnelStage(label: 'Started trial', value: 3100),
          FunnelStage(label: 'Activated', value: 1400),
          FunnelStage(label: 'Paid', value: 520),
        ],
      );

  Widget _treemap() => const TreemapChart2D(
        title: 'Annual budget',
        subtitle: 'Nested groups, squarified layout',
        nodes: [
          TreemapNode(label: 'Engineering', children: [
            TreemapNode(label: 'Salaries', value: 820),
            TreemapNode(label: 'Cloud', value: 240),
            TreemapNode(label: 'Tools', value: 90),
          ]),
          TreemapNode(label: 'Marketing', children: [
            TreemapNode(label: 'Ads', value: 300),
            TreemapNode(label: 'Events', value: 120),
            TreemapNode(label: 'Content', value: 70),
          ]),
          TreemapNode(label: 'Sales', value: 380),
          TreemapNode(label: 'Office', value: 150),
          TreemapNode(label: 'Legal', value: 60),
        ],
      );

  Widget _sankey() => const SankeyChart2D(
        title: 'User journey',
        subtitle: 'Where visitors come from and where they end up',
        links: [
          SankeyLink(source: 'Ads', target: 'Landing page', value: 500),
          SankeyLink(source: 'Search', target: 'Landing page', value: 700),
          SankeyLink(source: 'Search', target: 'Blog', value: 300),
          SankeyLink(source: 'Social', target: 'Blog', value: 220),
          SankeyLink(source: 'Landing page', target: 'Sign up', value: 450),
          SankeyLink(source: 'Landing page', target: 'Bounced', value: 750),
          SankeyLink(source: 'Blog', target: 'Sign up', value: 140),
          SankeyLink(source: 'Blog', target: 'Bounced', value: 380),
          SankeyLink(source: 'Sign up', target: 'Paid', value: 190),
          SankeyLink(source: 'Sign up', target: 'Churned', value: 400),
        ],
      );
}

/// KPI cards with inline sparklines.
class _KpiRow extends StatelessWidget {
  const _KpiRow();

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    Widget kpi(String label, String value, List<double> trend, Color color, {SparklineType type = SparklineType.line}) =>
        Expanded(
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 12, color: theme.subtitleColor), overflow: TextOverflow.ellipsis),
                  Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.titleColor)),
                  const SizedBox(height: 6),
                  Expanded(child: Sparkline(values: trend, color: color, filled: true, type: type, negativeColor: Colors.red)),
                ],
              ),
            ),
          ),
        );
    return Row(children: [
      kpi('Revenue', '\$48.2k', [31, 34, 33, 38, 41, 40, 45, 48], Colors.green),
      kpi('Churn', '2.1%', [3.4, 3.1, 3.2, 2.8, 2.6, 2.4, 2.3, 2.1], Colors.orange),
      kpi('Net flow', '+12', [4, -2, 6, 3, -5, 8, 12], Colors.indigo, type: SparklineType.bar),
    ]);
  }
}

class _GaugesDemo extends StatefulWidget {
  const _GaugesDemo();

  @override
  State<_GaugesDemo> createState() => _GaugesDemoState();
}

class _GaugesDemoState extends State<_GaugesDemo> {
  double _cpu = 64;
  double _speed = 38;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: Row(children: [
          Expanded(
            child: GaugeChart(
              value: _cpu,
              label: 'CPU',
              valueFormatter: (v) => '${v.round()}%',
              ranges: const [
                GaugeRange(from: 0, to: 60, color: Colors.green),
                GaugeRange(from: 60, to: 85, color: Colors.orange),
                GaugeRange(from: 85, to: 100, color: Colors.red),
              ],
            ),
          ),
          Expanded(
            child: GaugeChart(
              value: _speed,
              max: 120,
              label: 'km/h',
              style: GaugeStyle.needle,
              sweepAngle: 180,
              ranges: const [
                GaugeRange(from: 0, to: 90, color: Colors.teal),
                GaugeRange(from: 90, to: 120, color: Colors.redAccent),
              ],
            ),
          ),
        ]),
      ),
      TextButton.icon(
        onPressed: () => setState(() {
          final r = math.Random();
          _cpu = 10 + r.nextDouble() * 88;
          _speed = r.nextDouble() * 115;
        }),
        icon: const Icon(Icons.shuffle, size: 18),
        label: const Text('Randomize'),
      ),
    ]);
  }
}

/// A live trading chart: simulated trades every 250ms are aggregated into
/// 5-second candles by [LiveCandles]; the last-price tag flashes on each
/// tick, indicators update live, and zoom survives the updates.
class LiveTradingDemo extends StatefulWidget {
  const LiveTradingDemo({super.key});

  @override
  State<LiveTradingDemo> createState() => _LiveTradingDemoState();
}

class _LiveTradingDemoState extends State<LiveTradingDemo> {
  final _rnd = math.Random(42);
  late final LiveCandles _live;
  late final Timer _timer;
  double _price = 182;

  @override
  void initState() {
    super.initState();
    _live = LiveCandles(interval: const Duration(seconds: 5), maxCandles: 400, history: _history());
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _price = math.max(20, _price + (_rnd.nextDouble() - 0.495) * 0.35);
      _live.addTick(DateTime.now(), double.parse(_price.toStringAsFixed(2)), volume: 200 + _rnd.nextDouble() * 1800);
    });
  }

  /// A couple hundred past 5-second candles so indicators have history.
  List<Candle> _history() {
    final now = DateTime.now();
    final start = now.subtract(const Duration(seconds: 5 * 200));
    final out = <Candle>[];
    for (int i = 0; i < 200; i++) {
      final open = _price;
      _price = math.max(20, _price + (_rnd.nextDouble() - 0.49) * 0.9);
      out.add(Candle(
        time: DateTime.fromMillisecondsSinceEpoch(
            start.millisecondsSinceEpoch - start.millisecondsSinceEpoch % 5000 + i * 5000),
        open: open,
        high: math.max(open, _price) + _rnd.nextDouble() * 0.4,
        low: math.min(open, _price) - _rnd.nextDouble() * 0.4,
        close: _price,
        volume: 8000 + _rnd.nextDouble() * 20000,
      ));
    }
    return out;
  }

  @override
  void dispose() {
    _timer.cancel();
    _live.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _live,
      builder: (context, _) {
        final ltp = _live.lastPrice ?? 0;
        final up = (_live.previousPrice ?? ltp) <= ltp;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // A ticker header that flips color with each tick's direction.
          Row(children: [
            const Text('ACME', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(width: 10),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: up ? const Color(0xFF26A69A) : const Color(0xFFEF5350),
              ),
              child: Text('${ltp.toStringAsFixed(2)} ${up ? '▲' : '▼'}'),
            ),
            const SizedBox(width: 10),
            const Flexible(
              child: Text('LIVE · 5s candles', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: CandlestickChart2D(
              candles: _live.candles,
              lastPrice: _live.lastPrice,
              visibleCandles: 90,
              showVolume: true,
              enableAnimation: false,
              // Follow the app's light/dark toggle; on its own the chart
              // would default to the dark trading theme.
              indicators: const [
                MovingAverageIndicator(period: 20),
                MovingAverageIndicator(period: 50, type: MovingAverageType.exponential, color: Color(0xFF26C6DA)),
                BollingerBandsIndicator(),
                RsiIndicator(),
                MacdIndicator(),
              ],
            ),
          ),
        ]);
      },
    );
  }
}
