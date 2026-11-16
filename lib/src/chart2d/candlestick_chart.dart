import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'svg_export.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'cartesian_axes.dart';
import 'theme.dart';
import 'chart_chrome.dart';
import 'common.dart';
import 'controller.dart';
import 'indicators.dart';
import 'reference.dart';
import 'candle_types.dart';
import 'chart_drawings.dart';
import 'volume_profile.dart';
import 'crosshair_sync.dart';
import 'time_axis.dart' show formatTime;

/// One period of price data (a day, an hour, …).
class Candle {
  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double? volume;

  const Candle({required this.time, required this.open, required this.high, required this.low, required this.close, this.volume});

  bool get isUp => close >= open;

  @override
  bool operator ==(Object other) =>
      other is Candle &&
      other.time == time &&
      other.open == open &&
      other.high == high &&
      other.low == low &&
      other.close == close &&
      other.volume == volume;

  @override
  int get hashCode => Object.hash(time, open, high, low, close, volume);
}

/// How [CandlestickChart2D] draws each period.
enum CandleStyle {
  /// Filled body between open and close, with high/low wicks.
  candle,

  /// A vertical high–low bar with an open tick left and a close tick right.
  ohlc,
}

/// A trading chart: candlesticks or OHLC bars with optional volume,
/// technical indicators and a live last-traded-price marker.
///
/// ```dart
/// CandlestickChart2D(
///   title: 'ACME',
///   candles: candles,
///   showVolume: true,
///   indicators: const [
///     MovingAverageIndicator(period: 20),
///     BollingerBandsIndicator(),
///     RsiIndicator(),
///     MacdIndicator(),
///   ],
/// )
/// ```
///
/// Candles are spaced evenly by index, as on trading platforms — nights,
/// weekends and holidays without trades leave no gaps. Overlay indicators
/// draw on the price pane; RSI and MACD get their own panes. For live data,
/// update [candles] (see [LiveCandles]) and [lastPrice]: zoom and hover
/// survive updates, and the price tag flashes on each tick.
///
/// Uses a dark trading theme ([ChartTheme.trading]) unless [theme] is set
/// or a [ChartThemeScope] is above it.
///
/// Navigation works like trading apps: drag to scroll back and forth
/// through history (a quick swipe keeps gliding), pinch to zoom around your
/// fingers, and long-press to move the crosshair on touch screens. With a
/// mouse, the wheel zooms around the pointer and Shift+wheel (or a
/// horizontal trackpad swipe) scrolls. While the newest candle is in view,
/// the chart keeps following new candles at the user's zoom level.
class CandlestickChart2D extends StatefulWidget {
  final List<Candle> candles;
  final CandleStyle style;
  final Color upColor;
  final Color downColor;

  /// Volume bars along the bottom of the price pane (needs [Candle.volume]).
  final bool showVolume;

  /// Technical indicators: overlays on the price pane, oscillators in their
  /// own panes below.
  final List<CandleIndicator> indicators;

  /// Show an eye button on each indicator's legend row that hides/shows it.
  /// A hidden overlay stops drawing and no longer stretches the price
  /// scale; a hidden oscillator keeps its (empty) pane so the layout
  /// doesn't jump.
  final bool showIndicatorToggles;

  /// Called when the user hides or shows an indicator with its eye button.
  final void Function(CandleIndicator indicator, bool visible)? onIndicatorVisibilityChanged;

  /// The latest traded price (LTP). Defaults to the last candle's close.
  final double? lastPrice;

  /// Draw the last-price line and its tag on the price axis.
  final bool showLastPrice;

  /// Show only the latest N candles (and keep following new ones) until the
  /// user zooms. Null shows everything.
  final int? visibleCandles;

  /// Empty space to the right of the last candle, in candle widths — room
  /// for the next candle and the price tag.
  final double rightPadding;

  final String? title;
  final String? subtitle;
  final String emptyStateMessage;
  final String Function(double value) priceFormatter;
  final String Function(double value) volumeFormatter;

  /// Formats the time shown in the crosshair tag; defaults to a date/time.
  final String Function(DateTime time)? timeFormatter;
  final bool showGrid;
  final bool showCrosshair;

  /// Overrides the theme. By default the nearest [ChartThemeScope] is used,
  /// or [ChartTheme.trading] when there is none.
  final ChartTheme? theme;

  /// Price-axis marker lines and bands (support/resistance, targets).
  /// `ChartReferenceLine.time` / `ChartReferenceBand.time` mark dates.
  final List<ChartReferenceLine> referenceLines;
  final List<ChartReferenceBand> referenceBands;

  /// Callouts on the price pane: `x` is a time (see [ChartAnnotation.at]),
  /// `y` a price.
  final List<ChartAnnotation> annotations;

  /// Pinch (or mouse wheel) to zoom around the fingers/pointer.
  final bool enableZoom;

  /// Drag (or swipe, with momentum) to scroll through history.
  final bool enablePan;
  final bool enableAnimation;
  final Duration animationDuration;

  /// Shows a floating card for the hovered candle. By default the hovered
  /// candle's O/H/L/C appear in the header line instead, which never
  /// covers the chart.
  final Widget Function(BuildContext context, Candle candle)? tooltipBuilder;

  /// Reset zoom or export an image from outside the chart.
  final ChartController? controller;

  /// Links this chart's crosshair with other charts sharing the same sync
  /// (the shared x is time in milliseconds since epoch, so it pairs with
  /// time-axis line charts and other candlestick charts).
  final ChartCrosshairSync? crosshairSync;

  final ValueChanged<Candle?>? onCandleHover;
  final ValueChanged<Candle>? onCandleTap;

  /// How bars are built from [candles]: as given, Heikin-Ashi, Renko or
  /// line break. Indicators, volume and the O/H/L/C header follow the
  /// transformed bars; the last-price tag keeps the real last price.
  final CandleType candleType;

  /// Renko brick size; defaults to a round number near the 14-period ATR.
  final double? renkoBoxSize;

  /// Lines a line-break reversal has to clear (3 = three-line break).
  final int lineBreakCount;

  /// Volume-at-price bars over the visible candles, with point of control
  /// and value area.
  final VolumeProfile? volumeProfile;

  /// Enables drawing tools (trendlines, levels, Fibonacci, boxes) — see
  /// [ChartDrawingController].
  final ChartDrawingController? drawingController;

  const CandlestickChart2D({
    super.key,
    required this.candles,
    this.style = CandleStyle.candle,
    this.upColor = const Color(0xFF26A69A),
    this.downColor = const Color(0xFFEF5350),
    this.showVolume = false,
    this.indicators = const [],
    this.showIndicatorToggles = true,
    this.onIndicatorVisibilityChanged,
    this.lastPrice,
    this.showLastPrice = true,
    this.visibleCandles,
    this.rightPadding = 3,
    this.title,
    this.subtitle,
    this.emptyStateMessage = 'No data to display',
    this.priceFormatter = _price,
    this.volumeFormatter = _compact,
    this.timeFormatter,
    this.showGrid = true,
    this.showCrosshair = true,
    this.theme,
    this.referenceLines = const [],
    this.referenceBands = const [],
    this.annotations = const [],
    this.enableZoom = true,
    this.enablePan = true,
    this.enableAnimation = true,
    this.animationDuration = const Duration(milliseconds: 600),
    this.tooltipBuilder,
    this.controller,
    this.crosshairSync,
    this.onCandleHover,
    this.onCandleTap,
    this.candleType = CandleType.standard,
    this.renkoBoxSize,
    this.lineBreakCount = 3,
    this.volumeProfile,
    this.drawingController,
  });

  static String _price(double v) => v.abs() >= 1000 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  static String _compact(double v) {
    final a = v.abs();
    if (a >= 1e9) return '${Cartesian2DAxes.formatNumber(double.parse((v / 1e9).toStringAsFixed(2)))}B';
    if (a >= 1e6) return '${Cartesian2DAxes.formatNumber(double.parse((v / 1e6).toStringAsFixed(2)))}M';
    if (a >= 1e3) return '${Cartesian2DAxes.formatNumber(double.parse((v / 1e3).toStringAsFixed(1)))}k';
    return Cartesian2DAxes.formatNumber(v);
  }

  @override
  State<CandlestickChart2D> createState() => _CandlestickChart2DState();
}

/// One computed indicator plus where it draws.
class _Study {
  final CandleIndicator indicator;
  final IndicatorResult result;

  /// Position in [CandlestickChart2D.indicators].
  final int index;

  /// Toggled off with its legend's eye button.
  final bool hidden;

