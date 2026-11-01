import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'candlestick_chart.dart' show Candle;

/// One line an indicator draws, aligned 1:1 with the candles (null where
/// there isn't enough history yet, e.g. the first 19 bars of a 20-period SMA).
class IndicatorLine {
  final String name;
  final Color color;
  final List<double?> values;
  final double width;

  const IndicatorLine(this.name, this.color, this.values, {this.width = 1.4});
}

/// Bars drawn from zero (e.g. the MACD histogram), aligned with the candles.
class IndicatorHistogram {
  final List<double?> values;
  final Color positiveColor;
  final Color negativeColor;

  const IndicatorHistogram(this.values, this.positiveColor, this.negativeColor);
}

/// What an indicator computes for a set of candles.
class IndicatorResult {
  final List<IndicatorLine> lines;
  final IndicatorHistogram? histogram;

  /// A shaded range between two of [lines] (by index), e.g. Bollinger Bands.
  final (int upper, int lower, Color color)? band;

  /// Horizontal guide levels, e.g. RSI 70 / 30.
  final List<double> levels;

  /// A fixed value range for the indicator's pane (RSI is always 0–100);
  /// null fits the data.
  final (double, double)? fixedRange;

  const IndicatorResult({required this.lines, this.histogram, this.band, this.levels = const [], this.fixedRange});
}

/// A technical indicator for [CandlestickChart2D].
///
/// Overlays ([MovingAverageIndicator], [BollingerBandsIndicator],
/// [VwapIndicator]) draw on the price pane; oscillators ([RsiIndicator],
/// [MacdIndicator]) get their own pane below it. Call [compute] to get the
/// numbers yourself.
sealed class CandleIndicator {
  const CandleIndicator();

  /// Short name shown in the chart's legend, e.g. "EMA 20".
  String get label;

  /// Whether this indicator gets its own pane below the price pane.
  bool get separatePane;

  IndicatorResult compute(List<Candle> candles);
}

enum MovingAverageType { simple, exponential }

/// A simple (SMA) or exponential (EMA) moving average of closing prices.
class MovingAverageIndicator extends CandleIndicator {
  final int period;
  final MovingAverageType type;
  final Color color;

  const MovingAverageIndicator({
    this.period = 20,
    this.type = MovingAverageType.simple,
    this.color = const Color(0xFFFFB300),
  }) : assert(period > 0);

  @override
  String get label => '${type == MovingAverageType.simple ? 'SMA' : 'EMA'} $period';

  @override
  bool get separatePane => false;

  @override
  IndicatorResult compute(List<Candle> candles) {
    final closes = [for (final c in candles) c.close];
    final values = type == MovingAverageType.simple ? sma(closes, period) : ema(closes, period);
    return IndicatorResult(lines: [IndicatorLine(label, color, values)]);
  }
}

/// Bollinger Bands: an SMA with bands [multiplier] standard deviations
/// above and below.
class BollingerBandsIndicator extends CandleIndicator {
  final int period;
  final double multiplier;
  final Color color;

  const BollingerBandsIndicator({this.period = 20, this.multiplier = 2, this.color = const Color(0xFF42A5F5)})
      : assert(period > 1);

  @override
  String get label => 'BB $period ${_trim(multiplier)}';

  @override
  bool get separatePane => false;

  @override
  IndicatorResult compute(List<Candle> candles) {
    final b = bollinger([for (final c in candles) c.close], period, multiplier);
    return IndicatorResult(
      lines: [
        IndicatorLine('Upper', color, b.upper, width: 1),
        IndicatorLine('Basis', color.withValues(alpha: 0.7), b.middle, width: 1),
        IndicatorLine('Lower', color, b.lower, width: 1),
      ],
      band: (0, 2, color.withValues(alpha: 0.08)),
    );
  }
}

/// Volume-weighted average price, resetting at the start of each calendar
/// day (the usual intraday convention). Candles without volume are skipped.
class VwapIndicator extends CandleIndicator {
  final Color color;
  final bool resetDaily;

  const VwapIndicator({this.color = const Color(0xFFAB47BC), this.resetDaily = true});

  @override
  String get label => 'VWAP';

  @override
  bool get separatePane => false;

  @override
  IndicatorResult compute(List<Candle> candles) =>
      IndicatorResult(lines: [IndicatorLine(label, color, vwap(candles, resetDaily: resetDaily))]);
}

/// Relative Strength Index (Wilder's smoothing), 0–100, in its own pane.
class RsiIndicator extends CandleIndicator {
  final int period;
  final Color color;
  final double overbought;
  final double oversold;

  const RsiIndicator({
    this.period = 14,
    this.color = const Color(0xFF7E57C2),
    this.overbought = 70,
    this.oversold = 30,
  }) : assert(period > 0);

  @override
  String get label => 'RSI $period';

  @override
  bool get separatePane => true;

  @override
  IndicatorResult compute(List<Candle> candles) => IndicatorResult(
        lines: [IndicatorLine(label, color, rsi([for (final c in candles) c.close], period))],
        levels: [overbought, oversold],
        fixedRange: (0, 100),
      );
}

/// MACD: the gap between a fast and slow EMA, its signal-line EMA, and the
/// histogram of their difference, in its own pane.
class MacdIndicator extends CandleIndicator {
  final int fast;
  final int slow;
  final int signal;
  final Color macdColor;
  final Color signalColor;
  final Color positiveColor;
  final Color negativeColor;

