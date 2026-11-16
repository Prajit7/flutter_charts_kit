import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme.dart';
import 'cartesian_axes.dart';
import 'chart_chrome.dart';
import 'common.dart';
import 'controller.dart';
import 'hover_plot.dart';
import 'option_math.dart';

/// An option strategy's profit/loss against the underlying's price: the
/// expiry payoff (green above zero, red below), breakevens, max
/// profit/loss, the current spot, and optionally the strategy's value
/// today (Black-Scholes) and the ±1σ expected move.
///
/// ```dart
/// OptionPayoffChart2D(
///   spot: 24480,
///   daysToExpiry: 6,
///   volatility: 0.13,
///   legs: [
///     OptionLeg.call(strike: 24500, premium: 182, quantity: -1, lotSize: 75),
///     OptionLeg.put(strike: 24500, premium: 168, quantity: -1, lotSize: 75),
///     OptionLeg.call(strike: 24800, premium: 64, quantity: 1, lotSize: 75),
///     OptionLeg.put(strike: 24200, premium: 58, quantity: 1, lotSize: 75),
///   ],
/// )
/// ```
///
/// Hover (or tap) to read the P&L at any price.
class OptionPayoffChart2D extends StatefulWidget {
  final List<OptionLeg> legs;

  /// Current price of the underlying.
  final double spot;

  /// Price range shown; defaults to the strikes and spot ±[rangePercent].
  final double? minPrice;
  final double? maxPrice;
  final double rangePercent;

  /// Days to the (nearest) expiry — enables the "today" curve and the
  /// expected-move band.
  final double? daysToExpiry;

  /// Volatility for legs without their own [OptionLeg.iv] (0.15 = 15%).
  final double volatility;
  final double riskFreeRate;
  final bool showTodayCurve;
  final bool showExpectedMove;
  final bool showSummary;
  final String? title;
  final String? subtitle;
  final String emptyStateMessage;
  final Color profitColor;
  final Color lossColor;

  /// Today curve and spot marker color; defaults to the theme's axis color.
  final Color? todayColor;
  final String Function(double price) priceFormatter;
  final String Function(double pnl) pnlFormatter;
  final bool enableAnimation;
  final Duration animationDuration;

  /// Custom tooltip for the hovered price.
  final Widget Function(BuildContext context, double price, double expiryPnl, double? todayPnl)? tooltipBuilder;
  final ChartController? controller;

  const OptionPayoffChart2D({
    super.key,
    required this.legs,
    required this.spot,
    this.minPrice,
    this.maxPrice,
    this.rangePercent = 0.06,
    this.daysToExpiry,
    this.volatility = 0.15,
    this.riskFreeRate = 0.0,
    this.showTodayCurve = true,
    this.showExpectedMove = true,
    this.showSummary = true,
    this.title,
    this.subtitle,
    this.emptyStateMessage = 'Add a leg to see the payoff',
    this.profitColor = const Color(0xFF26A69A),
    this.lossColor = const Color(0xFFEF5350),
    this.todayColor,
    this.priceFormatter = Cartesian2DAxes.formatNumber,
    this.pnlFormatter = _signed,
    this.enableAnimation = true,
    this.animationDuration = const Duration(milliseconds: 600),
    this.tooltipBuilder,
    this.controller,
  });

  static String _signed(double v) {
    final s = Cartesian2DAxes.formatNumber(double.parse(v.abs().toStringAsFixed(0)));
    return v > 0.5 ? '+$s' : (v < -0.5 ? '-$s' : '0');
  }

  @override
  State<OptionPayoffChart2D> createState() => _OptionPayoffChart2DState();
}

class _OptionPayoffChart2DState extends State<OptionPayoffChart2D> with ChartControllerMixin<OptionPayoffChart2D> {
  @override
  ChartController? controllerOf(OptionPayoffChart2D widget) => widget.controller;

  @override
  void resetZoom() {}

  (double, double) get _priceRange {
    final w = widget;
    final strikes = [for (final l in w.legs) if (l.type != OptionType.underlying) l.strike];
    var lo = math.min(w.spot, strikes.isEmpty ? w.spot : strikes.reduce(math.min));
    var hi = math.max(w.spot, strikes.isEmpty ? w.spot : strikes.reduce(math.max));
    lo = math.min(lo, w.spot * (1 - w.rangePercent));
    hi = math.max(hi, w.spot * (1 + w.rangePercent));
    final pad = (hi - lo) * 0.08;
    return (w.minPrice ?? math.max(0, lo - pad), w.maxPrice ?? hi + pad);
  }