  _Study(this.indicator, this.result, {this.index = 0, this.hidden = false});
}

/// A horizontal slice of the chart with its own value scale.
class _Pane {
  final Rect rect;
  final double minY;
  final double maxY;
  final _Study? study; // null = the price pane

  _Pane(this.rect, this.minY, this.maxY, this.study);

  double y(double v) => maxY == minY ? rect.center.dy : rect.bottom - (v - minY) / (maxY - minY) * rect.height;
  double valueAt(double screenY) => minY + (rect.bottom - screenY) / rect.height * (maxY - minY);
}

const double _axisWidth = 64;
const double _timeAxisHeight = 22;

/// Every position the painters and hit-testing need, for one size and view.
class _CandleLayout {
  final List<Candle> candles;
  final Rect area; // all panes, excluding the price and time axes
  final double lo; // index at the left edge
  final double hi; // index at the right edge
  final _Pane price;
  final List<_Pane> oscillators;
  final List<_Study> overlays;
  final double maxVolume;
  final Rect? volumeRect;

  _CandleLayout._(this.candles, this.area, this.lo, this.hi, this.price, this.oscillators, this.overlays, this.maxVolume,
      this.volumeRect);

  factory _CandleLayout(Size size, List<Candle> candles, (double, double) view, List<_Study> studies, bool showVolume,
      double? lastPrice) {
    final (lo, hi) = view;
    final area = Rect.fromLTRB(4, 4, math.max(5, size.width - _axisWidth), math.max(5, size.height - _timeAxisHeight));
    final from = math.max(0, (lo + 0.5).ceil()), to = math.min(candles.length - 1, (hi - 0.5).floor());
    final overlays = [for (final s in studies) if (!s.indicator.separatePane) s];
    final panesBelow = [for (final s in studies) if (s.indicator.separatePane) s];

    // The price pane gets three shares of the height, each oscillator one.
    const gap = 8.0;
    final shares = 3 + panesBelow.length;
    final unit = (area.height - gap * panesBelow.length) / shares;
    final priceRect = Rect.fromLTWH(area.left, area.top, area.width, unit * 3);

    double lowest = double.infinity, highest = -double.infinity, maxVolume = 0;
    for (int i = from; i <= to; i++) {
      lowest = math.min(lowest, candles[i].low);
      highest = math.max(highest, candles[i].high);
      maxVolume = math.max(maxVolume, candles[i].volume ?? 0);
      for (final s in overlays) {
        if (s.hidden) continue;
        for (final line in s.result.lines) {
          final v = line.values[i];
          if (v == null) continue;
          lowest = math.min(lowest, v);
          highest = math.max(highest, v);
        }
      }
    }
    // Keep the live price in view while the latest candle is.
    if (lastPrice != null && to == candles.length - 1) {
      lowest = math.min(lowest, lastPrice);
      highest = math.max(highest, lastPrice);
    }
    if (!lowest.isFinite) {
      lowest = 0;
      highest = 1;
    }
    final pad = (highest - lowest) * 0.08 + (highest == lowest ? 1 : 0);
    final price = _Pane(priceRect, lowest - pad, highest + pad, null);

    final oscillators = <_Pane>[];
    double top = priceRect.bottom + gap;
    for (final s in panesBelow) {
      final rect = Rect.fromLTWH(area.left, top, area.width, unit);
      top += unit + gap;
      double a, b;
      if (s.result.fixedRange != null) {
        (a, b) = s.result.fixedRange!;
      } else {
        a = double.infinity;
        b = -double.infinity;
        for (int i = from; i <= to; i++) {
          for (final v in [...s.result.lines.map((l) => l.values[i]), s.result.histogram?.values[i]]) {
            if (v == null) continue;
            a = math.min(a, v);
            b = math.max(b, v);
          }
        }
        if (s.result.histogram != null) {
          a = math.min(a, 0);
          b = math.max(b, 0);
        }
        if (!a.isFinite) {
          a = -1;
          b = 1;
        }
        final p = (b - a) * 0.1 + (a == b ? 1 : 0);
        a -= p;
        b += p;
      }
      oscillators.add(_Pane(rect, a, b, s));
    }

    final volumeRect = showVolume && maxVolume > 0
        ? Rect.fromLTRB(priceRect.left, priceRect.bottom - priceRect.height * 0.2, priceRect.right, priceRect.bottom)
        : null;
    return _CandleLayout._(candles, area, lo, hi, price, oscillators, overlays, maxVolume, volumeRect);
  }

  double get slot => area.width / (hi - lo);
  double get candleWidth => math.max(1.0, slot * 0.7);
  double x(num index) => area.left + (index - lo) / (hi - lo) * area.width;
  double indexAt(double screenX) => lo + (screenX - area.left) / area.width * (hi - lo);

  int get firstVisible => math.max(0, (lo + 0.5).ceil());
  int get lastVisible => math.min(candles.length - 1, (hi - 0.5).floor());

  /// The candle under screen x, if the pointer is over the panes.
  int? indexUnder(Offset pos) {
    if (!area.contains(pos) || candles.isEmpty) return null;
    final i = indexAt(pos.dx).round();
    if (i < firstVisible || i > lastVisible) return null;
    return i;
  }

  /// The pane containing [pos], if any.
  _Pane? paneAt(Offset pos) {
    for (final p in [price, ...oscillators]) {
      if (p.rect.contains(pos)) return p;
    }
    return null;
  }

  /// Converts a time (ms since epoch) to a fractional candle index, for
  /// time-based reference lines.
  double indexOfTime(double ms) {
    if (candles.isEmpty) return 0;
    int lo = 0, hi = candles.length - 1;
    if (ms <= candles.first.time.millisecondsSinceEpoch) return 0;
    if (ms >= candles.last.time.millisecondsSinceEpoch) return hi.toDouble();
    while (hi - lo > 1) {
      final mid = (lo + hi) ~/ 2;
      candles[mid].time.millisecondsSinceEpoch <= ms ? lo = mid : hi = mid;
    }
    final a = candles[lo].time.millisecondsSinceEpoch, b = candles[hi].time.millisecondsSinceEpoch;
    return b == a ? lo.toDouble() : lo + (ms - a) / (b - a);
  }

  /// Time between candles at the start/end of the data, for positions
  /// beyond either end (drawings can extend into the future).
  double _edgeStep(bool end) {
    if (candles.length < 2) return 60000;
    final n = candles.length;
    final d = end
        ? candles[n - 1].time.millisecondsSinceEpoch - candles[n - 2].time.millisecondsSinceEpoch
        : candles[1].time.millisecondsSinceEpoch - candles[0].time.millisecondsSinceEpoch;
    return d > 0 ? d.toDouble() : 60000;
  }

  /// [indexOfTime], extrapolated past either end of the data.
  double indexOfTimeExtended(double ms) {
    if (candles.isEmpty) return 0;
    final first = candles.first.time.millisecondsSinceEpoch, last = candles.last.time.millisecondsSinceEpoch;
    if (ms < first) return (ms - first) / _edgeStep(false);
    if (ms > last) return candles.length - 1 + (ms - last) / _edgeStep(true);
    return indexOfTime(ms);
  }

  /// The time (ms) at a fractional candle index — the inverse of
  /// [indexOfTimeExtended].
  double timeAtIndex(double i) {
    if (candles.isEmpty) return 0;
    final n = candles.length;
    if (i <= 0) return candles.first.time.millisecondsSinceEpoch + i * _edgeStep(false);
    if (i >= n - 1) return candles.last.time.millisecondsSinceEpoch + (i - (n - 1)) * _edgeStep(true);
    final a = i.floor(), t = i - a;
    final ta = candles[a].time.millisecondsSinceEpoch, tb = candles[a + 1].time.millisecondsSinceEpoch;
    return ta + (tb - ta) * t;
  }
}

