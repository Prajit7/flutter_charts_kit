import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'theme.dart';
import 'cartesian_axes.dart';
import 'chart_chrome.dart';
import 'common.dart';
import 'controller.dart';
import 'legend.dart';
import 'models.dart';
import 'option_math.dart';

/// Open interest at one strike of an option chain.
class OptionStrikeData {
  final double strike;
  final double callOI;
  final double putOI;

  /// Change in OI since the previous session (signed).
  final double? callOIChange;
  final double? putOIChange;

  const OptionStrikeData({
    required this.strike,
    required this.callOI,
    required this.putOI,
    this.callOIChange,
    this.putOIChange,
  });
}

/// What an [OpenInterestChart2D] plots.
enum OpenInterestView {
  /// Total open interest per strike.
  total,

  /// Change in open interest (bars go below zero for unwinding).
  change,
}

/// Open interest by strike: calls and puts side by side at each strike,
/// with the spot price, max pain and put/call ratio — the option chain at
/// a glance. Large call OI often acts as resistance, large put OI as
/// support.
///
/// ```dart
/// OpenInterestChart2D(
///   spot: 24480,
///   strikes: [
///     OptionStrikeData(strike: 24400, callOI: 52000, putOI: 98000, callOIChange: 4000, putOIChange: 21000),
///     ...
///   ],
/// )
/// ```
///
/// With many strikes, the chart opens on the [visibleStrikes] around the
/// spot; drag sideways (or scroll) to see the rest.
class OpenInterestChart2D extends StatefulWidget {
  final List<OptionStrikeData> strikes;
  final double? spot;
  final OpenInterestView view;

  /// How many strikes fit the width; the rest scroll.
  final int visibleStrikes;
  final bool showMaxPain;
  final bool showSummary;
  final bool showLegend;
  final String? title;
  final String? subtitle;
  final String emptyStateMessage;
  final Color callColor;
  final Color putColor;
  final String Function(double strike) strikeFormatter;
  final String Function(double oi) oiFormatter;
  final Widget Function(BuildContext context, OptionStrikeData strike)? tooltipBuilder;
  final ChartController? controller;
  final ValueChanged<OptionStrikeData>? onStrikeTap;

  const OpenInterestChart2D({
    super.key,
    required this.strikes,
    this.spot,
    this.view = OpenInterestView.total,
    this.visibleStrikes = 21,
    this.showMaxPain = true,
    this.showSummary = true,
    this.showLegend = true,
    this.title,
    this.subtitle,
    this.emptyStateMessage = 'No option chain data',
    this.callColor = const Color(0xFFEF5350),
    this.putColor = const Color(0xFF26A69A),
    this.strikeFormatter = Cartesian2DAxes.formatNumber,
    this.oiFormatter = compactNumber,
    this.tooltipBuilder,
    this.controller,
    this.onStrikeTap,
  });

  /// 1.2K, 3.4M, 5.6B.
  static String compactNumber(double v) {
    final a = v.abs(), sign = v < 0 ? '-' : '';
    String f(double x) => x >= 100 ? x.toStringAsFixed(0) : x.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
    if (a >= 1e9) return '$sign${f(a / 1e9)}B';
    if (a >= 1e6) return '$sign${f(a / 1e6)}M';
    if (a >= 1e3) return '$sign${f(a / 1e3)}K';
    return '$sign${f(a)}';
  }

  @override
  State<OpenInterestChart2D> createState() => _OpenInterestChart2DState();
}

class _OpenInterestChart2DState extends State<OpenInterestChart2D> with ChartControllerMixin<OpenInterestChart2D> {
  /// Index of the first visible strike (fractional while dragging).
  double? _offset;
  final ValueNotifier<(int, Offset)?> _hover = ValueNotifier(null);
  late List<OptionStrikeData> _sorted;

  @override
  ChartController? controllerOf(OpenInterestChart2D widget) => widget.controller;

  /// Back to the strikes around spot.
  @override
  void resetZoom() {
    setState(() => _offset = null);
    reportZoomed(false);
  }

  @override
  void initState() {
    super.initState();
    _sort();
  }

  @override
  void didUpdateWidget(covariant OpenInterestChart2D old) {
    super.didUpdateWidget(old);
    if (!identical(old.strikes, widget.strikes)) _sort();
  }

  @override
  void dispose() {
    _hover.dispose();
    super.dispose();
  }

  void _sort() => _sorted = [...widget.strikes]..sort((a, b) => a.strike.compareTo(b.strike));

  int get _count => math.min(widget.visibleStrikes, _sorted.length);

  double get _maxOffset => (_sorted.length - _count).toDouble();

