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

/// Average True Range (Wilder's smoothing): how far price typically moves
/// per bar, in price units. Own pane.
class AtrIndicator extends CandleIndicator {
  final int period;
  final Color color;

  const AtrIndicator({this.period = 14, this.color = const Color(0xFFFF7043)}) : assert(period > 0);

  @override
  String get label => 'ATR $period';

  @override
  bool get separatePane => true;

  @override
  IndicatorResult compute(List<Candle> candles) => IndicatorResult(lines: [IndicatorLine(label, color, atr(candles, period))]);
}

/// Supertrend: an ATR trailing stop that flips sides when price closes
/// through it — green below price in an uptrend, red above in a downtrend.
class SupertrendIndicator extends CandleIndicator {
  final int period;
  final double multiplier;
  final Color upColor;
  final Color downColor;

  const SupertrendIndicator({
    this.period = 10,
    this.multiplier = 3,
    this.upColor = const Color(0xFF26A69A),
    this.downColor = const Color(0xFFEF5350),
  }) : assert(period > 0);

  @override
  String get label => 'Supertrend $period ${_trim(multiplier)}';

  @override
  bool get separatePane => false;

  @override
  IndicatorResult compute(List<Candle> candles) {
    final st = supertrend(candles, period, multiplier);
    // One line per direction (null on the other side), so each segment
    // takes its trend's color. Flips join the two at the flip bar.
    final up = List<double?>.filled(candles.length, null), down = List<double?>.filled(candles.length, null);
    for (int i = 0; i < candles.length; i++) {
      final v = st.line[i], d = st.up[i];
      if (v == null || d == null) continue;
      (d ? up : down)[i] = v;
      if (i > 0 && st.up[i - 1] != null && st.up[i - 1] != d) (d ? down : up)[i] = v;
    }
    return IndicatorResult(lines: [
      IndicatorLine('Up', upColor, up, width: 1.8),
      IndicatorLine('Down', downColor, down, width: 1.8),
    ]);
  }
}

/// Stochastic oscillator: where the close sits in the recent high–low
/// range (%K, smoothed) and its moving average (%D), 0–100. Own pane.
class StochasticIndicator extends CandleIndicator {
  final int period;
  final int smoothK;
  final int smoothD;
  final Color kColor;
  final Color dColor;
  final double overbought;
  final double oversold;

  const StochasticIndicator({
    this.period = 14,
    this.smoothK = 3,
    this.smoothD = 3,
    this.kColor = const Color(0xFF29B6F6),
    this.dColor = const Color(0xFFFFA726),
    this.overbought = 80,
    this.oversold = 20,
  }) : assert(period > 0 && smoothK > 0 && smoothD > 0);

  @override
  String get label => 'Stoch $period $smoothK $smoothD';

  @override
  bool get separatePane => true;

  @override
  IndicatorResult compute(List<Candle> candles) {
    final s = stochastic(candles, period, smoothK, smoothD);
    return IndicatorResult(
      lines: [IndicatorLine('%K', kColor, s.k), IndicatorLine('%D', dColor, s.d)],
      levels: [overbought, oversold],
      fixedRange: (0, 100),
    );
  }
}

/// Average Directional Index: trend strength (ADX, 0–100; above ~25 is a
/// trend) with the +DI/−DI direction lines. Own pane.
class AdxIndicator extends CandleIndicator {
  final int period;
  final Color adxColor;
  final Color plusColor;
  final Color minusColor;
  final double threshold;

  const AdxIndicator({
    this.period = 14,
    this.adxColor = const Color(0xFFFFCA28),
    this.plusColor = const Color(0xFF26A69A),
    this.minusColor = const Color(0xFFEF5350),
    this.threshold = 25,
  }) : assert(period > 0);

  @override
  String get label => 'ADX $period';

  @override
  bool get separatePane => true;

  @override
  IndicatorResult compute(List<Candle> candles) {
    final a = adx(candles, period);
    return IndicatorResult(
      lines: [
        IndicatorLine('ADX', adxColor, a.adx, width: 1.8),
        IndicatorLine('+DI', plusColor, a.plusDi, width: 1.1),
        IndicatorLine('−DI', minusColor, a.minusDi, width: 1.1),
      ],
      levels: [threshold],
      fixedRange: (0, 100),
    );
  }
}

