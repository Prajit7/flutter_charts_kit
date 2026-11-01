import 'package:flutter/foundation.dart';
import 'candlestick_chart.dart' show Candle;

/// Builds candles from a live stream of trades/ticks, for
/// [CandlestickChart2D].
///
/// Each [addTick] updates the current candle's high/low/close (the last
/// traded price) and volume, or starts a new candle when the tick falls in
/// the next [interval]. Listeners are notified on every tick.
///
/// ```dart
/// final live = LiveCandles(interval: const Duration(minutes: 1), maxCandles: 300);
/// socket.listen((t) => live.addTick(t.time, t.price, volume: t.qty));
/// ...
/// ListenableBuilder(
///   listenable: live,
///   builder: (_, __) => CandlestickChart2D(
///     candles: live.candles,
///     lastPrice: live.lastPrice,
///     visibleCandles: 80,
///   ),
/// )
/// ```
class LiveCandles extends ChangeNotifier {
  /// Length of one candle. Intervals of a day or more align to local
  /// midnight; shorter ones to whole multiples since the epoch (so 5-minute
  /// candles start at :00, :05, …).
  final Duration interval;

  /// Oldest candles are dropped beyond this many. Null keeps everything.
  final int? maxCandles;

  final List<Candle> _candles = [];
  double? _lastPrice;
  double? _previousPrice;
  List<Candle>? _snapshot;

  LiveCandles({required this.interval, this.maxCandles, List<Candle> history = const []})
      : assert(interval > Duration.zero) {
    _candles.addAll(history);
    _trim();
    if (_candles.isNotEmpty) _lastPrice = _candles.last.close;
  }

  /// The candles so far, oldest first. A new list after every change, so
  /// charts (which compare by value) see each update.
  List<Candle> get candles => _snapshot ??= List.unmodifiable(_candles);

  /// The most recent traded price (LTP).
  double? get lastPrice => _lastPrice;

  /// The price before the last tick — compare with [lastPrice] for the
  /// tick direction.
  double? get previousPrice => _previousPrice;

  /// Start time of the candle containing [time].
  DateTime bucketStart(DateTime time) {
    if (interval >= const Duration(days: 1)) {
      final days = interval.inDays;
      // Count whole calendar days in UTC so DST shifts can't make a day 23h.
      final dayNumber = DateTime.utc(time.year, time.month, time.day).difference(DateTime.utc(1970)).inDays;
      return DateTime(time.year, time.month, time.day - dayNumber % days);
    }
    final ms = interval.inMilliseconds;
    final t = time.millisecondsSinceEpoch;
    return DateTime.fromMillisecondsSinceEpoch(t - t % ms);
  }

  /// Records a trade at [price]. Ticks older than the current candle are
  /// ignored (late or out-of-order data).
  void addTick(DateTime time, double price, {double volume = 0}) {
    final start = bucketStart(time);
    if (_candles.isNotEmpty && start.isBefore(_candles.last.time)) return;
    if (_candles.isEmpty || start.isAfter(_candles.last.time)) {
      _candles.add(Candle(time: start, open: price, high: price, low: price, close: price, volume: volume));
      _trim();
    } else {
      final c = _candles.last;
      _candles[_candles.length - 1] = Candle(
        time: c.time,
        open: c.open,
        high: price > c.high ? price : c.high,
        low: price < c.low ? price : c.low,
        close: price,
        volume: (c.volume ?? 0) + volume,
      );
    }
    _previousPrice = _lastPrice;
    _lastPrice = price;
    _snapshot = null;
    notifyListeners();
  }

  /// Replaces everything, e.g. with history loaded from an API.
  void reset([List<Candle> history = const []]) {
    _candles
      ..clear()
      ..addAll(history);
    _trim();
    _lastPrice = _candles.isEmpty ? null : _candles.last.close;
    _previousPrice = null;
    _snapshot = null;
    notifyListeners();
  }

  void _trim() {
    final max = maxCandles;
    if (max != null && _candles.length > max) _candles.removeRange(0, _candles.length - max);
  }
}
