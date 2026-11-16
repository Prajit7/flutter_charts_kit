import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme.dart';
import 'cartesian_axes.dart';
import 'chart_chrome.dart';
import 'common.dart';
import 'controller.dart';
import 'hover_plot.dart';
import 'legend.dart';
import 'models.dart';


// ---------------------------------------------------------------------------
// Bump chart
// ---------------------------------------------------------------------------

/// A hovered point of a [BumpChart2D]: (series index, period index).
typedef BumpHit = (int series, int period);

/// A bump chart: rankings over time — who's first, who overtook whom.
/// Each series is ranked per period by its value (highest = 1 unless
/// [higherIsBetter] is false), and drawn as a smooth line between ranks.
///
/// ```dart
/// BumpChart2D(
///   periods: ['2022', '2023', '2024', '2025'],
///   series: [
///     CategorySeries(name: 'Chrome', color: Colors.blue, values: [62, 64, 65, 66]),
///     CategorySeries(name: 'Safari', color: Colors.teal, values: [19, 18, 18, 17]),
///     ...
///   ],
/// )
/// ```
class BumpChart2D extends StatefulWidget {
  final List<String> periods;

  /// One value per period; NaN for "not ranked" that period.
  final List<CategorySeries> series;
  final bool higherIsBetter;
  final String? title;
  final String? subtitle;
  final String emptyStateMessage;
  final String Function(double value) valueFormatter;
  final bool enableAnimation;
  final ChartController? controller;
  final void Function(String series, String period, int rank, double value)? onPointTap;

  const BumpChart2D({
    super.key,
    required this.periods,
    required this.series,
    this.higherIsBetter = true,
    this.title,
    this.subtitle,
    this.emptyStateMessage = 'No rankings',
    this.valueFormatter = Cartesian2DAxes.formatNumber,
    this.enableAnimation = true,
    this.controller,
    this.onPointTap,
  });

  /// Ranks per period: `ranks[series][period]`, 1-based, null if unranked.
  static List<List<int?>> rank(List<CategorySeries> series, int periods, {bool higherIsBetter = true}) {
    final out = [for (final _ in series) List<int?>.filled(periods, null)];
    for (int p = 0; p < periods; p++) {
      final idx = [
        for (int s = 0; s < series.length; s++)
          if (p < series[s].values.length && series[s].values[p].isFinite) s,
      ]..sort((a, b) {
          final c = series[a].values[p].compareTo(series[b].values[p]);
          return higherIsBetter ? -c : c;
        });
      for (int r = 0; r < idx.length; r++) {
        out[idx[r]][p] = r + 1;
      }
    }
    return out;
  }

  @override
  State<BumpChart2D> createState() => _BumpChart2DState();
}

class _BumpChart2DState extends State<BumpChart2D> with ChartControllerMixin<BumpChart2D> {
  @override
  ChartController? controllerOf(BumpChart2D widget) => widget.controller;

  @override
  void resetZoom() {}