  const MacdIndicator({
    this.fast = 12,
    this.slow = 26,
    this.signal = 9,
    this.macdColor = const Color(0xFF42A5F5),
    this.signalColor = const Color(0xFFFF7043),
    this.positiveColor = const Color(0xFF26A69A),
    this.negativeColor = const Color(0xFFEF5350),
  }) : assert(fast > 0 && slow > fast && signal > 0);

  @override
  String get label => 'MACD $fast $slow $signal';

  @override
  bool get separatePane => true;

  @override
  IndicatorResult compute(List<Candle> candles) {
    final m = macd([for (final c in candles) c.close], fast, slow, signal);
    return IndicatorResult(
      lines: [IndicatorLine('MACD', macdColor, m.macd), IndicatorLine('Signal', signalColor, m.signal)],
      histogram: IndicatorHistogram(
        m.histogram,
        positiveColor.withValues(alpha: 0.6),
        negativeColor.withValues(alpha: 0.6),
      ),
      levels: const [0],
    );
  }
}

String _trim(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

// ---------------------------------------------------------------------------
// The math. Each returns a list aligned with the input, null where undefined.
// ---------------------------------------------------------------------------

/// Simple moving average over [period] values.
List<double?> sma(List<double> values, int period) {
  final out = List<double?>.filled(values.length, null);
  double sum = 0;
  for (int i = 0; i < values.length; i++) {
    sum += values[i];
    if (i >= period) sum -= values[i - period];
    if (i >= period - 1) out[i] = sum / period;
  }
  return out;
}

/// Exponential moving average (α = 2 / (period + 1)), seeded with the SMA
/// of the first [period] values — the common charting-platform convention.
List<double?> ema(List<double> values, int period) => _emaFrom([for (final v in values) v], period);

List<double?> _emaFrom(List<double?> values, int period) {
  final out = List<double?>.filled(values.length, null);
  final alpha = 2 / (period + 1);
  double? prev;
  double seed = 0;
  int seen = 0;
  for (int i = 0; i < values.length; i++) {
    final v = values[i];
    if (v == null) continue;
    if (prev == null) {
      seed += v;
      seen++;
      if (seen == period) {
        prev = seed / period;
        out[i] = prev;
      }
    } else {
      prev = prev + alpha * (v - prev);
      out[i] = prev;
    }
  }
  return out;
}

/// Bollinger Bands: SMA ± [multiplier] × population standard deviation.
({List<double?> middle, List<double?> upper, List<double?> lower}) bollinger(List<double> values, int period, double multiplier) {
  final middle = sma(values, period);
  final upper = List<double?>.filled(values.length, null);
  final lower = List<double?>.filled(values.length, null);
  for (int i = period - 1; i < values.length; i++) {
    final m = middle[i]!;
    double variance = 0;
    for (int j = i - period + 1; j <= i; j++) {
      variance += (values[j] - m) * (values[j] - m);
    }
    final sd = math.sqrt(variance / period);
    upper[i] = m + multiplier * sd;
    lower[i] = m - multiplier * sd;
  }
  return (middle: middle, upper: upper, lower: lower);
}

/// RSI with Wilder's smoothing; the first value lands at index [period].
List<double?> rsi(List<double> closes, int period) {
  final out = List<double?>.filled(closes.length, null);
  if (closes.length <= period) return out;
  double gain = 0, loss = 0;
  for (int i = 1; i <= period; i++) {
    final change = closes[i] - closes[i - 1];
    change >= 0 ? gain += change : loss -= change;
  }
  gain /= period;
  loss /= period;
  double value(double g, double l) => l == 0 ? (g == 0 ? 50 : 100) : 100 - 100 / (1 + g / l);
  out[period] = value(gain, loss);
  for (int i = period + 1; i < closes.length; i++) {
    final change = closes[i] - closes[i - 1];
    gain = (gain * (period - 1) + math.max(change, 0)) / period;
    loss = (loss * (period - 1) + math.max(-change, 0)) / period;
    out[i] = value(gain, loss);
  }
  return out;
}

/// MACD line (fast EMA − slow EMA), its [signal]-period EMA, and their
/// difference.
({List<double?> macd, List<double?> signal, List<double?> histogram}) macd(
    List<double> closes, int fast, int slow, int signal) {
  final f = ema(closes, fast), s = ema(closes, slow);
  final line = [for (int i = 0; i < closes.length; i++) (f[i] == null || s[i] == null) ? null : f[i]! - s[i]!];
  final sig = _emaFrom(line, signal);
  final hist = [for (int i = 0; i < closes.length; i++) (line[i] == null || sig[i] == null) ? null : line[i]! - sig[i]!];
  return (macd: line, signal: sig, histogram: hist);
}

/// Volume-weighted average of the typical price (H+L+C)/3, accumulated
/// from the start of the data or (with [resetDaily]) of each calendar day.
List<double?> vwap(List<Candle> candles, {bool resetDaily = true}) {
  final out = List<double?>.filled(candles.length, null);
  double pv = 0, vol = 0;
  DateTime? day;
  for (int i = 0; i < candles.length; i++) {
    final c = candles[i];
    final d = DateTime(c.time.year, c.time.month, c.time.day);
    if (resetDaily && day != null && d != day) {
      pv = 0;
      vol = 0;
    }
    day = d;
    final v = c.volume ?? 0;
    pv += (c.high + c.low + c.close) / 3 * v;
    vol += v;
    if (vol > 0) out[i] = pv / vol;
  }
  return out;
}
