import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme.dart';
import 'cartesian_axes.dart';
import 'chart_chrome.dart';
import 'common.dart';
import 'controller.dart';
import 'hover_plot.dart';

/// One price level of an order book.
class DepthLevel {
  final double price;
  final double size;

  /// Number of orders at this level, if known (shown in the tooltip).
  final int? orders;

  const DepthLevel(this.price, this.size, {this.orders});
}

/// A hovered level of a [MarketDepthChart2D].
class DepthHit {
  final bool isBid;

  /// Index into the levels sorted outward from the spread (best first).
  final int index;
  final DepthLevel level;

  /// Total size from the best price up to and including this level.
  final double cumulative;

  const DepthHit(this.isBid, this.index, this.level, this.cumulative);

  @override
  bool operator ==(Object other) => other is DepthHit && other.isBid == isBid && other.index == index;

  @override
  int get hashCode => Object.hash(isBid, index);
}

/// Market depth: the order book as two stepped, cumulative areas — bids
/// (buyers) rising to the left of the spread, asks (sellers) to the right.
/// The steeper a side, the more liquidity close to the price; walls show
/// as cliffs.
///
/// ```dart
/// MarketDepthChart2D(
///   bids: [DepthLevel(24479.5, 300), DepthLevel(24479, 1200), ...],
///   asks: [DepthLevel(24480.5, 450), DepthLevel(24481, 900), ...],
/// )
/// ```
///
/// Levels can be in any order. Pass new lists as the book updates; the
/// chart redraws without replaying its entrance.
class MarketDepthChart2D extends StatefulWidget {
  final List<DepthLevel> bids;
  final List<DepthLevel> asks;

  /// How far each side extends from the mid price, as a fraction (0.01 =
  /// ±1%). Null shows every level.
  final double? priceRangeFraction;
  final String? title;
  final String? subtitle;
  final String emptyStateMessage;
  final Color bidColor;
  final Color askColor;
  final bool showSpread;
  final String Function(double price) priceFormatter;
  final String Function(double size) sizeFormatter;
  final bool enableAnimation;
  final Widget Function(BuildContext context, DepthHit hit)? tooltipBuilder;
  final ChartController? controller;

  const MarketDepthChart2D({
    super.key,
    required this.bids,
    required this.asks,
    this.priceRangeFraction,
    this.title,
    this.subtitle,
    this.emptyStateMessage = 'Order book is empty',
    this.bidColor = const Color(0xFF26A69A),
    this.askColor = const Color(0xFFEF5350),
    this.showSpread = true,
    this.priceFormatter = Cartesian2DAxes.formatNumber,
    this.sizeFormatter = Cartesian2DAxes.formatNumber,
    this.enableAnimation = true,
    this.tooltipBuilder,
    this.controller,
  });

  @override
  State<MarketDepthChart2D> createState() => _MarketDepthChart2DState();
}

/// One side, best price first, with running totals.
class _Side {
  final List<DepthLevel> levels;
  final List<double> cumulative;
  _Side(this.levels, this.cumulative);

  static _Side of(List<DepthLevel> levels, bool bids, double? limit) {
    final sorted = [
      for (final l in levels)
        if (l.size > 0 && l.price.isFinite && (limit == null || (bids ? l.price >= limit : l.price <= limit))) l,
    ]..sort((a, b) => bids ? b.price.compareTo(a.price) : a.price.compareTo(b.price));
    var total = 0.0;
    return _Side(sorted, [for (final l in sorted) total += l.size]);
  }

  double get total => cumulative.isEmpty ? 0 : cumulative.last;
}

class _MarketDepthChart2DState extends State<MarketDepthChart2D> with ChartControllerMixin<MarketDepthChart2D> {
  @override
  ChartController? controllerOf(MarketDepthChart2D widget) => widget.controller;

  @override
  void resetZoom() {}

  (_Side, _Side, double?) _sides() {
    final w = widget;
    final bestBid = w.bids.where((l) => l.size > 0).map((l) => l.price).fold<double?>(null, (m, p) => m == null ? p : math.max(m, p));
    final bestAsk = w.asks.where((l) => l.size > 0).map((l) => l.price).fold<double?>(null, (m, p) => m == null ? p : math.min(m, p));
    final mid = bestBid != null && bestAsk != null ? (bestBid + bestAsk) / 2 : (bestBid ?? bestAsk);
    final f = w.priceRangeFraction;
    return (
      _Side.of(w.bids, true, f == null || mid == null ? null : mid * (1 - f)),
      _Side.of(w.asks, false, f == null || mid == null ? null : mid * (1 + f)),
      mid,
    );
  }