  /// (plot rect, label width left, label width right).
  Rect _plot(Size size, ChartTheme theme) {
    double widest = 0;
    for (final s in widget.series) {
      widest = math.max(widest, layoutChartText(s.name, color: theme.axisColor, fontSize: 11).width);
    }
    final side = math.min(size.width * 0.22, widest + 18);
    return Rect.fromLTRB(side, 10, size.width - side, size.height - 26);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    final w = widget;
    final n = w.periods.length;
    if (w.series.isEmpty || n == 0) {
      return ChartFrame(boundaryKey: chartBoundaryKey, title: w.title, subtitle: w.subtitle, plot: ChartEmptyState(message: w.emptyStateMessage));
    }
    final ranks = BumpChart2D.rank(w.series, n, higherIsBetter: w.higherIsBetter);
    final maxRank = ranks.expand((r) => r).whereType<int>().fold(1, math.max);
    double xOf(Rect p, int i) => n == 1 ? p.center.dx : p.left + p.width * i / (n - 1);
    double yOf(Rect p, int rank) => maxRank == 1 ? p.center.dy : p.top + (p.height) * (rank - 1) / (maxRank - 1);
    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Bump chart', w.title, [
        for (int s = 0; s < w.series.length; s++)
          '${w.series[s].name}: rank ${ranks[s].first ?? '–'} in ${w.periods.first} to ${ranks[s].last ?? '–'} in ${w.periods.last}',
      ]),
      title: w.title,
      subtitle: w.subtitle,
      plot: HoverPlot<BumpHit>(
        enableAnimation: w.enableAnimation,
        hitTest: (pos, size) {
          final p = _plot(size, theme);
          BumpHit? best;
          var bestD = 14.0;
          for (int s = 0; s < w.series.length; s++) {
            for (int i = 0; i < n; i++) {
              final r = ranks[s][i];
              if (r == null) continue;
              final d = (Offset(xOf(p, i), yOf(p, r)) - pos).distance;
              if (d < bestD) {
                bestD = d;
                best = (s, i);
              }
            }
          }
          // Between points: the nearest line in this period gap.
          if (best == null && pos.dx >= p.left && pos.dx <= p.right && n > 1) {
            final i = ((pos.dx - p.left) / p.width * (n - 1)).floor().clamp(0, n - 2);
            for (int s = 0; s < w.series.length; s++) {
              final a = ranks[s][i], b = ranks[s][i + 1];
              if (a == null || b == null) continue;
              final t = ((pos.dx - xOf(p, i)) / (xOf(p, i + 1) - xOf(p, i))).clamp(0.0, 1.0);
              final e = t * t * (3 - 2 * t); // the curve's smoothstep
              final y = yOf(p, a) + (yOf(p, b) - yOf(p, a)) * e;
              if ((y - pos.dy).abs() < 6) best = (s, t < 0.5 ? i : i + 1);
            }
          }
          return best;
        },
        onTap: (h) {
          final r = ranks[h.$1][h.$2];
          if (r != null) w.onPointTap?.call(w.series[h.$1].name, w.periods[h.$2], r, w.series[h.$1].values[h.$2]);
        },
        painterBuilder: (size, hover, progress) => _BumpPainter(
          widget: w,
          ranks: ranks,
          plot: _plot(size, theme),
          xOf: xOf,
          yOf: yOf,
          theme: theme,
          hover: hover,
          progress: Curves.easeOutCubic.transform(progress),
        ),
        tooltipBuilder: (context, h, pointer, size) {
          final s = w.series[h.$1];
          final r = ranks[h.$1][h.$2];
          final prev = h.$2 > 0 ? ranks[h.$1][h.$2 - 1] : null;
          final move = r == null || prev == null || prev == r ? '' : (r < prev ? ' (▲${prev - r})' : ' (▼${r - prev})');
          return positionChartTooltip(
            anchor: pointer,
            areaSize: size,
            cardWidth: 170,
            child: ChartTooltipCard(
              theme: theme,
              width: 170,
              title: '${s.name} · ${w.periods[h.$2]}',
              subtitle: h.$2 < s.values.length ? w.valueFormatter(s.values[h.$2]) : null,
              value: r == null ? 'Unranked' : '#$r$move',
            ),
          );
        },
      ),
    );
  }
}

class _BumpPainter extends CustomPainter {
  final BumpChart2D widget;
  final List<List<int?>> ranks;
  final Rect plot;
  final double Function(Rect, int) xOf;
  final double Function(Rect, int) yOf;
  final ChartTheme theme;
  final BumpHit? hover;
  final double progress;