  bool get _hasToday => widget.showTodayCurve && widget.daysToExpiry != null && widget.daysToExpiry! > 0;

  double? _today(double s) => _hasToday
      ? OptionMath.payoffBeforeExpiry(widget.legs, s,
          daysToExpiry: widget.daysToExpiry!, volatility: widget.volatility, rate: widget.riskFreeRate)
      : null;

  /// Calendar spreads: legs expiring later still have time value at the
  /// nearest expiry, so the "expiry" curve values them with Black-Scholes.
  double _expiry(double s) {
    final legs = widget.legs;
    final nearest = legs.map((l) => l.daysToExpiry).whereType<double>().fold<double?>(null, (m, d) => m == null ? d : math.min(m, d));
    final mixed = nearest != null && legs.any((l) => l.type != OptionType.underlying && (l.daysToExpiry ?? nearest) > nearest);
    if (!mixed) return OptionMath.payoffAtExpiry(legs, s);
    return OptionMath.payoffBeforeExpiry(legs, s,
        daysToExpiry: widget.daysToExpiry ?? nearest, daysElapsed: nearest, volatility: widget.volatility, rate: widget.riskFreeRate);
  }

  bool get _calendar {
    final d = {for (final l in widget.legs) if (l.type != OptionType.underlying) l.daysToExpiry ?? widget.daysToExpiry};
    return d.length > 1;
  }

  /// Sample points: range ends, every strike in range, and enough in
  /// between for the curved today line.
  List<double> _samples((double, double) range) {
    final (lo, hi) = range;
    const n = 160;
    return {
      for (int i = 0; i <= n; i++) lo + (hi - lo) * i / n,
      for (final l in widget.legs)
        if (l.strike > lo && l.strike < hi) l.strike,
    }.toList()
      ..sort();
  }