/// Ichimoku cloud: conversion and base lines, the cloud (leading spans A
/// and B, shifted [displacement] bars forward) and the lagging span.
///
/// The cloud's forward part beyond the last candle isn't drawn — the chart
/// has no bars there yet.
class IchimokuIndicator extends CandleIndicator {
  final int conversion;
  final int base;
  final int spanB;
  final int displacement;
  final Color conversionColor;
  final Color baseColor;
  final Color spanAColor;
  final Color spanBColor;
  final Color laggingColor;

  const IchimokuIndicator({
    this.conversion = 9,
    this.base = 26,
    this.spanB = 52,
    this.displacement = 26,
    this.conversionColor = const Color(0xFF2962FF),
    this.baseColor = const Color(0xFFB71C1C),
    this.spanAColor = const Color(0xFF43A047),
    this.spanBColor = const Color(0xFFE53935),
    this.laggingColor = const Color(0xFF9C27B0),
  });

  @override
  String get label => 'Ichimoku $conversion $base $spanB';

  @override
  bool get separatePane => false;

  @override
  IndicatorResult compute(List<Candle> candles) {
    final r = ichimoku(candles, conversion: conversion, base: base, spanB: spanB, displacement: displacement);
    return IndicatorResult(
      lines: [
        IndicatorLine('Conversion', conversionColor, r.conversion, width: 1.1),
        IndicatorLine('Base', baseColor, r.base, width: 1.1),
        IndicatorLine('Span A', spanAColor, r.spanA, width: 0.9),
        IndicatorLine('Span B', spanBColor, r.spanB, width: 0.9),
        IndicatorLine('Lagging', laggingColor, r.lagging, width: 0.9),
      ],
      band: (2, 3, spanAColor.withValues(alpha: 0.12)),
    );
  }
}

/// The period [PivotPointsIndicator] takes its high/low/close from.
enum PivotPeriod { day, week, month }

/// Classic floor pivots: P = (H+L+C)/3 of the previous day/week/month,
/// with resistance R1–R3 and support S1–S3, drawn as steps that reset each
/// period.
class PivotPointsIndicator extends CandleIndicator {
  final PivotPeriod period;
  final Color pivotColor;
  final Color resistanceColor;
  final Color supportColor;

  const PivotPointsIndicator({
    this.period = PivotPeriod.day,
    this.pivotColor = const Color(0xFFFFB300),
    this.resistanceColor = const Color(0xFFEF5350),
    this.supportColor = const Color(0xFF26A69A),
  });

  @override
  String get label => 'Pivots ${switch (period) { PivotPeriod.day => 'D', PivotPeriod.week => 'W', PivotPeriod.month => 'M' }}';

  @override
  bool get separatePane => false;

  @override
  IndicatorResult compute(List<Candle> candles) {
    final p = pivotPoints(candles, period);
    return IndicatorResult(lines: [
      IndicatorLine('R3', resistanceColor.withValues(alpha: 0.5), p.r3, width: 0.9),
      IndicatorLine('R2', resistanceColor.withValues(alpha: 0.7), p.r2, width: 0.9),
      IndicatorLine('R1', resistanceColor, p.r1, width: 1),
      IndicatorLine('P', pivotColor, p.pivot, width: 1.3),
      IndicatorLine('S1', supportColor, p.s1, width: 1),
      IndicatorLine('S2', supportColor.withValues(alpha: 0.7), p.s2, width: 0.9),
      IndicatorLine('S3', supportColor.withValues(alpha: 0.5), p.s3, width: 0.9),
    ]);
  }
}

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

/// True range of each bar (the first bar uses its own high − low).
List<double> trueRange(List<Candle> candles) => [
      for (int i = 0; i < candles.length; i++)
        i == 0
            ? candles[i].high - candles[i].low
            : math.max(candles[i].high - candles[i].low,
                math.max((candles[i].high - candles[i - 1].close).abs(), (candles[i].low - candles[i - 1].close).abs())),
    ];

