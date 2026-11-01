/// Calendar-aware tick generation for time x-axes, where x values are
/// `DateTime.millisecondsSinceEpoch` (see `ChartPoint.at`).
///
/// Picks the smallest "natural" interval — 1s, 5s, …, 1h, 6h, 1d, 1w, 1mo,
/// 3mo, 1y, … — that yields at most `maxTicks` ticks, then aligns ticks to
/// calendar boundaries (midnight, the 1st of the month, 1 January) in local
/// time, and labels them at a matching granularity.
library;

enum _Unit { second, minute, hour, day, month, year }

class _Interval {
  final _Unit unit;
  final int step;
  const _Interval(this.unit, this.step);

  /// Rough length in ms, used only to pick an interval.
  int get approxMs => step * switch (unit) {
        _Unit.second => 1000,
        _Unit.minute => 60 * 1000,
        _Unit.hour => 3600 * 1000,
        _Unit.day => 86400 * 1000,
        _Unit.month => 30 * 86400 * 1000,
        _Unit.year => 365 * 86400 * 1000,
      };
}

const _intervals = [
  _Interval(_Unit.second, 1),
  _Interval(_Unit.second, 5),
  _Interval(_Unit.second, 15),
  _Interval(_Unit.second, 30),
  _Interval(_Unit.minute, 1),
  _Interval(_Unit.minute, 5),
  _Interval(_Unit.minute, 15),
  _Interval(_Unit.minute, 30),
  _Interval(_Unit.hour, 1),
  _Interval(_Unit.hour, 3),
  _Interval(_Unit.hour, 6),
  _Interval(_Unit.hour, 12),
  _Interval(_Unit.day, 1),
  _Interval(_Unit.day, 2),
  _Interval(_Unit.day, 7),
  _Interval(_Unit.month, 1),
  _Interval(_Unit.month, 3),
  _Interval(_Unit.month, 6),
  _Interval(_Unit.year, 1),
  _Interval(_Unit.year, 2),
  _Interval(_Unit.year, 5),
  _Interval(_Unit.year, 10),
  _Interval(_Unit.year, 25),
  _Interval(_Unit.year, 50),
  _Interval(_Unit.year, 100),
];

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _two(int n) => n.toString().padLeft(2, '0');

/// Time ticks between [minMs] and [maxMs] as `(x, label)` pairs.
List<(double, String)> timeTicks(double minMs, double maxMs, {int maxTicks = 6}) {
  if (!(maxMs > minMs)) {
    final t = DateTime.fromMillisecondsSinceEpoch(minMs.round());
    return [(minMs, formatTime(t))];
  }
  final span = maxMs - minMs;
  var index = _intervals.indexWhere((i) => span / i.approxMs <= maxTicks);
  if (index < 0) index = _intervals.length - 1;

  var ticks = _ticksAt(minMs, maxMs, _intervals[index]);
  // A coarse interval can leave just one or two ticks (e.g. 7 weeks of data
  // with room for 6 ticks jumps to monthly). Step down one interval then —
  // callers thin labels that would overlap, so the extra ticks are safe.
  if (ticks.length < 3 && index > 0) ticks = _ticksAt(minMs, maxMs, _intervals[index - 1]);
  return ticks;
}

List<(double, String)> _ticksAt(double minMs, double maxMs, _Interval interval) {
  final ticks = <(double, String)>[];
  var t = _alignUp(DateTime.fromMillisecondsSinceEpoch(minMs.floor()), interval);
  // Guard against pathological inputs producing an endless loop.
  for (int guard = 0; guard < 1000 && t.millisecondsSinceEpoch <= maxMs; guard++) {
    ticks.add((t.millisecondsSinceEpoch.toDouble(), _label(t, interval.unit)));
    t = _advance(t, interval);
  }
  return ticks;
}

/// A full, human-readable timestamp for tooltips, dropping the time of day
/// when it's exactly midnight.
String formatTime(DateTime t) {
  final date = '${t.day} ${_months[t.month - 1]} ${t.year}';
  if (t.hour == 0 && t.minute == 0 && t.second == 0) return date;
  final time = t.second == 0 ? '${_two(t.hour)}:${_two(t.minute)}' : '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
  return '$date $time';
}

String _label(DateTime t, _Unit unit) => switch (unit) {
      _Unit.second => '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}',
      _Unit.minute || _Unit.hour =>
        t.hour == 0 && t.minute == 0 ? '${t.day} ${_months[t.month - 1]}' : '${_two(t.hour)}:${_two(t.minute)}',
      _Unit.day => '${t.day} ${_months[t.month - 1]}',
      _Unit.month => t.month == 1 ? '${t.year}' : _months[t.month - 1],
      _Unit.year => '${t.year}',
    };

/// The first tick at or after [t] that sits on an [interval] boundary.
DateTime _alignUp(DateTime t, _Interval interval) {
  final step = interval.step;
  DateTime floor;
  switch (interval.unit) {
    case _Unit.second:
      floor = DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second - t.second % step);
    case _Unit.minute:
      floor = DateTime(t.year, t.month, t.day, t.hour, t.minute - t.minute % step);
    case _Unit.hour:
      floor = DateTime(t.year, t.month, t.day, t.hour - t.hour % step);
    case _Unit.day:
      // Weekly ticks land on Mondays; other day steps on midnights.
      final day = DateTime(t.year, t.month, t.day);
      floor = step == 7 ? DateTime(day.year, day.month, day.day - (day.weekday - DateTime.monday)) : day;
    case _Unit.month:
      floor = DateTime(t.year, t.month - (t.month - 1) % step);
    case _Unit.year:
      floor = DateTime(t.year - t.year % step);
  }
  return floor.isBefore(t) ? _advance(floor, interval) : floor;
}

/// Calendar arithmetic (not fixed milliseconds), so ticks stay on
/// boundaries across month lengths and daylight-saving changes.
DateTime _advance(DateTime t, _Interval interval) {
  final s = interval.step;
  return switch (interval.unit) {
    _Unit.second => DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second + s),
    _Unit.minute => DateTime(t.year, t.month, t.day, t.hour, t.minute + s),
    _Unit.hour => DateTime(t.year, t.month, t.day, t.hour + s),
    _Unit.day => DateTime(t.year, t.month, t.day + s),
    _Unit.month => DateTime(t.year, t.month + s),
    _Unit.year => DateTime(t.year + s),
  };
}