  _PayoffGeometry _geometry(Size size, ChartTheme theme) {
    final range = _priceRange;
    final xs = _samples(range);
    final expiry = [for (final s in xs) _expiry(s)];
    final today = _hasToday ? [for (final s in xs) _today(s)!] : null;
    var lo = expiry.reduce(math.min), hi = expiry.reduce(math.max);
    if (today != null) {
      lo = math.min(lo, today.reduce(math.min));
      hi = math.max(hi, today.reduce(math.max));
    }
    lo = math.min(lo, 0);
    hi = math.max(hi, 0);
    if (lo == hi) {
      lo -= 1;
      hi += 1;
    }
    final pad = (hi - lo) * 0.08;
    final (minY, maxY) = Cartesian2DAxes.niceExtent(lo - pad, hi + pad);
    final yTicks = Cartesian2DAxes.niceTicks(minY, maxY);
    // Left margin wide enough for the widest P&L label.
    final widest = yTicks
        .map((t) => layoutChartText(widget.pnlFormatter(t), color: theme.tickTextColor, fontSize: theme.tickFontSize).width)
        .fold(0.0, math.max);
    final top = widget.showSummary ? 34.0 : 12.0;
    final base = Cartesian2DAxes.computePlotArea(size, leftPad: math.max(40, widest + 12), rightPad: 14);
    final plot = Rect.fromLTRB(base.left, top, base.right, math.max(top + 1, base.bottom + 18));
    final axes = Cartesian2DAxes(plotArea: plot, minX: range.$1, maxX: range.$2, minY: minY, maxY: maxY, theme: theme);
    return _PayoffGeometry(axes, xs, expiry, today, yTicks);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    final w = widget;
    if (w.legs.isEmpty) {
      return ChartFrame(
        boundaryKey: chartBoundaryKey,
        title: w.title,
        subtitle: w.subtitle,
        plot: ChartEmptyState(message: w.emptyStateMessage),
      );
    }
    final breakevens = _calendar ? <double>[] : OptionMath.breakevens(w.legs);
    final maxProfit = _calendar ? null : OptionMath.maxProfit(w.legs);
    final maxLoss = _calendar ? null : OptionMath.maxLoss(w.legs);
    final net = OptionMath.netPremium(w.legs);
    String money(double? v) => v == null ? 'Unlimited' : w.pnlFormatter(v);
    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Option payoff chart', w.title, [
        w.legs.map((l) => l.description).join(', '),
        if (!_calendar) 'max profit ${money(maxProfit)}, max loss ${money(maxLoss)}',
        if (breakevens.isNotEmpty) 'breakevens ${breakevens.map(w.priceFormatter).join(' and ')}',
      ]),
      title: w.title,
      subtitle: w.subtitle,
      plot: HoverPlot<double>(
        enableAnimation: w.enableAnimation,
        animationDuration: w.animationDuration,
        animationKey: Object.hashAll(w.legs.map((l) => Object.hash(l.type, l.strike, l.quantity))),
        hitTest: (pos, size) {
          final g = _geometry(size, theme);
          final p = g.axes.plotArea;
          if (pos.dx < p.left || pos.dx > p.right || pos.dy < p.top - 4 || pos.dy > p.bottom + 4) return null;
          return g.axes.toDataX(pos.dx);
        },
        painterBuilder: (size, hover, progress) => _PayoffPainter(
          geometry: _geometry(size, theme),
          widget: w,
          theme: theme,
          hover: hover,
          hoverValues: hover == null ? null : (_expiry(hover), _today(hover)),
          breakevens: breakevens,
          summary: w.showSummary
              ? [
                  if (!_calendar) ('Max profit ', money(maxProfit), w.profitColor),
                  if (!_calendar) ('Max loss ', money(maxLoss), w.lossColor),
                  (net >= 0 ? 'Credit ' : 'Debit ', w.pnlFormatter(net.abs()).replaceFirst('+', ''), theme.axisColor),
                  if (breakevens.isNotEmpty) ('Breakeven ', breakevens.map(w.priceFormatter).join(' / '), theme.axisColor),
                ]
              : const [],
          progress: Curves.easeOutCubic.transform(progress),
        ),
        tooltipBuilder: (context, price, pointer, size) {
          final e = _expiry(price), t = _today(price);
          final change = (price - w.spot) / w.spot * 100;
          return positionChartTooltip(
            anchor: pointer,
            areaSize: size,
            cardWidth: 190,
            child: w.tooltipBuilder?.call(context, price, e, t) ??
                ChartTooltipCard(
                  theme: theme,
                  width: 190,
                  title: 'At ${w.priceFormatter(price)} (${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%)',
                  subtitle: t == null ? null : 'Today ${w.pnlFormatter(t)}',
                  value: 'Expiry ${w.pnlFormatter(e)}',
                ),
          );
        },
      ),
    );
  }
}

class _PayoffGeometry {
  final Cartesian2DAxes axes;
  final List<double> xs;
  final List<double> expiry;
  final List<double>? today;
  final List<double> yTicks;
  _PayoffGeometry(this.axes, this.xs, this.expiry, this.today, this.yTicks);
}

class _PayoffPainter extends CustomPainter {
  final _PayoffGeometry geometry;
  final OptionPayoffChart2D widget;
  final ChartTheme theme;
  final double? hover;
  final (double, double?)? hoverValues;
  final List<double> breakevens;
  final List<(String, String, Color)> summary;
  final double progress;

