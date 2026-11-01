import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_charts_kit/flutter_charts_kit.dart';

/// Demos for the time axis, curves, stacked areas, horizontal bars, value
/// labels, reference lines/bands, combo charts, and [ChartController].

/// A line chart over real dates, driven by a [ChartController] from the
/// toolbar above it (reset zoom + export to PNG).
class TimeSeriesDemo extends StatefulWidget {
  const TimeSeriesDemo({super.key});

  @override
  State<TimeSeriesDemo> createState() => _TimeSeriesDemoState();
}

class _TimeSeriesDemoState extends State<TimeSeriesDemo> {
  final _controller = ChartController();

  static final _start = DateTime(2026, 1, 1);
  static final _visits = [
    for (int d = 0; d < 90; d++) ChartPoint.at(_start.add(Duration(days: d)), y: 400 + (d * 37 % 160) + d * 3.0),
  ];
  static final _signups = [
    for (int d = 0; d < 90; d++) ChartPoint.at(_start.add(Duration(days: d)), y: 120 + (d * 23 % 90) + d * 1.5),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    final png = await _controller.toPngBytes();
    if (png == null) return;
    // A real app would save or share these bytes; the demo just reports them.
    messenger.showSnackBar(SnackBar(content: Text('Exported PNG (${(png.length / 1024).toStringAsFixed(1)} KB)')));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Wrap, not Row: two labelled buttons don't fit side by side on
        // narrow phones.
        Wrap(
          alignment: WrapAlignment.end,
          children: [
            ListenableBuilder(
              listenable: _controller,
              builder: (context, _) => TextButton.icon(
                onPressed: _controller.isZoomed ? _controller.resetZoom : null,
                icon: const Icon(Icons.zoom_out_map, size: 18),
                label: const Text('Reset zoom'),
              ),
            ),
            TextButton.icon(
              onPressed: _export,
              icon: const Icon(Icons.image_outlined, size: 18),
              label: const Text('Export PNG'),
            ),
          ],
        ),
        Expanded(
          child: LineChart2D(
            controller: _controller,
            title: 'Daily traffic',
            subtitle: 'Time axis, smooth curves, reference line + band — drag to zoom',
            xAxisType: ChartAxisType.time,
            curve: LineChartCurve.smooth,
            showPoints: false,
            referenceLines: const [ChartReferenceLine.y(500, label: 'Goal', color: Colors.red)],
            referenceBands: [
              ChartReferenceBand.time(DateTime(2026, 2, 10), DateTime(2026, 2, 20), label: 'Campaign'),
            ],
            series: [
              XySeries(name: 'Visits', color: Colors.indigo, data: _visits),
              XySeries(name: 'Sign-ups', color: Colors.teal, data: _signups),
            ],
          ),
        ),
      ],
    );
  }
}

class StackedAreaDemo extends StatelessWidget {
  const StackedAreaDemo({super.key});

  @override
  Widget build(BuildContext context) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug'];
    XySeries series(String name, Color color, List<double> values) => XySeries(
          name: name,
          color: color,
          data: [for (int i = 0; i < values.length; i++) ChartPoint(x: i.toDouble(), y: values[i], label: months[i])],
        );
    return LineChart2D(
      title: 'Traffic by source',
      subtitle: 'Stacked smooth areas, legend on the right',
      stacked: true,
      filled: true,
      curve: LineChartCurve.smooth,
      showPoints: false,
      legendPosition: ChartLegendPosition.right,
      series: [
        series('Direct', Colors.blue, [30, 34, 31, 38, 42, 40, 45, 48]),
        series('Search', Colors.green, [22, 25, 29, 27, 31, 35, 33, 38]),
        series('Social', Colors.purple, [10, 14, 12, 18, 15, 21, 24, 22]),
      ],
    );
  }
}

