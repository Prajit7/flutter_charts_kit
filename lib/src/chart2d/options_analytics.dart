import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'cartesian_axes.dart';
import 'chart_chrome.dart';
import 'crosshair_sync.dart';
import 'curves.dart';
import 'line_chart.dart';
import 'models.dart';
import 'option_math.dart';
import 'reference.dart';

/// One of the option Greeks, for [OptionGreeksChart2D].
enum OptionGreek {
  delta('Delta', 'Position change per 1 point move'),
  gamma('Gamma', 'Delta change per 1 point move'),
  theta('Theta', 'Value change per day'),
  vega('Vega', 'Value change per 1% volatility');

  final String label;
  final String description;
  const OptionGreek(this.label, this.description);

  double of(OptionGreeks g) => switch (this) {
        OptionGreek.delta => g.delta,
        OptionGreek.gamma => g.gamma,
        OptionGreek.theta => g.theta,
        OptionGreek.vega => g.vega,
      };
}

/// A strategy's Greeks across underlying prices — one small chart per
/// Greek, with linked crosshairs and the current spot marked. Pairs with
/// [OptionPayoffChart2D] for the same legs.
///
/// ```dart
/// OptionGreeksChart2D(legs: legs, spot: 24480, daysToExpiry: 6, volatility: 0.13)
/// ```
class OptionGreeksChart2D extends StatefulWidget {
  final List<OptionLeg> legs;
  final double spot;
  final double daysToExpiry;
  final double volatility;
  final double riskFreeRate;
  final List<OptionGreek> greeks;

  /// Price range; defaults to spot ±[rangePercent].
  final double? minPrice;
  final double? maxPrice;
  final double rangePercent;

  /// Grid columns (2 = a 2×2 grid for the four Greeks).
  final int columns;
  final String Function(double price) priceFormatter;
  final List<Color> colors;
  final bool enableAnimation;

  const OptionGreeksChart2D({
    super.key,
    required this.legs,
    required this.spot,
    required this.daysToExpiry,
    this.volatility = 0.15,
    this.riskFreeRate = 0,
    this.greeks = OptionGreek.values,
    this.minPrice,
    this.maxPrice,
    this.rangePercent = 0.05,
    this.columns = 2,
    this.priceFormatter = Cartesian2DAxes.formatNumber,
    this.colors = const [Color(0xFF3949AB), Color(0xFF8E24AA), Color(0xFFF4511E), Color(0xFF00897B)],
    this.enableAnimation = true,
  });

  @override
  State<OptionGreeksChart2D> createState() => _OptionGreeksChart2DState();
}

class _OptionGreeksChart2DState extends State<OptionGreeksChart2D> {
  final _sync = ChartCrosshairSync();

  @override
  void dispose() {
    _sync.dispose();
    super.dispose();
  }

  /// Enough significant digits for tiny Greeks (gamma is often ~0.001).
  static String _fmt(double v) {
    final a = v.abs();
    if (a == 0) return '0';
    if (a >= 100) return v.toStringAsFixed(0);
    if (a >= 1) return Cartesian2DAxes.formatNumber(double.parse(v.toStringAsFixed(2)));
    final digits = (-(math.log(a) / math.ln10).floor() + 1).clamp(2, 8);
    return v.toStringAsFixed(digits).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    if (w.legs.isEmpty || w.greeks.isEmpty) return const ChartEmptyState(message: 'Add a leg to see its Greeks');
    final lo = w.minPrice ?? w.spot * (1 - w.rangePercent), hi = w.maxPrice ?? w.spot * (1 + w.rangePercent);
    const n = 90;
    final xs = [for (int i = 0; i <= n; i++) lo + (hi - lo) * i / n];
    final values = [
      for (final s in xs)
        OptionMath.positionGreeks(w.legs, s, daysToExpiry: w.daysToExpiry, volatility: w.volatility, rate: w.riskFreeRate),
    ];
    final now = OptionMath.positionGreeks(w.legs, w.spot,
        daysToExpiry: w.daysToExpiry, volatility: w.volatility, rate: w.riskFreeRate);
    final charts = [
      for (int k = 0; k < w.greeks.length; k++)
        LineChart2D(
          title: '${w.greeks[k].label}  ${_fmt(w.greeks[k].of(now))}',
          subtitle: w.greeks[k].description,
          crosshairSync: _sync,
          showLegend: false,
          showPoints: false,
          filled: true,
          curve: LineChartCurve.smooth,
          enableAnimation: w.enableAnimation,
          xTickFormatter: w.priceFormatter,
          yTickFormatter: _fmt,
          referenceLines: [
            ChartReferenceLine.x(w.spot, label: 'Spot'),
            const ChartReferenceLine.y(0, dashed: false, strokeWidth: 0.8),
          ],
          series: [
            XySeries(
              name: w.greeks[k].label,
              color: w.colors[k % w.colors.length],
              data: [for (int i = 0; i <= n; i++) ChartPoint(x: xs[i], y: w.greeks[k].of(values[i]))],
            ),
          ],
        ),
    ];
    final rows = (charts.length / w.columns).ceil();
    return Column(children: [
      for (int r = 0; r < rows; r++)
        Expanded(
          child: Row(children: [
            for (int c = 0; c < w.columns; c++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: r * w.columns + c < charts.length ? charts[r * w.columns + c] : const SizedBox(),
                ),
              ),
          ]),
        ),
    ]);
  }
}