/// Calendar-aware tick marks for evenly spaced candles: picks the finest of
/// minute … year boundaries that yields at most [maxTicks] labels.
List<(int, String)> _timeTicks(List<Candle> candles, int from, int to, int maxTicks) {
  if (to <= from) return const [];
  int day(DateTime t) => DateTime.utc(t.year, t.month, t.day).difference(DateTime.utc(1970)).inDays;
  final keys = <int Function(DateTime)>[
    for (final m in [1, 5, 15, 30]) (t) => (day(t) * 24 + t.hour) * 60 ~/ m + t.minute ~/ m,
    for (final h in [1, 3, 6, 12]) (t) => day(t) * 24 ~/ h + t.hour ~/ h,
    day,
    (t) => (day(t) + 3) ~/ 7, // ISO weeks (1970-01-01 was a Thursday)
    (t) => t.year * 12 + t.month - 1,
    (t) => t.year * 4 + (t.month - 1) ~/ 3,
    (t) => t.year,
  ];
  List<int> boundaries(int Function(DateTime) key) => [
        for (int i = from + 1; i <= to; i++)
          if (key(candles[i].time) != key(candles[i - 1].time)) i,
      ];

  var chosen = boundaries(keys.last);
  for (final key in keys) {
    final b = boundaries(key);
    if (b.isNotEmpty && b.length <= maxTicks) {
      chosen = b;
      break;
    }
  }
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String two(int n) => n.toString().padLeft(2, '0');
  return [
    for (final i in chosen)
      (
        i,
        switch ((candles[i].time, candles[i - 1].time)) {
          (final t, final p) when t.year != p.year => '${t.year}',
          (final t, final p) when t.month != p.month && day(t) - day(p) <= 31 && chosen.length > 1 && _daily(candles) =>
            months[t.month - 1],
          (final t, final p) when day(t) != day(p) => '${t.day} ${months[t.month - 1]}',
          (final t, _) => '${two(t.hour)}:${two(t.minute)}',
        },
      ),
  ];
}

/// Whether candles are a day or longer apart (so month changes read better
/// as month names than as dates).
bool _daily(List<Candle> candles) =>
    candles.length < 2 || candles[1].time.difference(candles[0].time) >= const Duration(hours: 20);

typedef _Hover = (int index, Offset pointer);