class HorizontalBarDemo extends StatelessWidget {
  const HorizontalBarDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return const BarChart2D(
      title: 'Revenue by region',
      subtitle: 'Horizontal bars with value labels and an average line',
      horizontal: true,
      showValueLabels: true,
      showLegend: false,
      categories: ['North America', 'Europe', 'Asia Pacific', 'Latin America', 'Middle East & Africa'],
      series: [CategorySeries(name: 'Revenue', color: Colors.indigo, values: [82, 64, 71, 23, 15])],
      referenceLines: [ChartReferenceLine.y(51, label: 'Avg')],
    );
  }
}

class ComboDemo extends StatelessWidget {
  const ComboDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComboChart2D(
      title: 'Revenue & growth',
      subtitle: 'Bars + a line on a secondary axis — hover a month for every value',
      categories: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'],
      yAxisTitle: 'Revenue (k)',
      secondaryYAxisTitle: 'Growth %',
      curve: LineChartCurve.smooth,
      series: [
        ComboSeries(name: 'Revenue', color: Colors.blue, values: [120, 150, 170, 160, 190, 210]),
        ComboSeries(name: 'Costs', color: Colors.blueGrey, values: [90, 100, 110, 115, 120, 125]),
        ComboSeries.line(name: 'Growth %', color: Colors.orange, values: [4, 25, 13, -6, 19, 11], secondaryAxis: true),
      ],
    );
  }
}

/// Streaming data: a new reading every 200ms, shown in a 30-second live
/// window, next to a 100k-point series that stays smooth thanks to LTTB
/// downsampling.
class LiveDataDemo extends StatefulWidget {
  const LiveDataDemo({super.key});

  @override
  State<LiveDataDemo> createState() => _LiveDataDemoState();
}

class _LiveDataDemoState extends State<LiveDataDemo> {
  static const _windowMs = 30000.0;
  final _readings = <ChartPoint>[];
  late final Timer _timer;
  bool _paused = false;
  double _value = 50;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_paused) return;
      setState(() {
        _value = (_value + (DateTime.now().microsecond % 1000 - 500) / 120).clamp(5, 95);
        _readings.add(ChartPoint.at(DateTime.now(), y: _value));
        // Keep a little more than the window so the left edge stays filled.
        final cutoff = DateTime.now().millisecondsSinceEpoch - _windowMs * 1.2;
        _readings.removeWhere((p) => p.x < cutoff);
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => setState(() => _paused = !_paused),
            icon: Icon(_paused ? Icons.play_arrow : Icons.pause, size: 18),
            label: Text(_paused ? 'Resume' : 'Pause'),
          ),
        ),
        Expanded(
          child: LineChart2D(
            title: 'Live sensor',
            subtitle: 'New reading every 200ms · last 30s · drag to zoom (pauses following)',
            xAxisType: ChartAxisType.time,
            liveWindow: _windowMs,
            updateAnimation: ChartUpdateAnimation.none,
            enableAnimation: false,
            showPoints: false,
            showLegend: false,
            referenceBands: const [ChartReferenceBand.y(40, 60, label: 'Normal')],
            series: [
              // A new list each tick, so the chart sees the change.
              XySeries(name: 'Sensor', color: Colors.teal, data: List.of(_readings)),
            ],
          ),
        ),
      ],
    );
  }
}

class BigDataDemo extends StatelessWidget {
  const BigDataDemo({super.key});

  static final _series = [
    XySeries(
      name: '100k points',
      color: Colors.deepPurple,
      data: [
        for (int i = 0; i < 100000; i++)
          ChartPoint(x: i.toDouble(), y: 50 + 30 * math.sin(i / 3000) + 12 * math.sin(i / 170) + (i % 4999 == 0 ? 35 : 0)),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LineChart2D(
      title: '100,000 points',
      subtitle: 'Downsampled with LTTB to ~1.5 points per pixel — spikes preserved; zoom in for detail',
      showPoints: false,
      showLegend: false,
      series: _series,
    );
  }
}