  Cartesian2DAxes _axes(Size size, _Side bids, _Side asks, double mid, ChartTheme theme) {
    final lowest = bids.levels.isEmpty ? mid : bids.levels.last.price;
    final highest = asks.levels.isEmpty ? mid : asks.levels.last.price;
    // Symmetric around mid so the spread sits in the middle.
    final half = math.max(math.max(mid - lowest, highest - mid), mid.abs() * 1e-4 + 1e-9);
    final maxY = math.max(bids.total, asks.total);
    final (_, top) = Cartesian2DAxes.niceExtent(0, maxY == 0 ? 1 : maxY * 1.08);
    final ticks = Cartesian2DAxes.niceTicks(0, top);
    final widest = ticks
        .map((t) => layoutChartText(widget.sizeFormatter(t), color: theme.tickTextColor, fontSize: theme.tickFontSize).width)
        .fold(0.0, math.max);
    final base = Cartesian2DAxes.computePlotArea(size, leftPad: math.max(40, widest + 12), rightPad: 12);
    final plot = Rect.fromLTRB(base.left, widget.showSpread ? 30 : base.top, base.right, math.max(40, base.bottom + 18));
    return Cartesian2DAxes(plotArea: plot, minX: mid - half * 1.02, maxX: mid + half * 1.02, minY: 0, maxY: top, theme: theme);
  }

  DepthHit? _hit(Offset pos, Size size, ChartTheme theme) {
    final (bids, asks, mid) = _sides();
    if (mid == null) return null;
    final a = _axes(size, bids, asks, mid, theme);
    if (!a.plotArea.inflate(4).contains(pos)) return null;
    final price = a.toDataX(pos.dx);
    final isBid = price < mid;
    final side = isBid ? bids : asks;
    if (side.levels.isEmpty) return null;
    // The level whose step covers this price: the last one at or beyond it
    // (moving outward from the spread).
    var i = 0;
    for (int k = 0; k < side.levels.length; k++) {
      final p = side.levels[k].price;
      if (isBid ? p >= price : p <= price) i = k;
    }
    return DepthHit(isBid, i, side.levels[i], side.cumulative[i]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    final w = widget;
    final (bids, asks, mid) = _sides();
    if (mid == null) {
      return ChartFrame(
        boundaryKey: chartBoundaryKey,
        title: w.title,
        subtitle: w.subtitle,
        plot: ChartEmptyState(message: w.emptyStateMessage),
      );
    }
    final spread = bids.levels.isEmpty || asks.levels.isEmpty ? null : asks.levels.first.price - bids.levels.first.price;
    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Market depth chart', w.title, [
        'mid ${w.priceFormatter(mid)}',
        if (spread != null) 'spread ${w.priceFormatter(spread)}',
        'bids ${w.sizeFormatter(bids.total)} over ${bids.levels.length} levels',
        'asks ${w.sizeFormatter(asks.total)} over ${asks.levels.length} levels',
      ]),
      title: w.title,
      subtitle: w.subtitle,
      plot: HoverPlot<DepthHit>(
        enableAnimation: w.enableAnimation,
        // Replays only when the chart is first shown, not on book updates.
        animationKey: 'depth',
        hitTest: (pos, size) => _hit(pos, size, theme),
        painterBuilder: (size, hover, progress) => _DepthPainter(
          axes: _axes(size, bids, asks, mid, theme),
          bids: bids,
          asks: asks,
          mid: mid,
          spread: spread,
          widget: w,
          theme: theme,
          hover: hover,
          progress: Curves.easeOutCubic.transform(progress),
        ),
        tooltipBuilder: (context, hit, pointer, size) {
          final custom = w.tooltipBuilder;
          final notional = hit.isBid
              ? bids.levels.take(hit.index + 1).fold(0.0, (s, l) => s + l.price * l.size)
              : asks.levels.take(hit.index + 1).fold(0.0, (s, l) => s + l.price * l.size);
          final away = (hit.level.price - mid) / mid * 100;
          return positionChartTooltip(
            anchor: pointer,
            areaSize: size,
            cardWidth: 200,
            child: custom != null
                ? custom(context, hit)
                : ChartTooltipCard(
                    theme: theme,
                    width: 200,
                    title: '${hit.isBid ? 'Bid' : 'Ask'} ${w.priceFormatter(hit.level.price)} '
                        '(${away >= 0 ? '+' : ''}${away.toStringAsFixed(2)}%)',
                    subtitle: 'Size ${w.sizeFormatter(hit.level.size)}'
                        '${hit.level.orders == null ? '' : ' · ${hit.level.orders} orders'}\n'
                        'Value to here ${Cartesian2DAxes.formatNumber(double.parse(notional.toStringAsFixed(0)))}',
                    value: 'Total ${w.sizeFormatter(hit.cumulative)}',
                  ),
          );
        },
      ),
    );
  }
}