  /// The strikes centred on spot (or the middle of the chain).
  double get _defaultOffset {
    final spot = widget.spot;
    if (spot == null || _sorted.isEmpty) return _maxOffset / 2;
    var atm = 0;
    for (int i = 0; i < _sorted.length; i++) {
      if ((_sorted[i].strike - spot).abs() < (_sorted[atm].strike - spot).abs()) atm = i;
    }
    return (atm - (_count - 1) / 2).clamp(0.0, _maxOffset).roundToDouble();
  }

  double get _start => (_offset ?? _defaultOffset).clamp(0.0, _maxOffset);

  Rect _plot(Size size, ChartTheme theme, List<double> ticks) {
    final widest = ticks
        .map((t) => layoutChartText(widget.oiFormatter(t), color: theme.tickTextColor, fontSize: theme.tickFontSize).width)
        .fold(0.0, math.max);
    final top = widget.showSummary ? 30.0 : 12.0;
    return Rect.fromLTRB(math.max(36, widest + 12), top, size.width - 10, math.max(top + 1, size.height - 26));
  }

  (double, double) _value(OptionStrikeData s) => widget.view == OpenInterestView.total
      ? (s.callOI, s.putOI)
      : (s.callOIChange ?? 0, s.putOIChange ?? 0);

  (double, double) get _extent {
    var lo = 0.0, hi = 0.0;
    // Over the whole chain, so the scale doesn't jump while scrolling.
    for (final s in _sorted) {
      final (c, p) = _value(s);
      lo = math.min(lo, math.min(c, p));
      hi = math.max(hi, math.max(c, p));
    }
    if (lo == hi) hi = 1;
    return Cartesian2DAxes.niceExtent(lo, hi * 1.05);
  }