class _CandlestickChart2DState extends State<CandlestickChart2D>
    with TickerProviderStateMixin, ChartControllerMixin<CandlestickChart2D> {
  final ValueNotifier<_Hover?> _hover = ValueNotifier(null);

  /// The user's zoomed view (index range), or null for the default view.
  final ValueNotifier<(double, double)?> _view = ValueNotifier(null);

  /// Indices of indicators the user hid with the legend's eye button.
  final ValueNotifier<Set<int>> _hiddenStudies = ValueNotifier(const {});

  /// Momentum after a swipe: an unbounded controller driven by a friction
  /// simulation; each tick pans by the distance it moved.
  late final AnimationController _fling;
  double _flingLast = 0;
  Size _flingSize = Size.zero;

  /// The view, focal point and plot area when the current pan/pinch began.
  (double, double)? _gestureStartView;
  double _gestureStartFocalX = 0;
  Rect _gestureArea = Rect.zero;
  double _lastGestureScale = 1;
  late final AnimationController _entrance;

  /// Pulses the last-price tag on every price change.
  late final AnimationController _flash;
  bool _tickUp = true;

  /// The candles as given (sorted) and as drawn (after [CandleType]).
  late List<Candle> _raw;
  late List<Candle> _candles;
  late List<_Study> _studies;

  /// A drawing being created (dragged or clicked out), not yet committed.
  final ValueNotifier<ChartDrawing?> _draft = ValueNotifier(null);
  _DrawDrag? _drawDrag;

  /// Where the latest pointer went down: drags on drawings start there,
  /// not where the gesture recognizer fires (after the touch slop).
  Offset? _downPos;
  final FocusNode _focus = FocusNode(debugLabel: 'CandlestickChart2D');

  @override
  ChartController? controllerOf(CandlestickChart2D widget) => widget.controller;

  @override
  void resetZoom() => _view.value = null;

  @override
  void initState() {
    super.initState();
    _raw = _sorted(widget.candles);
    _candles = _transformed();
    _studies = _compute();
    widget.drawingController?.addListener(_onDrawingsChanged);
    _entrance = AnimationController(vsync: this, duration: widget.animationDuration);
    widget.enableAnimation ? _entrance.forward() : _entrance.value = 1;
    _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 500), value: 1);
    _fling = AnimationController.unbounded(vsync: this)..addListener(_onFlingTick);
    _view.addListener(() => reportZoomed(_view.value != null));
  }

  static List<Candle> _sorted(List<Candle> candles) {
    for (int i = 1; i < candles.length; i++) {
      if (candles[i].time.isBefore(candles[i - 1].time)) return [...candles]..sort((a, b) => a.time.compareTo(b.time));
    }
    return candles;
  }

  List<Candle> _transformed() => CandleTransforms.apply(_raw, widget.candleType,
      renkoBoxSize: widget.renkoBoxSize, lineBreakCount: widget.lineBreakCount);

  /// Drop an unfinished drawing when its tool is disarmed elsewhere.
  void _onDrawingsChanged() {
    if (widget.drawingController?.activeTool == null && _drawDrag == null) _draft.value = null;
  }

  List<_Study> _compute() => [for (final ind in widget.indicators) _Study(ind, ind.compute(_candles))];

  double? get _lastPrice => widget.lastPrice ?? (_raw.isEmpty ? null : _raw.last.close);

  @override
  void didUpdateWidget(covariant CandlestickChart2D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.drawingController != widget.drawingController) {
      oldWidget.drawingController?.removeListener(_onDrawingsChanged);
      widget.drawingController?.addListener(_onDrawingsChanged);
      _draft.value = null;
      _drawDrag = null;
    }
    final oldCandles = _candles;
    final oldPrice = _raw.isEmpty ? null : (oldWidget.lastPrice ?? _raw.last.close);
    final typeChanged = oldWidget.candleType != widget.candleType ||
        oldWidget.renkoBoxSize != widget.renkoBoxSize ||
        oldWidget.lineBreakCount != widget.lineBreakCount;
    final candlesChanged =
        typeChanged || (!identical(oldWidget.candles, widget.candles) && !listEquals(oldWidget.candles, widget.candles));
    if (candlesChanged) {
      _raw = _sorted(widget.candles);
      _candles = _transformed();
      // Live update (new or changed candles at the end, maybe old ones trimmed
      // off the front) vs. a different data set altogether.
      final shift = typeChanged || _candles.isEmpty ? -1 : oldCandles.indexWhere((c) => c.time == _candles.first.time);
      if (shift < 0) {
        _view.value = null;
        _hover.value = null;
        _fling.stop();
        if (widget.enableAnimation) _entrance.forward(from: 0);
      } else {
        // Keep the view and hover on the same candles despite any trimmed
        // off the front…
        final v = _view.value;
        if (v != null) {
          var next = (v.$1 - shift, v.$2 - shift);
          // …and if the user was watching the newest candle, scroll along
          // with the new ones (at their zoom level), like a live chart.
          if (_atLiveEdge(v, oldCandles.length)) {
            final added = _candles.length - (oldCandles.length - shift);
            next = (next.$1 + added, next.$2 + added);
          }
          _view.value = next;
        }
        final h = _hover.value;
        if (h != null && shift > 0) _hover.value = h.$1 - shift < 0 ? null : (h.$1 - shift, h.$2);
      }
      final h = _hover.value;
      if (h != null && h.$1 >= _candles.length) _hover.value = null;
    }
    final indicatorsChanged = !listEquals(oldWidget.indicators, widget.indicators);
    if (candlesChanged || indicatorsChanged) _studies = _compute();
    // Hidden flags are by position, so a different indicator list resets them.
    if (indicatorsChanged) _hiddenStudies.value = const {};

    final newPrice = _lastPrice;
    if (oldPrice != null && newPrice != null && newPrice != oldPrice) {
      _tickUp = newPrice > oldPrice;
      _flash.forward(from: 0);
    }
  }

  @override
  void dispose() {
    widget.crosshairSync?.clear(this);
    widget.drawingController?.removeListener(_onDrawingsChanged);
    _draft.dispose();
    _focus.dispose();
    _entrance.dispose();
    _flash.dispose();
    _fling.dispose();
    _hover.dispose();
    _view.dispose();
    _hiddenStudies.dispose();
    super.dispose();
  }

  (double, double) _defaultView() {
    final n = _candles.length;
    final hi = n - 0.5 + widget.rightPadding;
    final visible = widget.visibleCandles;
    final lo = visible == null ? -0.5 : math.max(-0.5, n - visible - 0.5);
    return (lo, hi);
  }

  _CandleLayout _layout(Size size) {
    final hidden = _hiddenStudies.value;
    final studies = [
      for (int k = 0; k < _studies.length; k++)
        _Study(_studies[k].indicator, _studies[k].result, index: k, hidden: hidden.contains(k)),
    ];
    return _CandleLayout(size, _candles, _view.value ?? _defaultView(), studies, widget.showVolume, _lastPrice);
  }

  void _toggleStudy(int index) {
    final next = {..._hiddenStudies.value};
    if (!next.remove(index)) next.add(index); // was visible -> hide it
    _hiddenStudies.value = next;
    widget.onIndicatorVisibilityChanged?.call(widget.indicators[index], !next.contains(index));
  }

  void _setHover(Offset pos, Size size) {
    final i = _layout(size).indexUnder(pos);
    final previous = _hover.value?.$1;
    _hover.value = i == null ? null : (i, pos);
    if (i != previous) widget.onCandleHover?.call(i == null ? null : _candles[i]);
    final sync = widget.crosshairSync;
    if (sync != null) i == null ? sync.clear(this) : sync.update(this, _candles[i].time.millisecondsSinceEpoch.toDouble());
  }

  /// Whether view [v] shows the newest of [count] candles at the right edge.
  bool _atLiveEdge((double, double) v, int count) => v.$2 >= count - 0.5 + widget.rightPadding - 0.5;

  /// Clamps a view to between ~8 candles and everything, not scrolled far
  /// past either end of the data (a little empty space is allowed, as on
  /// trading platforms).
  (double, double) _clampView(double lo, double hi) {
    final n = _candles.length;
    final maxSpan = n + widget.rightPadding + 1.0;
    final span = (hi - lo).clamp(math.min(8.0, maxSpan), maxSpan);
    final minLo = -0.5 - span * 0.25;
    final maxHi = n - 0.5 + math.max(widget.rightPadding, span * 0.5);
    var l = lo;
    if (l + span > maxHi) l = maxHi - span;
    if (l < minLo) l = minLo;
    return (l, l + span);
  }

  /// Sets the view, or clears it when it's back at the default (which then
  /// keeps following live data and hides the reset button). Returns whether
  /// anything changed.
  bool _setView(double lo, double hi) {
    final before = _view.value ?? _defaultView();
    final v = _clampView(lo, hi);
    final d = _defaultView();
    final isDefault = (v.$1 - d.$1).abs() < 0.01 && (v.$2 - d.$2).abs() < 0.01;
    _view.value = isDefault ? null : v;
    return (v.$1 - before.$1).abs() > 1e-6 || (v.$2 - before.$2).abs() > 1e-6;
  }

  void _zoomAround(double pointerX, double factor, Size size) {
    final l = _layout(size);
    final anchor = l.indexAt(pointerX);
    final span = (l.hi - l.lo) * factor;
    final t = (anchor - l.lo) / (l.hi - l.lo);
    _setView(anchor - t * span, anchor - t * span + span);
  }

  /// Scrolls by [dx] pixels: positive drags reveal older candles.
  bool _panBy(double dx, Size size) {
    final l = _layout(size);
    final perPixel = (l.hi - l.lo) / l.area.width;
    return _setView(l.lo - dx * perPixel, l.hi - dx * perPixel);
  }

  void _onScaleStart(ScaleStartDetails d, Size size) {
    _fling.stop();
    final l = _layout(size);
    _gestureStartView = (l.lo, l.hi);
    _gestureStartFocalX = d.localFocalPoint.dx;
    _gestureArea = l.area;
    _lastGestureScale = 1;
  }

  /// One handler for both gestures: the candle that was under the fingers'
  /// focal point stays under it (pan), while the visible span shrinks or
  /// grows with the pinch (zoom).
  void _onScaleUpdate(ScaleUpdateDetails d) {
    final start = _gestureStartView;
    if (start == null) return;
    _hover.value = null; // the crosshair would only lag behind a moving chart
    final area = _gestureArea;
    final scale = widget.enableZoom && d.horizontalScale > 0 ? d.horizontalScale : 1.0;
    _lastGestureScale = scale;
    final span0 = start.$2 - start.$1;
    final span = span0 / scale;
    final anchor = start.$1 + (_gestureStartFocalX - area.left) / area.width * span0;
    final focalX = widget.enablePan ? d.localFocalPoint.dx : _gestureStartFocalX;
    final lo = anchor - (focalX - area.left) / area.width * span;
    _setView(lo, lo + span);
  }

  void _onScaleEnd(ScaleEndDetails d, Size size) {
    _gestureStartView = null;
    final vx = d.velocity.pixelsPerSecond.dx;
    // Momentum for swipes only, not for the end of a pinch.
    if (!widget.enablePan || vx.abs() < 100 || (_lastGestureScale - 1).abs() > 0.02) return;
    _flingLast = 0;
    _flingSize = size;
    _fling.animateWith(FrictionSimulation(0.135, 0, vx));
  }

  void _onFlingTick() {
    final delta = _fling.value - _flingLast;
    _flingLast = _fling.value;
    // Stop once we hit either end rather than spinning invisibly.
    if (!_panBy(delta, _flingSize)) _fling.stop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? ChartThemeScope.maybeOf(context) ?? ChartTheme.trading;
    final frame = _candles.isEmpty
        ? ChartFrame(
            boundaryKey: chartBoundaryKey,
            title: widget.title,
            subtitle: widget.subtitle,
            plot: ChartEmptyState(message: widget.emptyStateMessage),
          )
        : ChartFrame(
            boundaryKey: chartBoundaryKey,
            semanticLabel: describeChart(switch (widget.candleType) {
              CandleType.standard => 'Candlestick chart',
              CandleType.heikinAshi => 'Heikin-Ashi chart',
              CandleType.renko => 'Renko chart',
              CandleType.lineBreak => 'Line break chart',
            }, widget.title, [
              '${_candles.length} periods from ${formatTime(_candles.first.time)} to ${formatTime(_candles.last.time)}',
              'last price ${widget.priceFormatter(_lastPrice!)}',
              for (final s in _studies) s.indicator.label,
            ]),
            title: widget.title,
            subtitle: widget.subtitle,
            plot: LayoutBuilder(builder: (context, constraints) => _buildPlot(constraints.biggest, theme)),
          );
    // The chart's own theme applies to its header, empty state and buttons too.
    return ChartThemeScope(theme: theme, child: frame);
  }

  // ---- drawing tools ----

  DrawingPoint _pointAt(_CandleLayout l, Offset pos) =>
      DrawingPoint(DateTime.fromMillisecondsSinceEpoch(l.timeAtIndex(l.indexAt(pos.dx)).round()), l.price.valueAt(pos.dy));

  /// The drawing under [pos]: (drawing, handle index) for a handle, or
  /// (drawing, null) for its body.
  (ChartDrawing, int?)? _drawingAt(_CandleLayout l, Offset pos) {
    final c = widget.drawingController;
    if (c == null) return null;
    final drawings = c.drawings.reversed.toList();
    for (final d in drawings) {
      for (int k = 0; k < d.points.length; k++) {
        if ((_drawingScreenPoint(l, d.points[k]) - pos).distance <= 9) return (d, k);
      }
    }
    for (final d in drawings) {
      if (_nearDrawing(l, d, pos)) return (d, null);
    }
    return null;
  }

  /// Taps: place points while a tool is armed, otherwise select drawings.
  /// Returns whether the tap was used.
  bool _handleDrawingTap(Offset pos, Size size) {
    final c = widget.drawingController;
    if (c == null) return false;
    _focus.requestFocus();
    final l = _layout(size);
    final tool = c.activeTool;
    if (tool != null) {
      if (!l.price.rect.contains(pos)) return true;
      final p = _pointAt(l, pos);
      if (tool == DrawingTool.horizontalLine) {
        _draft.value = null;
        c.finish(ChartDrawing(id: c.newId(), tool: tool, points: [p], color: c.color));
        return true;
      }
      final draft = _draft.value;
      if (draft == null) {
        _draft.value = ChartDrawing(id: c.newId(), tool: tool, points: [p, p], color: c.color);
      } else {
        _draft.value = null;
        c.finish(draft.copyWith(points: [draft.points.first, p]));
      }
      return true;
    }
    final hit = _drawingAt(l, pos);
    c.select(hit?.$1.id);
    return hit != null;
  }

  bool _startDrawingDrag(ScaleStartDetails d, Size size) {
    final c = widget.drawingController;
    if (c == null || d.pointerCount > 1) return false;
    final l = _layout(size);
    final pos = _downPos ?? d.localFocalPoint;
    if (!l.price.rect.contains(pos)) return false;
    final tool = c.activeTool;
    if (tool != null) {
      _fling.stop();
      final pending = _draft.value;
      final p = _pointAt(l, pos);
      final horizontal = tool == DrawingTool.horizontalLine;
      // A drag after a first click finishes that drawing; otherwise it
      // starts a new one from here.
      final draft = pending != null && !horizontal
          ? pending
          : ChartDrawing(id: c.newId(), tool: tool, points: horizontal ? [p] : [p, p], color: c.color);
      _draft.value = draft;
      _drawDrag = _DrawDrag(draft, horizontal ? 0 : 1, pos, creating: true);
      return true;
    }
    final hit = _drawingAt(l, pos);
    if (hit == null) return false;
    _fling.stop();
    c.select(hit.$1.id);
    _drawDrag = _DrawDrag(hit.$1, hit.$2, pos, creating: false);
    return true;
  }

  bool _updateDrawingDrag(ScaleUpdateDetails d, Size size) {
    final drag = _drawDrag;
    if (drag == null) return false;
    final c = widget.drawingController!;
    final l = _layout(size);
    final pos = d.localFocalPoint;
    _hover.value = null;
    final ChartDrawing next;
    final handle = drag.handle;
    if (handle != null) {
      next = drag.original.copyWith(points: [...drag.original.points]..[handle] = _pointAt(l, pos));
    } else {
      final di = l.indexAt(pos.dx) - l.indexAt(drag.start.dx);
      final dp = l.price.valueAt(pos.dy) - l.price.valueAt(drag.start.dy);
      next = drag.original.copyWith(points: [
        for (final p in drag.original.points)
          DrawingPoint(
            DateTime.fromMillisecondsSinceEpoch(
                l.timeAtIndex(l.indexOfTimeExtended(p.time.millisecondsSinceEpoch.toDouble()) + di).round()),
            p.price + dp,
          ),
      ]);
    }
    drag.creating ? _draft.value = next : c.update(next);
    return true;
  }

  bool _endDrawingDrag(Size size) {
    final drag = _drawDrag;
    if (drag == null) return false;
    _drawDrag = null;
    if (!drag.creating) return true;
    final draft = _draft.value;
    if (draft == null) return true;
    final l = _layout(size);
    final pts = [for (final p in draft.points) _drawingScreenPoint(l, p)];
    if (pts.length > 1 && (pts[0] - pts[1]).distance < 4) return true; // still pending: click the second point
    _draft.value = null;
    widget.drawingController!.finish(draft);
    return true;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final c = widget.drawingController;
    if (c == null || e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      if (c.activeTool != null || _draft.value != null) {
        _draft.value = null;
        c.cancelDrawing();
        return KeyEventResult.handled;
      }
      if (c.selectedId != null) {
        c.select(null);
        return KeyEventResult.handled;
      }
    }
    if ((e.logicalKey == LogicalKeyboardKey.delete || e.logicalKey == LogicalKeyboardKey.backspace) && c.removeSelected()) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildPlot(Size size, ChartTheme theme) {
    final drawings = widget.drawingController;
    final navigates = widget.enablePan || widget.enableZoom;
    final plot = _buildPlotContent(size, theme, navigates || drawings != null);
    if (drawings == null) return plot;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: ListenableBuilder(
        listenable: drawings,
        builder: (context, child) => MouseRegion(
          cursor: drawings.activeTool != null ? SystemMouseCursors.precise : MouseCursor.defer,
          child: child,
        ),
        child: plot,
      ),
    );
  }

  Widget _buildPlotContent(Size size, ChartTheme theme, bool scaleGestures) {
    final navigates = widget.enablePan || widget.enableZoom;
    return Listener(
      onPointerDown: (e) => _downPos = e.localPosition,
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent || !_layout(size).area.contains(event.localPosition)) return;
        final (dx, dy) = (event.scrollDelta.dx, event.scrollDelta.dy);
        // Horizontal trackpad swipes and Shift+wheel scroll; the wheel zooms.
        final horizontal = dx.abs() > dy.abs() || HardwareKeyboard.instance.isShiftPressed;
        if (horizontal && widget.enablePan) {
          _fling.stop();
          _panBy(-(dx.abs() > dy.abs() ? dx : dy), size);
        } else if (!horizontal && widget.enableZoom) {
          _zoomAround(event.localPosition.dx, math.exp(dy * 0.002), size);
        }
      },
      child: MouseRegion(
        onHover: (e) {
          _setHover(e.localPosition, size);
          // Preview the second point of a click-click drawing.
          final draft = _draft.value;
          if (draft != null && _drawDrag == null && draft.points.length > 1) {
            _draft.value = draft.copyWith(points: [draft.points.first, _pointAt(_layout(size), e.localPosition)]);
          }
        },
        onExit: (_) {
          if (_hover.value != null) widget.onCandleHover?.call(null);
          _hover.value = null;
          widget.crosshairSync?.clear(this);
        },
        child: GestureDetector(
          onTapDown: (_) => _fling.stop(), // a touch catches a gliding chart
          onTapUp: (d) {
            if (_handleDrawingTap(d.localPosition, size)) return;
            _setHover(d.localPosition, size);
            final h = _hover.value;
            if (h != null) widget.onCandleTap?.call(_candles[h.$1]);
          },
          // Drag is navigation on touch screens, so press-and-hold moves the
          // crosshair instead.
          onLongPressStart: (d) => _setHover(d.localPosition, size),
          onLongPressMoveUpdate: (d) => _setHover(d.localPosition, size),
          onScaleStart: scaleGestures
              ? (d) {
                  if (_startDrawingDrag(d, size)) return;
                  if (navigates) _onScaleStart(d, size);
                }
              : null,
          onScaleUpdate: scaleGestures
              ? (d) {
                  if (_updateDrawingDrag(d, size)) return;
                  if (navigates) _onScaleUpdate(d);
                }
              : null,
          onScaleEnd: scaleGestures
              ? (d) {
                  if (_endDrawingDrag(size)) return;
                  if (navigates) _onScaleEnd(d, size);
                }
              : null,
          child: AnimatedBuilder(
            animation: Listenable.merge([_view, _entrance, _flash, _hiddenStudies]),
            builder: (context, _) {
              final layout = _layout(size);
              return Stack(children: [
                // The data layer repaints on data, view, entrance and price
                // flashes; the crosshair/legend layer on hover.
                RepaintBoundary(
                  child: CustomPaint(
                    size: size,
                    painter: _CandlePainter(
                      layout: layout,
                      widget: widget,
                      theme: theme,
                      lastPrice: _lastPrice,
                      flash: 1 - Curves.easeOut.transform(_flash.value),
                      tickUp: _tickUp,
                      progress: _entrance.value,
                    ),
                  ),
                ),
                if (widget.drawingController != null)
                  IgnorePointer(
                    child: ListenableBuilder(
                      listenable: Listenable.merge([widget.drawingController!, _draft]),
                      builder: (context, _) {
                        final c = widget.drawingController!;
                        final draft = _draft.value;
                        return CustomPaint(
                          size: size,
                          painter: _DrawingsPainter(
                            layout: layout,
                            drawings: [...c.drawings, if (draft != null) draft],
                            selectedId: draft?.id ?? c.selectedId,
                            theme: theme,
                            priceFormatter: widget.priceFormatter,
                          ),
                        );
                      },
                    ),
                  ),
                ListenableBuilder(
                  listenable: Listenable.merge([_hover, if (widget.crosshairSync != null) widget.crosshairSync!]),
                  builder: (context, _) {
                    // Our own hover, or the candle at another chart's synced
                    // time (no pointer: vertical crosshair and legend only).
                    var hover = _hover.value;
                    final synced = widget.crosshairSync?.xFor(this);
                    if (hover == null && synced != null && _candles.isNotEmpty) {
                      final i = layout.indexOfTime(synced).round();
                      if (i >= layout.firstVisible && i <= layout.lastVisible) hover = (i, Offset(layout.x(i), -1));
                    }
                    return Stack(children: [
                    IgnorePointer(
                      child: CustomPaint(
                        size: size,
                        painter: _CandleOverlayPainter(
                          layout: layout,
                          widget: widget,
                          theme: theme,
                          hover: hover,
                        ),
                      ),
                    ),
                    ..._indicatorLegends(layout, hover, theme),
                    if (hover != null && widget.tooltipBuilder != null)
                      positionChartTooltip(
                        anchor: Offset(layout.x(hover.$1), layout.price.y(_candles[hover.$1].high)),
                        areaSize: size,
                        cardWidth: 170,
                        child: widget.tooltipBuilder!(context, _candles[hover.$1]),
                      ),
                  ]);
                  },
                ),
                if (_view.value != null)
                  Positioned(right: _axisWidth + 8, top: 8, child: ChartResetZoomButton(theme: theme, onTap: resetZoom)),
              ]);
            },
          ),
        ),
      ),
    );
  }

  /// One row per indicator — its name, its values at the hovered (or
  /// latest) candle, and an eye button to hide/show it. Overlays stack under
  /// the price pane's O/H/L/C line; oscillators sit at the top of their pane.
  List<Widget> _indicatorLegends(_CandleLayout l, _Hover? hover, ChartTheme theme) {
    if (_candles.isEmpty) return const [];
    final i = hover?.$1 ?? _candles.length - 1;
    String two(double v) => Cartesian2DAxes.formatNumber(double.parse(v.toStringAsFixed(2)));
    var y = l.price.rect.top + 21;
    return [
      for (final s in l.overlays)
        Positioned(left: l.area.left + 2, top: (y += 18) - 18, child: _legendRow(s, i, theme, widget.priceFormatter)),
      for (final p in l.oscillators) Positioned(left: p.rect.left + 2, top: p.rect.top, child: _legendRow(p.study!, i, theme, two)),
    ];
  }

  Widget _legendRow(_Study s, int i, ChartTheme theme, String Function(double) format) {
    final muted = theme.subtitleColor;
    final style = TextStyle(fontSize: 11, fontWeight: FontWeight.w500, fontFamily: theme.fontFamily, height: 1.2);
    final r = s.result;
    final hist = r.histogram?.values[i];
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(width: 4),
      Text(s.indicator.label, style: style.copyWith(color: s.hidden ? muted.withValues(alpha: 0.45) : muted)),
      if (!s.hidden)
        Text.rich(TextSpan(style: style, children: [
          for (final line in r.lines)
            if (line.values[i] != null) TextSpan(text: '  ${format(line.values[i]!)}', style: TextStyle(color: line.color)),
          if (hist != null)
            TextSpan(
              text: '  ${format(hist)}',
              style: TextStyle(color: hist >= 0 ? r.histogram!.positiveColor : r.histogram!.negativeColor),
            ),
        ])),
      if (widget.showIndicatorToggles)
        _EyeToggle(
          hidden: s.hidden,
          color: s.hidden ? muted.withValues(alpha: 0.6) : muted,
          label: s.indicator.label,
          onTap: () => _toggleStudy(s.index),
        ),
    ]);
  }

}