/// Wilder's smoothing (RMA) seeded with the SMA of the first [period]
/// values from [start].
List<double?> _wilder(List<double> values, int period, {int start = 0}) {
  final out = List<double?>.filled(values.length, null);
  if (values.length - start < period) return out;
  double avg = 0;
  for (int i = start; i < start + period; i++) {
    avg += values[i];
  }
  avg /= period;
  out[start + period - 1] = avg;
  for (int i = start + period; i < values.length; i++) {
    avg = (avg * (period - 1) + values[i]) / period;
    out[i] = avg;
  }
  return out;
}

/// Average True Range with Wilder's smoothing.
List<double?> atr(List<Candle> candles, int period) => _wilder(trueRange(candles), period);

/// Supertrend: the trailing band ([multiplier] × ATR from (H+L)/2) and its
/// direction (true = uptrend) per bar.
({List<double?> line, List<bool?> up}) supertrend(List<Candle> candles, int period, double multiplier) {
  final n = candles.length;
  final a = atr(candles, period);
  final line = List<double?>.filled(n, null);
  final up = List<bool?>.filled(n, null);
  double? finalUpper, finalLower;
  bool trendUp = true;
  for (int i = 0; i < n; i++) {
    final v = a[i];
    if (v == null) continue;
    final c = candles[i];
    final mid = (c.high + c.low) / 2;
    final basicUpper = mid + multiplier * v, basicLower = mid - multiplier * v;
    final prevClose = i > 0 ? candles[i - 1].close : c.close;
    // Bands only tighten while price stays on their side.
    finalUpper = finalUpper == null || basicUpper < finalUpper || prevClose > finalUpper ? basicUpper : finalUpper;
    finalLower = finalLower == null || basicLower > finalLower || prevClose < finalLower ? basicLower : finalLower;
    if (up[i - 1 < 0 ? 0 : i - 1] == null) {
      trendUp = c.close >= mid;
    } else if (trendUp && c.close < finalLower) {
      trendUp = false;
    } else if (!trendUp && c.close > finalUpper) {
      trendUp = true;
    }
    up[i] = trendUp;
    line[i] = trendUp ? finalLower : finalUpper;
  }
  return (line: line, up: up);
}

/// Stochastic %K (smoothed over [smoothK]) and %D ([smoothD]-period SMA of %K).
({List<double?> k, List<double?> d}) stochastic(List<Candle> candles, int period, int smoothK, int smoothD) {
  final n = candles.length;
  final raw = List<double?>.filled(n, null);
  for (int i = period - 1; i < n; i++) {
    var hi = -double.infinity, lo = double.infinity;
    for (int j = i - period + 1; j <= i; j++) {
      hi = math.max(hi, candles[j].high);
      lo = math.min(lo, candles[j].low);
    }
    raw[i] = hi == lo ? 50 : (candles[i].close - lo) / (hi - lo) * 100;
  }
  List<double?> smooth(List<double?> v, int p) {
    final out = List<double?>.filled(v.length, null);
    for (int i = 0; i < v.length; i++) {
      if (i < p - 1) continue;
      var sum = 0.0;
      var ok = true;
      for (int j = i - p + 1; j <= i; j++) {
        if (v[j] == null) {
          ok = false;
          break;
        }
        sum += v[j]!;
      }
      if (ok) out[i] = sum / p;
    }
    return out;
  }

  final k = smooth(raw, smoothK);
  return (k: k, d: smooth(k, smoothD));
}