  int? _strikeAt(Offset pos, Rect plot) {
    if (pos.dx < plot.left || pos.dx > plot.right || pos.dy < plot.top - 4 || pos.dy > plot.bottom + 22) return null;
    final slot = plot.width / _count;
    final i = (_start + (pos.dx - plot.left) / slot - 0.5).round();
    return i >= 0 && i < _sorted.length ? i : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    final w = widget;
    if (_sorted.isEmpty) {
      return ChartFrame(
        boundaryKey: chartBoundaryKey,
        title: w.title,
        subtitle: w.subtitle,
        plot: ChartEmptyState(message: w.emptyStateMessage),
      );
    }
    final totalCalls = _sorted.fold(0.0, (s, x) => s + x.callOI);
    final totalPuts = _sorted.fold(0.0, (s, x) => s + x.putOI);
    final pcr = totalCalls == 0 ? null : totalPuts / totalCalls;
    final maxPain = OptionMath.maxPain([for (final s in _sorted) (s.strike, s.callOI, s.putOI)]);
    final (minY, maxY) = _extent;
    final ticks = Cartesian2DAxes.niceTicks(minY, maxY, count: 5);
    final summary = <(String, String, Color)>[
      if (pcr != null) ('PCR ', pcr.toStringAsFixed(2), pcr >= 1 ? w.putColor : w.callColor),
      if (maxPain != null && w.showMaxPain) ('Max pain ', w.strikeFormatter(maxPain), theme.axisColor),
      ('Calls ', w.oiFormatter(totalCalls), w.callColor),
      ('Puts ', w.oiFormatter(totalPuts), w.putColor),
    ];
    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Open interest chart', w.title, [
        '${_sorted.length} strikes',
        for (final (l, v, _) in summary) '$l$v',
      ]),
      title: w.title,
      subtitle: w.subtitle,
      legendBuilder: w.showLegend
          ? (direction) => Chart2DLegend(direction: direction, entries: [
                LegendEntry(label: w.view == OpenInterestView.total ? 'Call OI' : 'Call OI change', color: w.callColor),
                LegendEntry(label: w.view == OpenInterestView.total ? 'Put OI' : 'Put OI change', color: w.putColor),
              ])
          : null,
      plot: LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest;
        final plot = _plot(size, theme, ticks);
        final scrollable = _sorted.length > _count;
        void pan(double dx) {
          if (!scrollable) return;
          final slot = plot.width / _count;
          setState(() => _offset = (_start - dx / slot).clamp(0.0, _maxOffset));
          reportZoomed(true);
        }

        return Listener(
          onPointerSignal: (e) {
            // Trackpad swipes and Shift+wheel scroll the chain sideways.
            if (e is PointerScrollEvent) pan(-(e.scrollDelta.dx != 0 ? e.scrollDelta.dx : e.scrollDelta.dy));
          },
          child: MouseRegion(
            onHover: (e) {
              final i = _strikeAt(e.localPosition, plot);
              _hover.value = i == null ? null : (i, e.localPosition);
            },
            onExit: (_) => _hover.value = null,
            child: GestureDetector(
              onTapUp: (d) {
                final i = _strikeAt(d.localPosition, plot);
                _hover.value = i == null ? null : (i, d.localPosition);
                if (i != null) w.onStrikeTap?.call(_sorted[i]);
              },
              onHorizontalDragUpdate: scrollable
                  ? (d) {
                      _hover.value = null;
                      pan(d.delta.dx);
                    }
                  : null,
              onHorizontalDragEnd: scrollable ? (_) => setState(() => _offset = _start.roundToDouble()) : null,
              child: ValueListenableBuilder<(int, Offset)?>(
                valueListenable: _hover,
                builder: (context, hover, _) => Stack(children: [
                  CustomPaint(
                    size: size,
                    painter: _OIPainter(
                      state: this,
                      plot: plot,
                      minY: minY,
                      maxY: maxY,
                      ticks: ticks,
                      start: _start,
                      maxPain: w.showMaxPain ? maxPain : null,
                      summary: w.showSummary ? summary : const [],
                      theme: theme,
                      hovered: hover?.$1,
                    ),
                  ),
                  if (_offset != null && (_offset! - _defaultOffset).abs() > 0.5)
                    Positioned(right: 12, top: plot.top + 4, child: ChartResetZoomButton(theme: theme, onTap: resetZoom)),
                  if (hover != null) _tooltip(context, _sorted[hover.$1], hover.$2, size, theme),
                ]),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _tooltip(BuildContext context, OptionStrikeData s, Offset pointer, Size size, ChartTheme theme) {
    final w = widget;
    String change(double? c) => c == null ? '' : ' (${c >= 0 ? '+' : ''}${w.oiFormatter(c)})';
    final pcr = s.callOI == 0 ? null : s.putOI / s.callOI;
    return positionChartTooltip(
      anchor: pointer,
      areaSize: size,
      cardWidth: 190,
      child: w.tooltipBuilder?.call(context, s) ??
          ChartTooltipCard(
            theme: theme,
            width: 190,
            title: 'Strike ${w.strikeFormatter(s.strike)}',
            subtitle: 'Calls ${w.oiFormatter(s.callOI)}${change(s.callOIChange)}\n'
                'Puts ${w.oiFormatter(s.putOI)}${change(s.putOIChange)}',
            value: pcr == null ? null : 'PCR ${pcr.toStringAsFixed(2)}',
          ),
    );
  }
}

class _OIPainter extends CustomPainter {
  final _OpenInterestChart2DState state;
  final Rect plot;
  final double minY, maxY;
  final List<double> ticks;
  final double start;
  final double? maxPain;
  final List<(String, String, Color)> summary;
  final ChartTheme theme;
  final int? hovered;

  _OIPainter({
    required this.state,
    required this.plot,
    required this.minY,
    required this.maxY,
    required this.ticks,
    required this.start,
    required this.maxPain,
    required this.summary,
    required this.theme,
    required this.hovered,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = state;
    final w = s.widget;
    final strikes = s._sorted;
    final count = s._count;
    final slot = plot.width / count;
    double xOf(double index) => plot.left + (index - start + 0.5) * slot;
    double yOf(double v) => plot.bottom - (v - minY) / (maxY - minY) * plot.height;

    final axes = Cartesian2DAxes(plotArea: plot, minX: 0, maxX: 1, minY: minY, maxY: maxY, theme: theme);
    axes.drawGridAndAxes(canvas, yTicks: ticks, yFormatter: w.oiFormatter);

    canvas.save();
    canvas.clipRect(Rect.fromLTRB(plot.left, 0, plot.right, size.height));

    // Strike labels: every nth so they don't collide.
    final sample = layoutChartText(w.strikeFormatter(strikes.last.strike), color: theme.tickTextColor, fontSize: theme.tickFontSize);
    final every = math.max(1, ((sample.width + 10) / slot).ceil());
    final first = math.max(0, start.floor() - 1), last = math.min(strikes.length - 1, (start + count).ceil());
    final zero = yOf(0);
    final barW = math.max(1.0, slot * 0.36);
    for (int i = first; i <= last; i++) {
      final x = xOf(i.toDouble());
      if (i == hovered) {
        canvas.drawRect(Rect.fromLTRB(x - slot / 2, plot.top, x + slot / 2, plot.bottom),
            Paint()..color = theme.crosshairColor.withValues(alpha: theme.crosshairColor.a * 0.15));
      }
      final (c, p) = s._value(strikes[i]);
      for (final (v, color, dx) in [(c, w.callColor, -barW / 2 - 0.5), (p, w.putColor, barW / 2 + 0.5)]) {
        final y = yOf(v);
        final r = Rect.fromLTRB(x + dx - barW / 2, math.min(y, zero), x + dx + barW / 2, math.max(y, zero));
        canvas.drawRRect(
          RRect.fromRectAndCorners(r,
              topLeft: Radius.circular(v >= 0 ? 2 : 0),
              topRight: Radius.circular(v >= 0 ? 2 : 0),
              bottomLeft: Radius.circular(v < 0 ? 2 : 0),
              bottomRight: Radius.circular(v < 0 ? 2 : 0)),
          Paint()..color = color.withValues(alpha: color.a * (hovered == null || hovered == i ? 0.9 : 0.55)),
        );
      }
      if (i % every == 0) {
        final atm = w.spot != null && i == _atm(strikes, w.spot!);
        final tp = layoutChartText(w.strikeFormatter(strikes[i].strike),
            color: atm ? theme.axisColor : theme.tickTextColor,
            fontSize: theme.tickFontSize,
            fontWeight: atm ? FontWeight.w800 : FontWeight.w600,
            fontFamily: theme.fontFamily);
        tp.paint(canvas, Offset(x - tp.width / 2, plot.bottom + 6));
      }
    }

    // Spot (between strikes) and max pain.
    double? xOfPrice(double price) {
      for (int i = 0; i + 1 < strikes.length; i++) {
        final a = strikes[i].strike, b = strikes[i + 1].strike;
        if (price >= a && price <= b) return xOf(i + (b == a ? 0 : (price - a) / (b - a)));
      }
      return null;
    }

    void marker(double? price, String label, Color color, double labelY) {
      if (price == null) return;
      final x = xOfPrice(price);
      if (x == null || x < plot.left || x > plot.right) return;
      axes.dashedLine(canvas, Offset(x, plot.top), Offset(x, plot.bottom), Paint()
        ..color = color
        ..strokeWidth = 1.2);
      final tp = layoutChartText(label, color: theme.tooltipTextColor, fontSize: 10, fontFamily: theme.fontFamily);
      final box = Rect.fromLTWH((x - tp.width / 2 - 5).clamp(plot.left, plot.right - tp.width - 10), labelY, tp.width + 10, tp.height + 4);
      canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(3)), Paint()..color = theme.tooltipBackgroundColor);
      canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(3)), Paint()
        ..style = PaintingStyle.stroke
        ..color = color);
      tp.paint(canvas, box.topLeft + const Offset(5, 2));
    }

    marker(w.spot, 'Spot ${w.spot == null ? '' : w.strikeFormatter(w.spot!)}', theme.axisColor, plot.top + 2);
    marker(maxPain, 'Max pain ${maxPain == null ? '' : w.strikeFormatter(maxPain!)}', theme.subtitleColor, plot.top + 24);
    canvas.restore();

    // Summary above the plot.
    var x = plot.left;
    for (final (label, value, color) in summary) {
      final l = layoutChartText(label, color: theme.subtitleColor, fontSize: 11, fontWeight: FontWeight.w500, fontFamily: theme.fontFamily);
      final v = layoutChartText(value, color: color, fontSize: 11, fontWeight: FontWeight.w700, fontFamily: theme.fontFamily);
      if (x + l.width + v.width > plot.right && x > plot.left) break;
      l.paint(canvas, Offset(x, 6));
      v.paint(canvas, Offset(x + l.width, 6));
      x += l.width + v.width + 16;
    }

    // Scroll hint: fade marks at clipped edges.
    if (start > 0.01) _edge(canvas, Rect.fromLTWH(plot.left, plot.top, 14, plot.height), true);
    if (start < s._maxOffset - 0.01) _edge(canvas, Rect.fromLTWH(plot.right - 14, plot.top, 14, plot.height), false);
  }

  void _edge(Canvas canvas, Rect r, bool left) {
    final base = theme.tooltipBackgroundColor;
    canvas.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: left ? Alignment.centerLeft : Alignment.centerRight,
          end: left ? Alignment.centerRight : Alignment.centerLeft,
          colors: [base.withValues(alpha: base.a * 0.7), base.withValues(alpha: 0)],
        ).createShader(r),
    );
  }

  static int _atm(List<OptionStrikeData> strikes, double spot) {
    var atm = 0;
    for (int i = 0; i < strikes.length; i++) {
      if ((strikes[i].strike - spot).abs() < (strikes[atm].strike - spot).abs()) atm = i;
    }
    return atm;
  }

  @override
  bool shouldRepaint(covariant _OIPainter old) => true;
}