/// Open interest at one moment, for [OpenInterestTrendChart2D].
class OpenInterestSnapshot {
  final DateTime time;
  final double callOI;
  final double putOI;

  /// The underlying's price then (optional).
  final double? spot;

  const OpenInterestSnapshot({required this.time, required this.callOI, required this.putOI, this.spot});

  double? get pcr => callOI == 0 ? null : putOI / callOI;
}

/// Open interest through the session: total call vs put OI, and the
/// put/call ratio below it (with the 1.0 line), crosshairs linked.
///
/// ```dart
/// OpenInterestTrendChart2D(snapshots: [
///   OpenInterestSnapshot(time: t0, callOI: 1.2e8, putOI: 1.1e8, spot: 24480),
///   ...
/// ])
/// ```
class OpenInterestTrendChart2D extends StatefulWidget {
  final List<OpenInterestSnapshot> snapshots;
  final String? title;
  final String? subtitle;
  final Color callColor;
  final Color putColor;
  final Color pcrColor;

  /// Show the underlying's price as a third line in the PCR pane's chart.
  final bool showSpot;
  final String Function(double oi) oiFormatter;
  final bool enableAnimation;

  const OpenInterestTrendChart2D({
    super.key,
    required this.snapshots,
    this.title,
    this.subtitle,
    this.callColor = const Color(0xFFEF5350),
    this.putColor = const Color(0xFF26A69A),
    this.pcrColor = const Color(0xFF3949AB),
    this.showSpot = false,
    this.oiFormatter = _compact,
    this.enableAnimation = true,
  });

  static String _compact(double v) {
    final a = v.abs();
    String f(double x) => x >= 100 ? x.toStringAsFixed(0) : x.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
    if (a >= 1e9) return '${f(v / 1e9)}B';
    if (a >= 1e6) return '${f(v / 1e6)}M';
    if (a >= 1e3) return '${f(v / 1e3)}K';
    return f(v);
  }

  @override
  State<OpenInterestTrendChart2D> createState() => _OpenInterestTrendChart2DState();
}

class _OpenInterestTrendChart2DState extends State<OpenInterestTrendChart2D> {
  final _sync = ChartCrosshairSync();

  @override
  void dispose() {
    _sync.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final snaps = [...w.snapshots]..sort((a, b) => a.time.compareTo(b.time));
    if (snaps.isEmpty) return const ChartEmptyState(message: 'No open interest history');
    final last = snaps.last;
    final pcr = [for (final s in snaps) if (s.pcr != null) ChartPoint.at(s.time, y: s.pcr!)];
    return Column(children: [
      Expanded(
        flex: 3,
        child: LineChart2D(
          title: w.title,
          subtitle: w.subtitle ??
              'Calls ${w.oiFormatter(last.callOI)} · Puts ${w.oiFormatter(last.putOI)}'
                  '${last.pcr == null ? '' : ' · PCR ${last.pcr!.toStringAsFixed(2)}'}',
          xAxisType: ChartAxisType.time,
          crosshairSync: _sync,
          showPoints: false,
          includeZero: false,
          enableAnimation: w.enableAnimation,
          yTickFormatter: w.oiFormatter,
          series: [
            XySeries(name: 'Call OI', color: w.callColor, data: [for (final s in snaps) ChartPoint.at(s.time, y: s.callOI)]),
            XySeries(name: 'Put OI', color: w.putColor, data: [for (final s in snaps) ChartPoint.at(s.time, y: s.putOI)]),
          ],
        ),
      ),
      Expanded(
        flex: 2,
        child: LineChart2D(
          subtitle: 'Put/call ratio',
          xAxisType: ChartAxisType.time,
          crosshairSync: _sync,
          showPoints: false,
          showLegend: false,
          includeZero: false,
          enableAnimation: w.enableAnimation,
          yTickFormatter: (v) => v.toStringAsFixed(2),
          referenceLines: const [ChartReferenceLine.y(1, label: 'PCR 1.0')],
          series: [XySeries(name: 'PCR', color: w.pcrColor, data: pcr)],
        ),
      ),
    ]);
  }
}