class _DepthPainter extends CustomPainter {
  final Cartesian2DAxes axes;
  final _Side bids, asks;
  final double mid;
  final double? spread;
  final MarketDepthChart2D widget;
  final ChartTheme theme;
  final DepthHit? hover;
  final double progress;

  _DepthPainter({
    required this.axes,
    required this.bids,
    required this.asks,
    required this.mid,
    required this.spread,
    required this.widget,
    required this.theme,
    required this.hover,
    required this.progress,
  });

  /// Stepped outline of one side, from the best price outward to the edge.
  List<Offset> _steps(_Side side, bool isBid) {
    final a = axes;
    final pts = <Offset>[];
    var prevY = a.toScreenY(0);
    for (int i = 0; i < side.levels.length; i++) {
      final x = a.toScreenX(side.levels[i].price);
      final y = a.toScreenY(side.cumulative[i] * progress);
      pts.add(Offset(x, prevY));
      pts.add(Offset(x, y));
      prevY = y;
    }
    if (pts.isNotEmpty) pts.add(Offset(isBid ? a.plotArea.left : a.plotArea.right, prevY));
    return pts;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final a = axes;
    final w = widget;
    final plot = a.plotArea;
    a.drawGridAndAxes(canvas, yTicks: Cartesian2DAxes.niceTicks(0, a.maxY), yFormatter: w.sizeFormatter);
    final xTicks = Cartesian2DAxes.niceTicks(a.minX, a.maxX, count: math.max(3, (plot.width / 90).floor()));
    a.drawXTicks(canvas, [
      for (final t in xTicks)
        if (t >= a.minX && t <= a.maxX) (a.toScreenX(t), w.priceFormatter(t)),
    ]);

    final zero = a.toScreenY(0);
    canvas.save();
    canvas.clipRect(plot);
    for (final (side, isBid, color) in [(bids, true, w.bidColor), (asks, false, w.askColor)]) {
      final pts = _steps(side, isBid);
      if (pts.isEmpty) continue;
      final line = Path()..addPolygon(pts, false);
      final area = Path()
        ..addPolygon([...pts, Offset(pts.last.dx, zero), Offset(pts.first.dx, zero)], true);
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: color.a * 0.45), color.withValues(alpha: color.a * 0.08)],
          ).createShader(Rect.fromLTRB(plot.left, plot.top, plot.right, zero)),
      );
      // Flat fill too, so SVG export (no gradients) still shows the areas.
      canvas.drawPath(area, Paint()..color = color.withValues(alpha: color.a * 0.06));
      canvas.drawPath(line, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = color);
    }

    // Mid line.
    final mx = a.toScreenX(mid);
    a.dashedLine(canvas, Offset(mx, plot.top), Offset(mx, plot.bottom), Paint()
      ..color = theme.crosshairColor
      ..strokeWidth = 1);

    // Hover: the level's step corner, and a guide down to the price axis.
    final h = hover;
    if (h != null) {
      final color = h.isBid ? w.bidColor : w.askColor;
      final p = Offset(a.toScreenX(h.level.price), a.toScreenY(h.cumulative));
      a.dashedLine(canvas, Offset(p.dx, p.dy), Offset(p.dx, plot.bottom), Paint()
        ..color = color
        ..strokeWidth = 1);
      a.dashedLine(canvas, Offset(plot.left, p.dy), p, Paint()
        ..color = color
        ..strokeWidth = 1);
      canvas.drawCircle(p, 4.5, Paint()..color = color);
      canvas.drawCircle(p, 4.5, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = theme.tooltipBackgroundColor);
    }
    canvas.restore();

    // Mid price and spread, above the plot.
    if (w.showSpread) {
      final s = spread;
      final text = s == null
          ? 'Mid ${w.priceFormatter(mid)}'
          : 'Mid ${w.priceFormatter(mid)}  ·  Spread ${w.priceFormatter(s)} (${(s / mid * 100).toStringAsFixed(3)}%)';
      final tp = layoutChartText(text, color: theme.axisColor, fontSize: 11, fontWeight: FontWeight.w700, fontFamily: theme.fontFamily);
      tp.paint(canvas, Offset((mx - tp.width / 2).clamp(plot.left, math.max(plot.left, plot.right - tp.width)), 8));
      final bidLabel = layoutChartText('Bids ${w.sizeFormatter(bids.total)}', color: w.bidColor, fontSize: 10, fontFamily: theme.fontFamily);
      final askLabel = layoutChartText('Asks ${w.sizeFormatter(asks.total)}', color: w.askColor, fontSize: 10, fontFamily: theme.fontFamily);
      bidLabel.paint(canvas, Offset(plot.left + 6, plot.top + 4));
      askLabel.paint(canvas, Offset(plot.right - askLabel.width - 6, plot.top + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _DepthPainter old) => true;
}