/// Paints [spans] (text, color) in a row from [origin]; returns its width.
double _paintRow(Canvas canvas, Offset origin, List<(String, Color)> spans, ChartTheme theme, {double fontSize = 11}) {
  final tp = ChartTextPainter(
    text: TextSpan(children: [
      for (final (text, color) in spans)
        TextSpan(
          text: text,
          style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.w500, fontFamily: theme.fontFamily),
        ),
    ]),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  tp.paint(canvas, origin);
  return tp.width;
}

/// A filled tag on the price axis, e.g. the last price or crosshair value.
void _paintAxisTag(Canvas canvas, Rect area, double y, String text, Color background, Color foreground, ChartTheme theme) {
  final tp = layoutChartText(text, color: foreground, fontSize: theme.tickFontSize, fontFamily: theme.fontFamily);
  final box = Rect.fromLTWH(area.right + 1, y - tp.height / 2 - 3, math.max(_axisWidth - 4, tp.width + 10), tp.height + 6);
  canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(3)), Paint()..color = background);
  tp.paint(canvas, Offset(box.left + 5, box.top + 3));
}

class _CandlePainter extends CustomPainter {
  final _CandleLayout layout;
  final CandlestickChart2D widget;
  final ChartTheme theme;
  final double? lastPrice;

  /// 1 right after a price change, fading to 0.
  final double flash;
  final bool tickUp;
  final double progress;