  _PayoffPainter({
    required this.geometry,
    required this.widget,
    required this.theme,
    required this.hover,
    required this.hoverValues,
    required this.breakevens,
    required this.summary,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;
    final a = g.axes;
    final plot = a.plotArea;
    final w = widget;

    // Expected move: ±1σ band around spot.
    final days = w.daysToExpiry;
    if (w.showExpectedMove && days != null && days > 0) {
      final (lo, hi) = OptionMath.expectedMove(w.spot, w.volatility, days);
      final band = Rect.fromLTRB(a.toScreenX(lo).clamp(plot.left, plot.right), plot.top,
          a.toScreenX(hi).clamp(plot.left, plot.right), plot.bottom);
      canvas.drawRect(band, Paint()..color = theme.crosshairColor.withValues(alpha: theme.crosshairColor.a * 0.08));
      a.drawLabel(canvas, '±1σ', Offset(band.left + 4, plot.bottom - 4), alignBottom: true, color: theme.subtitleColor);
    }

    a.drawGridAndAxes(canvas, yTicks: g.yTicks, yFormatter: w.pnlFormatter);
    final xTicks = Cartesian2DAxes.niceTicks(a.minX, a.maxX, count: math.max(3, (plot.width / 90).floor()));
    a.drawXTicks(canvas, [
      for (final t in xTicks)
        if (t >= a.minX && t <= a.maxX) (a.toScreenX(t), w.priceFormatter(t)),
    ]);

    final zeroY = a.toScreenY(0);
    canvas.drawLine(Offset(plot.left, zeroY), Offset(plot.right, zeroY), Paint()
      ..color = theme.axisColor
      ..strokeWidth = 1);

    // Reveal: the curve grows out of the zero line.
    final pts = [
      for (int i = 0; i < g.xs.length; i++) Offset(a.toScreenX(g.xs[i]), zeroY + (a.toScreenY(g.expiry[i]) - zeroY) * progress),
    ];
    final line = Path()..addPolygon(pts, false);
    // Down to the zero line at both ends, so the fill is bounded by it.
    final area = Path()..addPolygon([Offset(pts.first.dx, zeroY), ...pts, Offset(pts.last.dx, zeroY)], true);
    for (final (rect, color) in [
      (Rect.fromLTRB(plot.left, plot.top, plot.right, zeroY), w.profitColor),
      (Rect.fromLTRB(plot.left, zeroY, plot.right, plot.bottom), w.lossColor),
    ]) {
      canvas.save();
      canvas.clipRect(rect);
      canvas.drawPath(area, Paint()..color = color.withValues(alpha: color.a * 0.18));
      canvas.drawPath(line, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..color = color);
      canvas.restore();
    }

    // Today (T+0) curve.
    final today = g.today;
    final todayColor = w.todayColor ?? theme.axisColor;
    if (today != null) {
      final tp = Path();
      for (int i = 0; i < g.xs.length; i++) {
        final p = Offset(a.toScreenX(g.xs[i]), zeroY + (a.toScreenY(today[i]) - zeroY) * progress);
        i == 0 ? tp.moveTo(p.dx, p.dy) : tp.lineTo(p.dx, p.dy);
      }
      canvas.save();
      canvas.clipRect(plot);
      canvas.drawPath(tp, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = todayColor.withValues(alpha: todayColor.a * 0.75));
      canvas.restore();
    }

    // Breakevens on the zero line.
    for (final b in breakevens) {
      if (b < a.minX || b > a.maxX) continue;
      final p = Offset(a.toScreenX(b), zeroY);
      canvas.drawCircle(p, 4, Paint()..color = theme.tooltipBackgroundColor);
      canvas.drawCircle(p, 4, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = theme.axisColor);
      a.drawLabel(canvas, w.priceFormatter(b), p + const Offset(5, 4), color: theme.subtitleColor);
    }

    // Spot.
    final sx = a.toScreenX(w.spot);
    if (sx >= plot.left && sx <= plot.right) {
      a.dashedLine(canvas, Offset(sx, plot.top), Offset(sx, plot.bottom), Paint()
        ..color = todayColor
        ..strokeWidth = 1);
      a.drawLabel(canvas, 'Spot ${w.priceFormatter(w.spot)}', Offset(sx + 4, plot.top + 2), color: todayColor);
    }

    // Summary line above the plot.
    var x = plot.left;
    for (final (label, value, color) in summary) {
      final l = layoutChartText(label, color: theme.subtitleColor, fontSize: 11, fontWeight: FontWeight.w500, fontFamily: theme.fontFamily);
      final v = layoutChartText(value, color: color, fontSize: 11, fontWeight: FontWeight.w700, fontFamily: theme.fontFamily);
      if (x + l.width + v.width > plot.right + 10 && x > plot.left) break;
      l.paint(canvas, Offset(x, 8));
      v.paint(canvas, Offset(x + l.width, 8));
      x += l.width + v.width + 16;
    }

    // Hover: crosshair and dots on both curves.
    final h = hover, hv = hoverValues;
    if (h != null && hv != null) {
      final hx = a.toScreenX(h);
      a.dashedLine(canvas, Offset(hx, plot.top), Offset(hx, plot.bottom), Paint()
        ..color = theme.crosshairColor
        ..strokeWidth = 1);
      final ey = a.toScreenY(hv.$1);
      canvas.drawCircle(Offset(hx, ey), 4.5, Paint()..color = hv.$1 >= 0 ? w.profitColor : w.lossColor);
      if (hv.$2 != null) canvas.drawCircle(Offset(hx, a.toScreenY(hv.$2!)), 3.5, Paint()..color = todayColor);
    }
  }

  @override
  bool shouldRepaint(covariant _PayoffPainter old) => true;
}