  _BumpPainter({
    required this.widget,
    required this.ranks,
    required this.plot,
    required this.xOf,
    required this.yOf,
    required this.theme,
    required this.hover,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = widget;
    final n = w.periods.length;
    // Period labels.
    for (int i = 0; i < n; i++) {
      final tp = layoutChartText(w.periods[i], color: theme.tickTextColor, fontSize: theme.tickFontSize, fontFamily: theme.fontFamily);
      tp.paint(canvas, Offset(xOf(plot, i) - tp.width / 2, plot.bottom + 10));
      canvas.drawLine(Offset(xOf(plot, i), plot.top - 6), Offset(xOf(plot, i), plot.bottom + 6), Paint()
        ..color = theme.gridColor
        ..strokeWidth = 1);
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, plot.left + (plot.width + 40) * progress, size.height));
    final focus = hover?.$1;
    // Dimmed series first, the hovered one last (on top).
    final order = [for (int s = 0; s < w.series.length; s++) if (s != focus) s, if (focus != null) focus];
    final dotR = math.min(11.0, math.max(6.0, plot.height / math.max(1, ranks.expand((r) => r).whereType<int>().fold(1, math.max)) / 3));
    for (final s in order) {
      final series = w.series[s];
      final dim = focus != null && s != focus;
      final color = dim ? series.color.withValues(alpha: series.color.a * 0.2) : series.color;
      final path = Path();
      var started = false;
      Offset? prev;
      for (int i = 0; i < n; i++) {
        final r = ranks[s][i];
        if (r == null) {
          started = false;
          prev = null;
          continue;
        }
        final pt = Offset(xOf(plot, i), yOf(plot, r));
        if (!started || prev == null) {
          path.moveTo(pt.dx, pt.dy);
          started = true;
        } else {
          final mx = (prev.dx + pt.dx) / 2;
          path.cubicTo(mx, prev.dy, mx, pt.dy, pt.dx, pt.dy);
        }
        prev = pt;
      }
      canvas.drawPath(path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s == focus ? 5 : 3.5
        ..strokeCap = StrokeCap.round
        ..color = color);
      for (int i = 0; i < n; i++) {
        final r = ranks[s][i];
        if (r == null) continue;
        final pt = Offset(xOf(plot, i), yOf(plot, r));
        canvas.drawCircle(pt, dotR, Paint()..color = color);
        if (!dim && dotR >= 7) {
          final tp = layoutChartText('$r', color: contrastingTextColor(series.color), fontSize: dotR * 0.95, fontFamily: theme.fontFamily);
          tp.paint(canvas, pt - Offset(tp.width / 2, tp.height / 2));
        }
      }
    }
    canvas.restore();
    // Names at both ends.
    for (int s = 0; s < w.series.length; s++) {
      final dim = focus != null && s != focus;
      final color = dim ? theme.tickTextColor.withValues(alpha: 0.4) : w.series[s].color;
      final first = ranks[s].indexWhere((r) => r != null), last = ranks[s].lastIndexWhere((r) => r != null);
      if (first < 0) continue;
      final a = layoutChartText(w.series[s].name, color: color, fontSize: 11, fontWeight: FontWeight.w700, fontFamily: theme.fontFamily, maxWidth: plot.left - 14);
      a.paint(canvas, Offset(xOf(plot, first) - dotR - 6 - a.width, yOf(plot, ranks[s][first]!) - a.height / 2));
      if (progress >= 0.99) {
        final b = layoutChartText(w.series[s].name, color: color, fontSize: 11, fontWeight: FontWeight.w700, fontFamily: theme.fontFamily, maxWidth: size.width - plot.right - 14);
        b.paint(canvas, Offset(xOf(plot, last) + dotR + 6, yOf(plot, ranks[s][last]!) - b.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BumpPainter old) => true;
}

// ---------------------------------------------------------------------------
// Slope chart
// ---------------------------------------------------------------------------

/// One item of a [SlopeChart2D].
class SlopeItem {
  final String label;
  final double start;
  final double end;

  /// Defaults to green for rises and red for falls.
  final Color? color;

  const SlopeItem({required this.label, required this.start, required this.end, this.color});

  double get change => end - start;
}

/// A slope chart: before vs after for each item, as lines between two
/// axes — steep lines are big changes, crossings are reversals of order.
///
/// ```dart
/// SlopeChart2D(
///   startLabel: '2024', endLabel: '2025',
///   items: [SlopeItem(label: 'North', start: 42, end: 55), ...],
/// )
/// ```
class SlopeChart2D extends StatefulWidget {
  final List<SlopeItem> items;
  final String startLabel;
  final String endLabel;
  final String? title;
  final String? subtitle;
  final String emptyStateMessage;
  final Color riseColor;
  final Color fallColor;
  final String Function(double value) valueFormatter;
  final bool enableAnimation;
  final ChartController? controller;
  final ValueChanged<SlopeItem>? onItemTap;

  const SlopeChart2D({
    super.key,
    required this.items,
    this.startLabel = 'Before',
    this.endLabel = 'After',
    this.title,
    this.subtitle,
    this.emptyStateMessage = 'No data',
    this.riseColor = const Color(0xFF26A69A),
    this.fallColor = const Color(0xFFEF5350),
    this.valueFormatter = Cartesian2DAxes.formatNumber,
    this.enableAnimation = true,
    this.controller,
    this.onItemTap,
  });

  @override
  State<SlopeChart2D> createState() => _SlopeChart2DState();
}

class _SlopeChart2DState extends State<SlopeChart2D> with ChartControllerMixin<SlopeChart2D> {
  @override
  ChartController? controllerOf(SlopeChart2D widget) => widget.controller;

  @override
  void resetZoom() {}

  (Rect, double, double) _geometry(Size size) {
    final w = widget;
    final values = [for (final i in w.items) ...[i.start, i.end]];
    var lo = values.reduce(math.min), hi = values.reduce(math.max);
    if (lo == hi) {
      lo -= 1;
      hi += 1;
    }
    final pad = (hi - lo) * 0.06;
    final side = math.min(size.width * 0.3, 150.0);
    return (Rect.fromLTRB(side, 30, size.width - side, size.height - 12), lo - pad, hi + pad);
  }

  /// Label y positions, nudged apart so they don't overlap.
  static List<double> _spread(List<double> ys, double gap, double top, double bottom) {
    final order = List.generate(ys.length, (i) => i)..sort((a, b) => ys[a].compareTo(ys[b]));
    final out = [...ys];
    for (int k = 1; k < order.length; k++) {
      final prev = out[order[k - 1]];
      if (out[order[k]] < prev + gap) out[order[k]] = prev + gap;
    }
    // If pushed past the bottom, shift everything back up.
    if (order.isNotEmpty && out[order.last] > bottom) {
      out[order.last] = bottom;
      for (int k = order.length - 2; k >= 0; k--) {
        final next = out[order[k + 1]];
        if (out[order[k]] > next - gap) out[order[k]] = next - gap;
      }
    }
    for (int k = 0; k < out.length; k++) {
      out[k] = math.max(out[k], top);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    final w = widget;
    if (w.items.isEmpty) {
      return ChartFrame(boundaryKey: chartBoundaryKey, title: w.title, subtitle: w.subtitle, plot: ChartEmptyState(message: w.emptyStateMessage));
    }
    Color colorOf(SlopeItem i) => i.color ?? (i.change >= 0 ? w.riseColor : w.fallColor);
    double y(Rect p, double lo, double hi, double v) => p.bottom - (v - lo) / (hi - lo) * p.height;
    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Slope chart', w.title, [
        for (final i in w.items) '${i.label}: ${w.valueFormatter(i.start)} to ${w.valueFormatter(i.end)}',
      ]),
      title: w.title,
      subtitle: w.subtitle,
      plot: HoverPlot<int>(
        enableAnimation: w.enableAnimation,
        hitTest: (pos, size) {
          final (p, lo, hi) = _geometry(size);
          int? best;
          var bestD = 8.0;
          for (int k = 0; k < w.items.length; k++) {
            final a = Offset(p.left, y(p, lo, hi, w.items[k].start)), b = Offset(p.right, y(p, lo, hi, w.items[k].end));
            final ab = b - a;
            final t = (((pos - a).dx * ab.dx + (pos - a).dy * ab.dy) / ab.distanceSquared).clamp(0.0, 1.0);
            final d = (pos - (a + ab * t)).distance;
            if (d < bestD) {
              bestD = d;
              best = k;
            }
          }
          if (best != null) return best;
          // Or over a label column.
          if (pos.dx < p.left || pos.dx > p.right) {
            final left = pos.dx < p.left;
            final ys = _spread([for (final i in w.items) y(p, lo, hi, left ? i.start : i.end)], 15, p.top, p.bottom);
            for (int k = 0; k < ys.length; k++) {
              if ((ys[k] - pos.dy).abs() < 7.5) return k;
            }
          }
          return null;
        },
        onTap: (k) => w.onItemTap?.call(w.items[k]),
        painterBuilder: (size, hover, progress) {
          final (p, lo, hi) = _geometry(size);
          return _SlopePainter(
            widget: w,
            plot: p,
            y: (v) => y(p, lo, hi, v),
            colorOf: colorOf,
            startLabelYs: _spread([for (final i in w.items) y(p, lo, hi, i.start)], 15, p.top, p.bottom),
            endLabelYs: _spread([for (final i in w.items) y(p, lo, hi, i.end)], 15, p.top, p.bottom),
            theme: theme,
            hover: hover,
            progress: Curves.easeOutCubic.transform(progress),
          );
        },
        tooltipBuilder: (context, k, pointer, size) {
          final i = w.items[k];
          final pct = i.start == 0 ? null : i.change / i.start.abs() * 100;
          return positionChartTooltip(
            anchor: pointer,
            areaSize: size,
            cardWidth: 180,
            child: ChartTooltipCard(
              theme: theme,
              width: 180,
              title: i.label,
              subtitle: '${w.startLabel} ${w.valueFormatter(i.start)} → ${w.endLabel} ${w.valueFormatter(i.end)}',
              value: '${i.change >= 0 ? '+' : ''}${w.valueFormatter(i.change)}'
                  '${pct == null ? '' : ' (${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%)'}',
            ),
          );
        },
      ),
    );
  }
}

class _SlopePainter extends CustomPainter {
  final SlopeChart2D widget;
  final Rect plot;
  final double Function(double) y;
  final Color Function(SlopeItem) colorOf;
  final List<double> startLabelYs, endLabelYs;
  final ChartTheme theme;
  final int? hover;
  final double progress;

  _SlopePainter({
    required this.widget,
    required this.plot,
    required this.y,
    required this.colorOf,
    required this.startLabelYs,
    required this.endLabelYs,
    required this.theme,
    required this.hover,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = widget;
    final axis = Paint()
      ..color = theme.axisColor
      ..strokeWidth = 1.2;
    canvas.drawLine(plot.topLeft, plot.bottomLeft, axis);
    canvas.drawLine(plot.topRight, plot.bottomRight, axis);
    for (final (label, x) in [(w.startLabel, plot.left), (w.endLabel, plot.right)]) {
      final tp = layoutChartText(label, color: theme.axisColor, fontSize: 12, fontWeight: FontWeight.w800, fontFamily: theme.fontFamily);
      tp.paint(canvas, Offset(x - tp.width / 2, plot.top - tp.height - 10));
    }
    for (int k = 0; k < w.items.length; k++) {
      final i = w.items[k];
      final dim = hover != null && hover != k;
      final base = colorOf(i);
      final color = dim ? base.withValues(alpha: base.a * 0.2) : base;
      final a = Offset(plot.left, y(i.start)), b0 = Offset(plot.right, y(i.end));
      final b = Offset.lerp(a, b0, progress)!;
      canvas.drawLine(a, b, Paint()
        ..color = color
        ..strokeWidth = hover == k ? 3.4 : 2.2
        ..strokeCap = StrokeCap.round);
      canvas.drawCircle(a, 4, Paint()..color = color);
      canvas.drawCircle(b, 4, Paint()..color = color);
      final textColor = dim ? theme.tickTextColor.withValues(alpha: 0.35) : theme.axisColor;
      final left = layoutChartText('${i.label}  ${w.valueFormatter(i.start)}',
          color: textColor, fontSize: 11, fontFamily: theme.fontFamily, maxWidth: plot.left - 12);
      left.paint(canvas, Offset(plot.left - 10 - left.width, startLabelYs[k] - left.height / 2));
      if (progress >= 0.99) {
        final right = layoutChartText('${w.valueFormatter(i.end)}  ${i.label}',
            color: dim ? textColor : base, fontSize: 11, fontWeight: FontWeight.w700, fontFamily: theme.fontFamily, maxWidth: size.width - plot.right - 12);
        right.paint(canvas, Offset(plot.right + 10, endLabelYs[k] - right.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SlopePainter old) => true;
}

// ---------------------------------------------------------------------------
// Marimekko
// ---------------------------------------------------------------------------

/// A hovered cell of a [MarimekkoChart2D]: (series, category).
typedef MarimekkoHit = (int series, int category);

/// A Marimekko (mosaic) chart: 100%-stacked columns whose widths are each
/// column's share of the grand total — market share by segment *and*
/// segment size in one picture.
///
/// ```dart
/// MarimekkoChart2D(
///   categories: ['Retail', 'SMB', 'Enterprise'],
///   series: [
///     CategorySeries(name: 'Us', color: Colors.indigo, values: [120, 80, 300]),
///     CategorySeries(name: 'Rival', color: Colors.orange, values: [200, 60, 150]),
///   ],
/// )
/// ```
class MarimekkoChart2D extends StatefulWidget {
  final List<String> categories;
  final List<CategorySeries> series;
  final String? title;
  final String? subtitle;
  final String emptyStateMessage;
  final bool showLegend;
  final ChartLegendPosition legendPosition;
  final bool showPercentLabels;
  final String Function(double value) valueFormatter;
  final bool enableAnimation;
  final ChartController? controller;
  final void Function(String series, String category, double value)? onCellTap;

  const MarimekkoChart2D({
    super.key,
    required this.categories,
    required this.series,
    this.title,
    this.subtitle,
    this.emptyStateMessage = 'No data',
    this.showLegend = true,
    this.legendPosition = ChartLegendPosition.bottom,
    this.showPercentLabels = true,
    this.valueFormatter = Cartesian2DAxes.formatNumber,
    this.enableAnimation = true,
    this.controller,
    this.onCellTap,
  });

  @override
  State<MarimekkoChart2D> createState() => _MarimekkoChart2DState();
}

class _MarimekkoChart2DState extends State<MarimekkoChart2D> with ChartControllerMixin<MarimekkoChart2D> {
  @override
  ChartController? controllerOf(MarimekkoChart2D widget) => widget.controller;

  @override
  void resetZoom() {}

  double _v(int s, int c) {
    final vs = widget.series[s].values;
    return c < vs.length && vs[c].isFinite ? math.max(0, vs[c]) : 0;
  }

  /// Cell rects by (series, category), in a plot with %-axis on the left.
  (Rect, Map<MarimekkoHit, Rect>, List<double>) _layout(Size size) {
    final w = widget;
    final plot = Rect.fromLTRB(42, 8, size.width - 8, size.height - 34);
    final totals = [for (int c = 0; c < w.categories.length; c++) [for (int s = 0; s < w.series.length; s++) _v(s, c)].fold(0.0, (a, b) => a + b)];
    final grand = totals.fold(0.0, (a, b) => a + b);
    final cells = <MarimekkoHit, Rect>{};
    var x = plot.left;
    const gap = 2.0;
    for (int c = 0; c < w.categories.length; c++) {
      final width = grand == 0 ? 0.0 : plot.width * totals[c] / grand;
      var y = plot.bottom;
      for (int s = 0; s < w.series.length; s++) {
        final h = totals[c] == 0 ? 0.0 : plot.height * _v(s, c) / totals[c];
        cells[(s, c)] = Rect.fromLTRB(x + gap / 2, y - h, x + math.max(gap / 2, width - gap / 2), y);
        y -= h;
      }
      x += width;
    }
    return (plot, cells, totals);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    final w = widget;
    final grand = [for (int s = 0; s < w.series.length; s++) for (int c = 0; c < w.categories.length; c++) _v(s, c)].fold(0.0, (a, b) => a + b);
    if (w.series.isEmpty || w.categories.isEmpty || grand <= 0) {
      return ChartFrame(boundaryKey: chartBoundaryKey, title: w.title, subtitle: w.subtitle, plot: ChartEmptyState(message: w.emptyStateMessage));
    }
    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Marimekko chart', w.title, [
        for (int c = 0; c < w.categories.length; c++)
          '${w.categories[c]}: ${[for (int s = 0; s < w.series.length; s++) _v(s, c)].fold(0.0, (a, b) => a + b) / grand * 100 ~/ 1}% of total',
      ]),
      title: w.title,
      subtitle: w.subtitle,
      legendPosition: w.legendPosition,
      legendBuilder: w.showLegend
          ? (direction) => Chart2DLegend(direction: direction, entries: [for (final s in w.series) LegendEntry(label: s.name, color: s.color)])
          : null,
      plot: HoverPlot<MarimekkoHit>(
        enableAnimation: w.enableAnimation,
        hitTest: (pos, size) {
          final (_, cells, _) = _layout(size);
          for (final e in cells.entries) {
            if (e.value.contains(pos)) return e.key;
          }
          return null;
        },
        onTap: (h) => w.onCellTap?.call(w.series[h.$1].name, w.categories[h.$2], _v(h.$1, h.$2)),
        painterBuilder: (size, hover, progress) {
          final (plot, cells, totals) = _layout(size);
          return _MarimekkoPainter(widget: w, plot: plot, cells: cells, totals: totals, grand: grand, theme: theme, hover: hover, progress: progress);
        },
        tooltipBuilder: (context, h, pointer, size) {
          final (_, _, totals) = _layout(size);
          final v = _v(h.$1, h.$2);
          return positionChartTooltip(
            anchor: pointer,
            areaSize: size,
            cardWidth: 190,
            child: ChartTooltipCard(
              theme: theme,
              width: 190,
              title: '${w.series[h.$1].name} · ${w.categories[h.$2]}',
              subtitle: '${(v / totals[h.$2] * 100).toStringAsFixed(1)}% of ${w.categories[h.$2]}\n'
                  '${(v / grand * 100).toStringAsFixed(1)}% of total',
              value: w.valueFormatter(v),
            ),
          );
        },
      ),
    );
  }
}

class _MarimekkoPainter extends CustomPainter {
  final MarimekkoChart2D widget;
  final Rect plot;
  final Map<MarimekkoHit, Rect> cells;
  final List<double> totals;
  final double grand;
  final ChartTheme theme;
  final MarimekkoHit? hover;
  final double progress;

  _MarimekkoPainter({
    required this.widget,
    required this.plot,
    required this.cells,
    required this.totals,
    required this.grand,
    required this.theme,
    required this.hover,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = widget;
    final t = Curves.easeOutCubic.transform(progress);
    for (int p = 0; p <= 100; p += 25) {
      final y = plot.bottom - plot.height * p / 100;
      canvas.drawLine(Offset(plot.left - 4, y), Offset(plot.left, y), Paint()..color = theme.axisColor);
      final tp = layoutChartText('$p%', color: theme.tickTextColor, fontSize: theme.tickFontSize, fontFamily: theme.fontFamily);
      tp.paint(canvas, Offset(plot.left - 7 - tp.width, y - tp.height / 2));
    }
    for (final e in cells.entries) {
      final (s, c) = e.key;
      final r0 = e.value;
      if (r0.width <= 0 || r0.height <= 0) continue;
      // Grow up from the baseline on entrance.
      final r = Rect.fromLTRB(r0.left, plot.bottom - (plot.bottom - r0.top) * t, r0.right, plot.bottom - (plot.bottom - r0.bottom) * t);
      final base = w.series[s].color;
      final dim = hover != null && hover != e.key;
      canvas.drawRect(r, Paint()..color = dim ? base.withValues(alpha: base.a * 0.45) : base);
      if (w.showPercentLabels && t > 0.98 && r.width > 34 && r.height > 16) {
        // A cell's height is its share of the column.
        final share = r0.height / plot.height * 100;
        final tp = layoutChartText('${share.round()}%', color: contrastingTextColor(base), fontSize: 10.5, fontFamily: theme.fontFamily);
        tp.paint(canvas, r.center - Offset(tp.width / 2, tp.height / 2));
      }
    }
    // Category labels under each column, with the column's share of total.
    for (int c = 0; c < w.categories.length; c++) {
      final col = cells[(0, c)];
      if (col == null || col.width < 4) continue;
      final tp = layoutChartText(w.categories[c], color: theme.axisColor, fontSize: 10.5, fontWeight: FontWeight.w700, fontFamily: theme.fontFamily, maxWidth: col.width + 2);
      tp.paint(canvas, Offset(col.center.dx - tp.width / 2, plot.bottom + 5));
      final share = layoutChartText('${(totals[c] / grand * 100).toStringAsFixed(0)}%', color: theme.tickTextColor, fontSize: 9.5, fontFamily: theme.fontFamily);
      if (share.width < col.width) share.paint(canvas, Offset(col.center.dx - share.width / 2, plot.bottom + 5 + tp.height));
    }
  }

  @override
  bool shouldRepaint(covariant _MarimekkoPainter old) => true;
}