/// ADX with +DI and −DI (Wilder).
({List<double?> adx, List<double?> plusDi, List<double?> minusDi}) adx(List<Candle> candles, int period) {
  final n = candles.length;
  final plusDm = List<double>.filled(n, 0), minusDm = List<double>.filled(n, 0);
  for (int i = 1; i < n; i++) {
    final upMove = candles[i].high - candles[i - 1].high, downMove = candles[i - 1].low - candles[i].low;
    plusDm[i] = upMove > downMove && upMove > 0 ? upMove : 0;
    minusDm[i] = downMove > upMove && downMove > 0 ? downMove : 0;
  }
  final tr = trueRange(candles);
  final atrS = _wilder(tr, period, start: 1), plusS = _wilder(plusDm, period, start: 1), minusS = _wilder(minusDm, period, start: 1);
  final plusDi = List<double?>.filled(n, null), minusDi = List<double?>.filled(n, null);
  final dx = List<double>.filled(n, 0);
  int firstDx = -1;
  for (int i = 0; i < n; i++) {
    final t = atrS[i];
    if (t == null || t == 0) continue;
    plusDi[i] = plusS[i]! / t * 100;
    minusDi[i] = minusS[i]! / t * 100;
    final sum = plusDi[i]! + minusDi[i]!;
    dx[i] = sum == 0 ? 0 : (plusDi[i]! - minusDi[i]!).abs() / sum * 100;
    if (firstDx < 0) firstDx = i;
  }
  final adxLine = firstDx < 0 ? List<double?>.filled(n, null) : _wilder(dx, period, start: firstDx);
  return (adx: adxLine, plusDi: plusDi, minusDi: minusDi);
}

/// Ichimoku lines aligned with the candles: spans A/B are shifted
/// [displacement] bars forward and the lagging span that many back.
({List<double?> conversion, List<double?> base, List<double?> spanA, List<double?> spanB, List<double?> lagging}) ichimoku(
  List<Candle> candles, {
  int conversion = 9,
  int base = 26,
  int spanB = 52,
  int displacement = 26,
}) {
  final n = candles.length;
  List<double?> mid(int p) => [
        for (int i = 0; i < n; i++)
          i < p - 1
              ? null
              : (candles.sublist(i - p + 1, i + 1).map((c) => c.high).reduce(math.max) +
                      candles.sublist(i - p + 1, i + 1).map((c) => c.low).reduce(math.min)) /
                  2,
      ];
  final conv = mid(conversion), bas = mid(base), b = mid(spanB);
  final a = [for (int i = 0; i < n; i++) conv[i] == null || bas[i] == null ? null : (conv[i]! + bas[i]!) / 2];
  List<double?> shift(List<double?> v, int by) => [
        for (int i = 0; i < n; i++) (i - by >= 0 && i - by < n) ? v[i - by] : null,
      ];
  return (
    conversion: conv,
    base: bas,
    spanA: shift(a, displacement),
    spanB: shift(b, displacement),
    lagging: shift([for (final c in candles) c.close], -displacement),
  );
}

/// Classic pivots from the previous [period]'s high, low and close; null
/// during the first period (nothing before it).
({List<double?> pivot, List<double?> r1, List<double?> r2, List<double?> r3, List<double?> s1, List<double?> s2, List<double?> s3})
    pivotPoints(List<Candle> candles, PivotPeriod period) {
  final n = candles.length;
  int key(DateTime t) => switch (period) {
        PivotPeriod.day => t.year * 10000 + t.month * 100 + t.day,
        PivotPeriod.week => DateTime.utc(t.year, t.month, t.day).difference(DateTime.utc(1970, 1, 5)).inDays ~/ 7,
        PivotPeriod.month => t.year * 12 + t.month,
      };
  final out = [for (int k = 0; k < 7; k++) List<double?>.filled(n, null)];
  int? currentKey;
  double hi = -double.infinity, lo = double.infinity, close = 0;
  List<double>? levels;
  for (int i = 0; i < n; i++) {
    final c = candles[i];
    final k = key(c.time);
    if (currentKey != null && k != currentKey) {
      final p = (hi + lo + close) / 3;
      levels = [p, 2 * p - lo, p + (hi - lo), hi + 2 * (p - lo), 2 * p - hi, p - (hi - lo), lo - 2 * (hi - p)];
      hi = -double.infinity;
      lo = double.infinity;
    }
    currentKey = k;
    hi = math.max(hi, c.high);
    lo = math.min(lo, c.low);
    close = c.close;
    if (levels != null) {
      for (int j = 0; j < 7; j++) {
        out[j][i] = levels[j];
      }
    }
  }
  return (pivot: out[0], r1: out[1], r2: out[2], r3: out[3], s1: out[4], s2: out[5], s3: out[6]);
}