  _CandlePainter({
    required this.layout,
    required this.widget,
    required this.theme,
    required this.lastPrice,
    required this.flash,
    required this.tickUp,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final l = layout;
    final area = l.area;
    final from = l.firstVisible, to = l.lastVisible;
    final gridPaint = Paint()
      ..color = theme.gridColor
      ..strokeWidth = 1;
    final borderPaint = Paint()
      ..color = theme.axisColor
      ..strokeWidth = 1;

    // Time ticks: vertical grid lines through every pane + labels below.
    final timeAxes = Cartesian2DAxes(plotArea: area, minX: l.lo, maxX: l.hi, minY: 0, maxY: 1, theme: theme);
    final ticks = _timeTicks(l.candles, from, to, math.max(2, (area.width / 90).floor()));
    if (widget.showGrid) {
      for (final (i, _) in ticks) {
        for (final p in [l.price, ...l.oscillators]) {
          canvas.drawLine(Offset(l.x(i), p.rect.top), Offset(l.x(i), p.rect.bottom), gridPaint);
        }
      }
    }
    timeAxes.drawXTicks(canvas, [for (final (i, label) in ticks) (l.x(i), label)]);

    // Each pane: horizontal grid, value labels on the right axis, a border.
    for (final p in [l.price, ...l.oscillators]) {
      final values = p.study == null
          ? Cartesian2DAxes.niceTicks(p.minY, p.maxY, count: math.max(2, (p.rect.height / 45).floor()))
          : (p.study!.result.fixedRange != null ? p.study!.result.levels : Cartesian2DAxes.niceTicks(p.minY, p.maxY, count: 3));
      for (final v in values) {
        final y = p.y(v);
        if (y < p.rect.top - 0.5 || y > p.rect.bottom + 0.5) continue;
        if (widget.showGrid) canvas.drawLine(Offset(p.rect.left, y), Offset(p.rect.right, y), gridPaint);
        final text = p.study == null ? widget.priceFormatter(v) : Cartesian2DAxes.formatNumber(double.parse(v.toStringAsFixed(2)));
        final tp = layoutChartText(text, color: theme.tickTextColor, fontSize: theme.tickFontSize, fontFamily: theme.fontFamily);
        tp.paint(canvas, Offset(area.right + 6, y - tp.height / 2));
      }
      canvas.drawLine(p.rect.topRight, p.rect.bottomRight, borderPaint);
      canvas.drawLine(p.rect.bottomLeft, p.rect.bottomRight, borderPaint);
    }

    // Price pane content, revealed left-to-right on entrance.
    final price = l.price;
    final priceAxes = Cartesian2DAxes(
        plotArea: price.rect, minX: l.lo, maxX: l.hi, minY: price.minY, maxY: price.maxY, theme: theme);
    final references = ReferencePainter(priceAxes);
    // Time-based references are in ms; this axis is in candle indices.
    ChartReferenceBand toIndexBand(ChartReferenceBand b) => b.axis == ChartReferenceAxis.x
        ? ChartReferenceBand.x(l.indexOfTime(b.from), l.indexOfTime(b.to), label: b.label, color: b.color)
        : b;
    ChartReferenceLine toIndexLine(ChartReferenceLine r) => r.axis == ChartReferenceAxis.x
        ? ChartReferenceLine.x(l.indexOfTime(r.value), label: r.label, color: r.color, strokeWidth: r.strokeWidth, dashed: r.dashed)
        : r;
    references.paintBands(canvas, [for (final b in widget.referenceBands) toIndexBand(b)]);

    canvas.save();
    canvas.clipRect(Rect.fromLTRB(price.rect.left, price.rect.top, price.rect.left + price.rect.width * progress, price.rect.bottom));

    final w = l.candleWidth;
    final vr = l.volumeRect;
    if (vr != null) {
      for (int i = from; i <= to; i++) {
        final c = l.candles[i];
        final h = (c.volume ?? 0) / l.maxVolume * vr.height;
        canvas.drawRect(Rect.fromLTRB(l.x(i) - w / 2, vr.bottom - h, l.x(i) + w / 2, vr.bottom),
            Paint()..color = (c.isUp ? widget.upColor : widget.downColor).withValues(alpha: 0.28));
      }
    }

    final vp = widget.volumeProfile;
    if (vp != null) _paintVolumeProfile(canvas, vp, from, to);

    for (final s in l.overlays) {
      if (!s.hidden) _paintStudy(canvas, s.result, price, from, to);
    }

    for (int i = from; i <= to; i++) {
      final c = l.candles[i];
      final x = l.x(i);
      final paint = Paint()
        ..color = c.isUp ? widget.upColor : widget.downColor
        ..strokeWidth = math.max(1, math.min(2, w / 6));
      final yHigh = price.y(c.high), yLow = price.y(c.low), yOpen = price.y(c.open), yClose = price.y(c.close);
      canvas.drawLine(Offset(x, yHigh), Offset(x, yLow), paint);
      if (widget.style == CandleStyle.candle) {
        canvas.drawRect(
            Rect.fromLTRB(x - w / 2, math.min(yOpen, yClose), x + w / 2, math.max(math.max(yOpen, yClose), math.min(yOpen, yClose) + 1)),
            paint);
      } else {
        canvas.drawLine(Offset(x - w / 2, yOpen), Offset(x, yOpen), paint);
        canvas.drawLine(Offset(x, yClose), Offset(x + w / 2, yClose), paint);
      }
    }
    canvas.restore();
    references.paintLines(canvas, [for (final r in widget.referenceLines) toIndexLine(r)]);
    paintAnnotations(canvas, widget.annotations, (a) {
      final i = l.indexOfTime(a.x);
      if (i < l.lo || i > l.hi) return null;
      return Offset(l.x(i), price.y(a.y));
    }, price.rect, theme);

    // Oscillator panes.
    for (final p in l.oscillators) {
      if (p.study!.hidden) continue; // keep the empty pane; draw nothing in it
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(p.rect.left, p.rect.top, p.rect.left + p.rect.width * progress, p.rect.bottom));
      final levelPaint = Paint()
        ..color = theme.crosshairColor.withValues(alpha: 0.6)
        ..strokeWidth = 1;
      for (final level in p.study!.result.levels) {
        Cartesian2DAxes.dashedLineStatic(canvas, Offset(p.rect.left, p.y(level)), Offset(p.rect.right, p.y(level)), levelPaint);
      }
      _paintStudy(canvas, p.study!.result, p, from, to);
      canvas.restore();
    }

    // Last traded price: a dashed line across the price pane and a tag on
    // the axis that flashes green/red as the price ticks up/down.
    final ltp = lastPrice;
    if (widget.showLastPrice && ltp != null && l.candles.isNotEmpty) {
      final y = price.y(ltp);
      if (y >= price.rect.top && y <= price.rect.bottom) {
        final base = l.candles.last.isUp ? widget.upColor : widget.downColor;
        Cartesian2DAxes.dashedLineStatic(canvas, Offset(price.rect.left, y), Offset(price.rect.right, y),
            Paint()
              ..color = base.withValues(alpha: 0.8)
              ..strokeWidth = 1);
        final flashColor = tickUp ? widget.upColor : widget.downColor;
        final tag = Color.lerp(base, Color.lerp(flashColor, Colors.white, 0.35)!, flash)!;
        _paintAxisTag(canvas, area, y, widget.priceFormatter(ltp), tag, Colors.white, theme);
      }
    }
  }

