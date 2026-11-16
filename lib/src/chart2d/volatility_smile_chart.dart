import 'package:flutter/material.dart';
import 'cartesian_axes.dart';
import 'controller.dart';
import 'curves.dart';
import 'line_chart.dart';
import 'models.dart';
import 'reference.dart';

/// Implied volatility by strike for one expiry.
class VolatilitySmile {
  /// E.g. "28 Nov" or "Weekly".
  final String label;

  /// Strike → implied volatility (0.14 = 14%). Strikes without a valid IV
  /// (null, NaN or ≤ 0) are skipped.
  final Map<double, double?> points;
  final Color color;

  const VolatilitySmile({required this.label, required this.points, required this.color});
}

/// The volatility smile (or skew): implied volatility across strikes, one
/// curve per expiry. Puts below spot usually carry more IV than calls above
/// it — the skew — and short-dated expiries smile more steeply.
///
/// ```dart
/// VolatilitySmileChart2D(
///   spot: 24480,
///   smiles: [
///     VolatilitySmile(label: 'Weekly', color: Colors.indigo, points: {24000: 0.168, 24500: 0.131, 25000: 0.142}),
///     VolatilitySmile(label: 'Monthly', color: Colors.teal, points: {...}),
///   ],
/// )
/// ```
///
/// Compute IVs from option prices with [OptionMath.impliedVolatility].
/// For a 3D view across expiries, feed the same grid to `Surface3DChart`.
class VolatilitySmileChart2D extends StatelessWidget {
  final List<VolatilitySmile> smiles;
  final double? spot;
  final String? title;
  final String? subtitle;
  final String Function(double strike) strikeFormatter;
  final bool showPoints;
  final bool enableAnimation;
  final ChartController? controller;

  const VolatilitySmileChart2D({
    super.key,
    required this.smiles,
    this.spot,
    this.title,
    this.subtitle,
    this.strikeFormatter = Cartesian2DAxes.formatNumber,
    this.showPoints = true,
    this.enableAnimation = true,
    this.controller,
  });

  /// 0.135 → "13.5%", 0.14 → "14%".
  static String _pct(double v) {
    final p = double.parse((v * 100).toStringAsFixed(1));
    return '${p == p.roundToDouble() ? p.toInt() : p}%';
  }

  @override
  Widget build(BuildContext context) {
    return LineChart2D(
      title: title,
      subtitle: subtitle,
      controller: controller,
      enableAnimation: enableAnimation,
      curve: LineChartCurve.smooth,
      showPoints: showPoints,
      emptyStateMessage: 'No implied volatility data',
      xTickFormatter: strikeFormatter,
      yTickFormatter: _pct,
      referenceLines: [
        if (spot != null) ChartReferenceLine.x(spot!, label: 'Spot ${strikeFormatter(spot!)}'),
      ],
      series: [
        for (final s in smiles)
          XySeries(
            name: s.label,
            color: s.color,
            data: [
              for (final e in (s.points.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
                if (e.value != null && e.value!.isFinite && e.value! > 0) ChartPoint(x: e.key, y: e.value!),
            ],
          ),
      ],
    );
  }
}
