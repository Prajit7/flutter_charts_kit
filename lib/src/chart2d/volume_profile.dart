import 'dart:math' as math;
import 'dart:ui' show Color;
import 'candlestick_chart.dart' show Candle;

/// Settings for the volume profile drawn on a [CandlestickChart2D]: how
/// much volume traded at each price over the visible candles, as
/// horizontal bars docked to the right of the price pane.
///
/// ```dart
/// CandlestickChart2D(candles: candles, volumeProfile: const VolumeProfile())
/// ```
///
/// The busiest price is the **point of control** (POC); the band around it
/// holding [valueArea] of the volume is the **value area**.
class VolumeProfile {
  /// Number of price rows.
  final int bins;

  /// Share of volume in the value area (0.7 = 70%).
  final double valueArea;

  /// Width of the longest bar, as a fraction of the pane.
  final double width;

  /// Split each bar into up-candle and down-candle volume.
  final bool splitUpDown;
  final bool showPointOfControl;
  final bool showValueArea;

  /// Bar color when not split; defaults to the theme's crosshair color.
  final Color? color;

  const VolumeProfile({
    this.bins = 24,
    this.valueArea = 0.7,
    this.width = 0.28,
    this.splitUpDown = true,
    this.showPointOfControl = true,
    this.showValueArea = true,
    this.color,
  });

  @override
  bool operator ==(Object other) =>
      other is VolumeProfile &&
      other.bins == bins &&
      other.valueArea == valueArea &&
      other.width == width &&
      other.splitUpDown == splitUpDown &&
      other.showPointOfControl == showPointOfControl &&
      other.showValueArea == showValueArea &&
      other.color == color;

  @override
  int get hashCode => Object.hash(bins, valueArea, width, splitUpDown, showPointOfControl, showValueArea, color);
}

/// One price row of a volume profile.
class VolumeProfileBin {
  final double low;
  final double high;
  final double upVolume;
  final double downVolume;

  const VolumeProfileBin(this.low, this.high, this.upVolume, this.downVolume);

  double get volume => upVolume + downVolume;
}

/// A computed volume profile.
class VolumeProfileResult {
  final List<VolumeProfileBin> bins;

  /// Index of the busiest bin.
  final int pointOfControlIndex;

  /// Bins [valueAreaLowIndex]..[valueAreaHighIndex] hold the value area.
  final int valueAreaLowIndex;
  final int valueAreaHighIndex;

  const VolumeProfileResult(this.bins, this.pointOfControlIndex, this.valueAreaLowIndex, this.valueAreaHighIndex);

  double get maxVolume => bins.fold(0.0, (m, b) => math.max(m, b.volume));
  double get totalVolume => bins.fold(0.0, (s, b) => s + b.volume);

  /// Middle of the busiest bin.
  double get pointOfControl => (bins[pointOfControlIndex].low + bins[pointOfControlIndex].high) / 2;
  double get valueAreaLow => bins[valueAreaLowIndex].low;
  double get valueAreaHigh => bins[valueAreaHighIndex].high;

  /// Profiles candles [from]..[to] over prices [low]..[high] in [bins]
  /// rows. Each candle's volume is spread evenly over its high–low range.
  /// Returns null when there's no volume.
  static VolumeProfileResult? compute(
    List<Candle> candles, {
    int from = 0,
    int? to,
    double? low,
    double? high,
    int bins = 24,
    double valueArea = 0.7,
  }) {
    final last = math.min(candles.length - 1, to ?? candles.length - 1);
    if (last < from || bins < 1) return null;
    var lo = low ?? double.infinity, hi = high ?? -double.infinity;
    if (low == null || high == null) {
      for (int i = from; i <= last; i++) {
        if (low == null) lo = math.min(lo, candles[i].low);
        if (high == null) hi = math.max(hi, candles[i].high);
      }
    }
    if (!(hi > lo)) return null;
    final step = (hi - lo) / bins;
    final up = List.filled(bins, 0.0), down = List.filled(bins, 0.0);
    for (int i = from; i <= last; i++) {
      final c = candles[i];
      final v = c.volume ?? 0;
      if (v <= 0) continue;
      final target = c.isUp ? up : down;
      final range = c.high - c.low;
      if (range <= 0) {
        final b = ((c.close - lo) / step).floor();
        if (b >= 0 && b < bins) target[b] += v;
        continue;
      }
      final b0 = math.max(0, ((c.low - lo) / step).floor()), b1 = math.min(bins - 1, ((c.high - lo) / step).floor());
      for (int b = b0; b <= b1; b++) {
        final overlap = math.min(c.high, lo + (b + 1) * step) - math.max(c.low, lo + b * step);
        if (overlap > 0) target[b] += v * overlap / range;
      }
    }
    final list = [for (int b = 0; b < bins; b++) VolumeProfileBin(lo + b * step, lo + (b + 1) * step, up[b], down[b])];
    final total = list.fold(0.0, (s, b) => s + b.volume);
    if (total <= 0) return null;
    var poc = 0;
    for (int b = 1; b < bins; b++) {
      if (list[b].volume > list[poc].volume) poc = b;
    }
    // Grow the value area from the POC toward the busier neighbour.
    var a = poc, z = poc, inside = list[poc].volume;
    while (inside < total * valueArea && (a > 0 || z < bins - 1)) {
      final below = a > 0 ? list[a - 1].volume : -1.0, above = z < bins - 1 ? list[z + 1].volume : -1.0;
      if (above >= below) {
        z++;
        inside += above;
      } else {
        a--;
        inside += below;
      }
    }
    return VolumeProfileResult(list, poc, a, z);
  }
}