  /// Volume-at-price bars docked to the right of the price pane.
  void _paintVolumeProfile(Canvas canvas, VolumeProfile vp, int from, int to) {
    final l = layout;
    final p = l.price;
    final r = VolumeProfileResult.compute(l.candles,
        from: from, to: to, low: p.minY, high: p.maxY, bins: vp.bins, valueArea: vp.valueArea);
    if (r == null) return;
    final maxW = p.rect.width * vp.width, maxV = r.maxVolume;
    final right = p.rect.right;
    for (int b = 0; b < r.bins.length; b++) {
      final bin = r.bins[b];
      final inArea = b >= r.valueAreaLowIndex && b <= r.valueAreaHighIndex;
      final alpha = vp.showValueArea ? (inArea ? 0.45 : 0.18) : 0.32;
      final top = p.y(bin.high) + 0.5, bottom = p.y(bin.low) - 0.5;
      if (bottom <= top) continue;
      if (vp.splitUpDown) {
        final upW = bin.upVolume / maxV * maxW, downW = bin.downVolume / maxV * maxW;
        canvas.drawRect(Rect.fromLTRB(right - upW, top, right, bottom), Paint()..color = widget.upColor.withValues(alpha: alpha));
        canvas.drawRect(Rect.fromLTRB(right - upW - downW, top, right - upW, bottom),
            Paint()..color = widget.downColor.withValues(alpha: alpha));
      } else {
        final base = vp.color ?? theme.crosshairColor;
        canvas.drawRect(Rect.fromLTRB(right - bin.volume / maxV * maxW, top, right, bottom),
            Paint()..color = base.withValues(alpha: base.a * alpha * 1.6));
      }
    }
    if (vp.showPointOfControl) {
      final y = p.y(r.pointOfControl);
      final color = theme.axisColor.withValues(alpha: theme.axisColor.a * 0.8);
      Cartesian2DAxes.dashedLineStatic(canvas, Offset(p.rect.left, y), Offset(right, y), Paint()
        ..color = color
        ..strokeWidth = 1);
      final tp = layoutChartText('POC', color: color, fontSize: 9, fontWeight: FontWeight.w700, fontFamily: theme.fontFamily);
      tp.paint(canvas, Offset(right - maxW - tp.width - 4, y - tp.height - 1));
    }
  }

  void _paintStudy(Canvas canvas, IndicatorResult r, _Pane p, int from, int to) {
    final l = layout;
    final hist = r.histogram;
    if (hist != null) {
      final zero = p.y(0);
      for (int i = from; i <= to; i++) {
        final v = hist.values[i];
        if (v == null) continue;
        final y = p.y(v);
        canvas.drawRect(Rect.fromLTRB(l.x(i) - l.candleWidth / 2, math.min(y, zero), l.x(i) + l.candleWidth / 2, math.max(y, zero)),
            Paint()..color = v >= 0 ? hist.positiveColor : hist.negativeColor);
      }
    }
    final band = r.band;
    if (band != null) {
      final upper = r.lines[band.$1].values, lower = r.lines[band.$2].values;
      // Along the upper line, then back along the lower one.
      final path = Path();
      final back = <Offset>[];
      for (int i = from; i <= to; i++) {
        if (upper[i] == null || lower[i] == null) continue;
        final pt = Offset(l.x(i), p.y(upper[i]!));
        back.isEmpty ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
        back.add(Offset(l.x(i), p.y(lower[i]!)));
      }
      for (final pt in back.reversed) {
        path.lineTo(pt.dx, pt.dy);
      }
      if (back.length > 1) canvas.drawPath(path..close(), Paint()..color = band.$3);
    }
    for (final line in r.lines) {
      final path = Path();
      bool started = false;
      // Extend one candle beyond the view so lines run to the edges.
      for (int i = math.max(0, from - 1); i <= math.min(l.candles.length - 1, to + 1); i++) {
        final v = line.values[i];
        if (v == null) {
          started = false;
          continue;
        }
        started ? path.lineTo(l.x(i), p.y(v)) : path.moveTo(l.x(i), p.y(v));
        started = true;
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = line.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = line.width
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CandlePainter old) =>
      !identical(old.layout.candles, layout.candles) ||
      old.layout.lo != layout.lo ||
      old.layout.hi != layout.hi ||
      old.layout.area != layout.area ||
      old.lastPrice != lastPrice ||
      old.flash != flash ||
      old.progress != progress ||
      old.theme != theme ||
      !identical(old.widget, widget) ||
      !identical(old.layout.overlays, layout.overlays);
}

/// Crosshair, axis tags and the per-pane legends — everything that changes
/// on hover, above the data layer.
class _CandleOverlayPainter extends CustomPainter {
  final _CandleLayout layout;
  final CandlestickChart2D widget;
  final ChartTheme theme;
  final _Hover? hover;

  _CandleOverlayPainter({required this.layout, required this.widget, required this.theme, required this.hover});

  @override
  void paint(Canvas canvas, Size size) {
    final l = layout;
    if (l.candles.isEmpty) return;
    final i = hover?.$1 ?? l.candles.length - 1;
    final c = l.candles[i];
    final muted = theme.subtitleColor;
    final f = widget.priceFormatter;

    // Price pane legend: O H L C (+change) of the hovered or latest candle,
    // then each overlay's value at that candle.
    final valueColor = c.isUp ? widget.upColor : widget.downColor;
    final prevClose = i > 0 ? l.candles[i - 1].close : c.open;
    final change = c.close - prevClose;
    final pct = prevClose == 0 ? 0 : change / prevClose * 100;
    _paintRow(canvas, Offset(l.area.left + 6, l.price.rect.top + 4), [
      ('O ', muted), ('${f(c.open)}  ', valueColor),
      ('H ', muted), ('${f(c.high)}  ', valueColor),
      ('L ', muted), ('${f(c.low)}  ', valueColor),
      ('C ', muted), ('${f(c.close)}  ', valueColor),
      ('${change >= 0 ? '+' : ''}${f(change)} (${change >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%)', valueColor),
      if (c.volume != null) ('   Vol ${widget.volumeFormatter(c.volume!)}', muted),
    ], theme);
    // Indicator rows (with their eye buttons) are widgets, built by the state.

    final h = hover;
    if (h == null || !widget.showCrosshair) return;
    final x = l.x(h.$1);
    final crossPaint = Paint()
      ..color = theme.crosshairColor
      ..strokeWidth = 1;
    for (final p in [l.price, ...l.oscillators]) {
      Cartesian2DAxes.dashedLineStatic(canvas, Offset(x, p.rect.top), Offset(x, p.rect.bottom), crossPaint);
    }
    // Horizontal line + value tag in whichever pane the pointer is in.
    final pane = l.paneAt(h.$2);
    if (pane != null) {
      Cartesian2DAxes.dashedLineStatic(canvas, Offset(pane.rect.left, h.$2.dy), Offset(pane.rect.right, h.$2.dy), crossPaint);
      final v = pane.valueAt(h.$2.dy);
      final text = pane.study == null ? f(v) : Cartesian2DAxes.formatNumber(double.parse(v.toStringAsFixed(2)));
      _paintAxisTag(canvas, l.area, h.$2.dy, text, theme.tooltipBackgroundColor, theme.tooltipTextColor, theme);
    }
    // Time tag under the hovered candle.
    final label = widget.timeFormatter?.call(c.time) ?? formatTime(c.time);
    final tp = layoutChartText(label, color: theme.tooltipTextColor, fontSize: theme.tickFontSize, fontFamily: theme.fontFamily);
    final box = Rect.fromCenter(center: Offset(x, l.area.bottom + _timeAxisHeight / 2), width: tp.width + 12, height: tp.height + 6);
    final shifted = box.shift(Offset((l.area.left - box.left).clamp(0, double.infinity) + (l.area.right - box.right).clamp(double.negativeInfinity, 0), 0));
    canvas.drawRRect(RRect.fromRectAndRadius(shifted, const Radius.circular(3)), Paint()..color = theme.tooltipBackgroundColor);
    tp.paint(canvas, shifted.topLeft + const Offset(6, 3));
  }

  @override
  bool shouldRepaint(covariant _CandleOverlayPainter old) => true;
}

/// The eye button on an indicator's legend row.
class _EyeToggle extends StatelessWidget {
  final bool hidden;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _EyeToggle({required this.hidden, required this.color, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: hidden ? 'Show $label' : 'Hide $label',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          // Padding gives a comfortable hit area around the small icon.
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            child: Icon(hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 14, color: color),
          ),
        ),
      ),
    );
  }
}

