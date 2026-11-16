import 'dart:math' as math;
import 'candlestick_chart.dart' show Candle;

/// How [CandlestickChart2D] builds its bars from the raw candles.
enum CandleType {
  /// The candles as given.
  standard,

  /// Heikin-Ashi: each bar averages the previous one, smoothing noise so
  /// trends read as runs of one color.
  heikinAshi,

  /// Renko: fixed-size bricks, a new one only when price moves a full box
  /// beyond the last brick — time is ignored, only movement counts.
  renko,

  /// Line break (three-line break by default): a new line when the close
  /// beats the last line; a reversal only when it beats the last few lines.
  lineBreak,
}

/// The transforms behind [CandleType], usable on their own (e.g. to feed
/// indicators or your own logic).
abstract final class CandleTransforms {
  /// Applies [type] with its settings.
  static List<Candle> apply(List<Candle> candles, CandleType type, {double? renkoBoxSize, int lineBreakCount = 3}) =>
      switch (type) {
        CandleType.standard => candles,
        CandleType.heikinAshi => heikinAshi(candles),
        CandleType.renko => renko(candles, boxSize: renkoBoxSize),
        CandleType.lineBreak => lineBreak(candles, lines: lineBreakCount),
      };

  /// Heikin-Ashi bars: close = (O+H+L+C)/4, open = midpoint of the previous
  /// bar's open and close, high/low stretched to include both.
  static List<Candle> heikinAshi(List<Candle> candles) {
    final out = <Candle>[];
    for (final c in candles) {
      final close = (c.open + c.high + c.low + c.close) / 4;
      final open = out.isEmpty ? (c.open + c.close) / 2 : (out.last.open + out.last.close) / 2;
      out.add(Candle(
        time: c.time,
        open: open,
        high: math.max(c.high, math.max(open, close)),
        low: math.min(c.low, math.min(open, close)),
        close: close,
        volume: c.volume,
      ));
    }
    return out;
  }

  /// Average true range over the last [period] candles (Wilder's
  /// smoothing), or null with fewer than two candles.
  static double? averageTrueRange(List<Candle> candles, {int period = 14}) {
    if (candles.length < 2) return null;
    double? atr;
    for (int i = 1; i < candles.length; i++) {
      final c = candles[i], prev = candles[i - 1].close;
      final tr = math.max(c.high - c.low, math.max((c.high - prev).abs(), (c.low - prev).abs()));
      atr = atr == null ? tr : (atr * (period - 1) + tr) / period;
    }
    return atr;
  }

  /// A "nice" box size near the ATR: 1, 2, 2.5 or 5 × a power of ten.
  static double defaultRenkoBox(List<Candle> candles) {
    final atr = averageTrueRange(candles) ?? (candles.isEmpty ? 1 : candles.last.close * 0.01);
    if (atr <= 0) return 1;
    final mag = math.pow(10, (math.log(atr) / math.ln10).floor()).toDouble();
    final n = atr / mag;
    return mag * (n < 1.5 ? 1 : n < 2.25 ? 2 : n < 3.75 ? 2.5 : n < 7.5 ? 5 : 10);
  }

  /// Renko bricks of [boxSize] (default: [defaultRenkoBox]) built from
  /// closes. Continuing a trend takes one box; reversing takes two (the
  /// brick has to clear the previous brick's far side). Each brick is
  /// stamped with the time of the candle that completed it, and carries
  /// an equal share of that candle's volume.
  static List<Candle> renko(List<Candle> candles, {double? boxSize}) {
    if (candles.isEmpty) return const [];
    final box = boxSize ?? defaultRenkoBox(candles);
    if (!(box > 0)) return candles;
    final out = <Candle>[];
    // The last brick's range; starts as a zero-height "brick" at the
    // first close, snapped to the box grid.
    var lo = (candles.first.close / box).round() * box, hi = lo;
    for (final c in candles) {
      final bricks = <(double, double)>[]; // (open, close)
      while (true) {
        if (c.close >= hi + box) {
          bricks.add((hi, hi + box));
          lo = hi;
          hi += box;
        } else if (c.close <= lo - box) {
          bricks.add((lo, lo - box));
          hi = lo;
          lo -= box;
        } else {
          break;
        }
      }
      final share = c.volume == null || bricks.isEmpty ? null : c.volume! / bricks.length;
      for (final (o, cl) in bricks) {
        out.add(Candle(time: c.time, open: o, high: math.max(o, cl), low: math.min(o, cl), close: cl, volume: share));
      }
    }
    return out;
  }

  /// Line-break chart: a new line when the close goes beyond the last
  /// line's close; a reversal line only when it goes beyond the extreme of
  /// the last [lines] lines.
  static List<Candle> lineBreak(List<Candle> candles, {int lines = 3}) {
    if (candles.isEmpty) return const [];
    final out = <Candle>[];
    final base = candles.first.close;
    double vol = 0;
    for (final c in candles) {
      vol += c.volume ?? 0;
      if (out.isEmpty) {
        if (c.close == base) continue;
        out.add(_line(c.time, base, c.close, vol));
        vol = 0;
        continue;
      }
      final last = out.last;
      final recent = out.sublist(math.max(0, out.length - lines));
      final up = last.close > last.open;
      if (up ? c.close > last.close : c.close < last.close) {
        out.add(_line(c.time, last.close, c.close, vol));
        vol = 0;
      } else if (up ? c.close < recent.map((l) => l.low).reduce(math.min) : c.close > recent.map((l) => l.high).reduce(math.max)) {
        // Reversal: starts from the last line's open.
        out.add(_line(c.time, last.open, c.close, vol));
        vol = 0;
      }
    }
    return out;
  }

  static Candle _line(DateTime t, double open, double close, double volume) => Candle(
        time: t,
        open: open,
        high: math.max(open, close),
        low: math.min(open, close),
        close: close,
        volume: volume == 0 ? null : volume,
      );
}