/// An in-progress drag on a drawing: creating it, moving one handle, or
/// moving the whole drawing (handle == null).
class _DrawDrag {
  final ChartDrawing original;
  final int? handle;
  final Offset start;
  final bool creating;
  _DrawDrag(this.original, this.handle, this.start, {required this.creating});
}

Offset _drawingScreenPoint(_CandleLayout l, DrawingPoint p) =>
    Offset(l.x(l.indexOfTimeExtended(p.time.millisecondsSinceEpoch.toDouble())), l.price.y(p.price));

double _segmentDistance(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.distanceSquared;
  final t = len2 == 0 ? 0.0 : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

/// Where a ray from [a] through [b] leaves [bounds] (far enough to clip).
Offset _rayEnd(Offset a, Offset b, Rect bounds) {
  final d = b - a;
  if (d.distance < 1e-6) return b;
  return a + d * ((bounds.longestSide * 4) / d.distance);
}

/// Fibonacci levels span at least this wide, so a vertical drag still shows.
const double _minFibWidth = 60;

(double, double) _fibSpan(Offset a, Offset b) {
  final x0 = math.min(a.dx, b.dx), x1 = math.max(a.dx, b.dx);
  return (x0, math.max(x1, x0 + _minFibWidth));
}

bool _nearDrawing(_CandleLayout l, ChartDrawing d, Offset pos) {
  final pts = [for (final p in d.points) _drawingScreenPoint(l, p)];
  if (pts.isEmpty) return false;
  const tolerance = 6.0;
  switch (d.tool) {
    case DrawingTool.horizontalLine:
      return (pos.dy - pts[0].dy).abs() <= tolerance && l.price.rect.contains(pos);
    case DrawingTool.trendLine:
      return pts.length > 1 && _segmentDistance(pos, pts[0], pts[1]) <= tolerance;
    case DrawingTool.ray:
      return pts.length > 1 && _segmentDistance(pos, pts[0], _rayEnd(pts[0], pts[1], l.price.rect)) <= tolerance;
    case DrawingTool.rectangle:
      return pts.length > 1 && Rect.fromPoints(pts[0], pts[1]).inflate(4).contains(pos);
    case DrawingTool.fibonacci:
      if (pts.length < 2) return false;
      final (x0, x1) = _fibSpan(pts[0], pts[1]);
      if (pos.dx < x0 - 4 || pos.dx > x1 + 4) return false;
      return ChartDrawing.fibonacciLevels.any((lv) => (l.price.y(d.fibonacciPrice(lv)) - pos.dy).abs() <= tolerance);
  }
}

class _DrawingsPainter extends CustomPainter {
  final _CandleLayout layout;
  final List<ChartDrawing> drawings;
  final String? selectedId;
  final ChartTheme theme;
  final String Function(double) priceFormatter;

  _DrawingsPainter({
    required this.layout,
    required this.drawings,
    required this.selectedId,
    required this.theme,
    required this.priceFormatter,
  });

  static const _fibColors = [
    Color(0xFF787B86),
    Color(0xFFF23645),
    Color(0xFFFF9800),
    Color(0xFF4CAF50),
    Color(0xFF089981),
    Color(0xFF2962FF),
    Color(0xFF787B86),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final l = layout;
    final rect = l.price.rect;
    final tags = <(double, String, Color)>[];
    canvas.save();
    canvas.clipRect(rect);
    for (final d in drawings) {
      final pts = [for (final p in d.points) _drawingScreenPoint(l, p)];
      if (pts.isEmpty) continue;
      final stroke = Paint()
        ..color = d.color
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      switch (d.tool) {
        case DrawingTool.trendLine:
          if (pts.length > 1) canvas.drawLine(pts[0], pts[1], stroke);
        case DrawingTool.ray:
          if (pts.length > 1) canvas.drawLine(pts[0], _rayEnd(pts[0], pts[1], rect), stroke);
        case DrawingTool.horizontalLine:
          canvas.drawLine(Offset(rect.left, pts[0].dy), Offset(rect.right, pts[0].dy), stroke);
          tags.add((pts[0].dy, priceFormatter(d.points[0].price), d.color));
        case DrawingTool.rectangle:
          if (pts.length < 2) break;
          final r = Rect.fromPoints(pts[0], pts[1]);
          canvas.drawRect(r, Paint()..color = d.color.withValues(alpha: d.color.a * 0.14));
          canvas.drawRect(r, stroke);
        case DrawingTool.fibonacci:
          if (pts.length < 2) break;
          final (x0, x1) = _fibSpan(pts[0], pts[1]);
          const levels = ChartDrawing.fibonacciLevels;
          for (int i = 0; i + 1 < levels.length; i++) {
            final ya = l.price.y(d.fibonacciPrice(levels[i])), yb = l.price.y(d.fibonacciPrice(levels[i + 1]));
            final c = _fibColors[(i + 1) % _fibColors.length];
            canvas.drawRect(Rect.fromLTRB(x0, math.min(ya, yb), x1, math.max(ya, yb)), Paint()..color = c.withValues(alpha: 0.08));
          }
          for (int i = 0; i < levels.length; i++) {
            final price = d.fibonacciPrice(levels[i]);
            final y = l.price.y(price);
            final c = _fibColors[i % _fibColors.length];
            canvas.drawLine(Offset(x0, y), Offset(x1, y), Paint()
              ..color = c
              ..strokeWidth = 1);
            final tp = layoutChartText('${levels[i]} (${priceFormatter(price)})',
                color: c, fontSize: 9.5, fontWeight: FontWeight.w600, fontFamily: theme.fontFamily);
            tp.paint(canvas, Offset(x0 + 3, y - tp.height - 1));
          }
          Cartesian2DAxes.dashedLineStatic(canvas, pts[0], pts[1], Paint()
            ..color = d.color.withValues(alpha: d.color.a * 0.7)
            ..strokeWidth = 1);
      }
      if (d.id == selectedId) {
        for (final p in pts) {
          canvas.drawCircle(p, 5, Paint()..color = theme.tooltipBackgroundColor);
          canvas.drawCircle(p, 5, Paint()
            ..color = d.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8);
        }
      }
    }
    canvas.restore();
    for (final (y, text, color) in tags) {
      if (y >= rect.top && y <= rect.bottom) _paintAxisTag(canvas, l.area, y, text, color, Colors.white, theme);
    }
  }

  @override
  bool shouldRepaint(covariant _DrawingsPainter old) => true;
}
