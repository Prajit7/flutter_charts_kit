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
// Streamgraph
// ---------------------------------------------------------------------------

/// Where a [StreamgraphChart2D]'s layers are stacked from.
enum StreamBaseline {
  /// Centred on zero — the classic symmetric stream.
  silhouette,

  /// Minimises the layers' wiggle (Byron & Wattenberg): calmer for many layers.
  wiggle,

  /// A plain stacked area from zero.
  zero,
}

/// A streamgraph: stacked layers flowing around a centre line — how the
/// mix of many categories shifts over time (genres, topics, traffic
/// sources).
///
/// ```dart
/// StreamgraphChart2D(
///   labels: ['Jan', 'Feb', 'Mar', ...],
///   series: [CategorySeries(name: 'Rock', color: Colors.red, values: [...]), ...],
/// )
/// ```
///
/// Hover for every layer's value at that point.
class StreamgraphChart2D extends StatefulWidget {
  /// One label per point along the x-axis.
  final List<String> labels;

  /// One layer per series, one value per label.
  final List<CategorySeries> series;
  final StreamBaseline baseline;
  final String? title;
  final String? subtitle;
  final String emptyStateMessage;
  final bool showLegend;
  final ChartLegendPosition legendPosition;
  final String Function(double value) valueFormatter;
  final bool enableAnimation;
  final ChartController? controller;

  const StreamgraphChart2D({
    super.key,
    required this.labels,
    required this.series,
    this.baseline = StreamBaseline.silhouette,
    this.title,
    this.subtitle,
    this.emptyStateMessage = 'No data',
    this.showLegend = true,
    this.legendPosition = ChartLegendPosition.bottom,
    this.valueFormatter = Cartesian2DAxes.formatNumber,
    this.enableAnimation = true,
    this.controller,
  });

  /// Layer bounds `[layer][point] = (bottom, top)` for [baseline].
  static List<List<(double, double)>> stack(List<List<double>> values, StreamBaseline baseline) {
    final m = values.length;
    if (m == 0) return const [];
    final n = values.first.length;
    double v(int l, int i) => i < values[l].length && values[l][i].isFinite ? math.max(0, values[l][i]) : 0;
    final totals = [for (int i = 0; i < n; i++) [for (int l = 0; l < m; l++) v(l, i)].fold(0.0, (a, b) => a + b)];
    final g0 = List<double>.filled(n, 0);
    switch (baseline) {
      case StreamBaseline.zero:
        break;
      case StreamBaseline.silhouette:
        for (int i = 0; i < n; i++) {
          g0[i] = -totals[i] / 2;
        }
      case StreamBaseline.wiggle:
        // g0' = -(Σ (m - l + 0.5)·f_l') / Σ f, integrated from a centred start.
        g0[0] = -totals[0] / 2;
        for (int i = 1; i < n; i++) {
          double num = 0;
          for (int l = 0; l < m; l++) {
            num += (m - l - 0.5) * (v(l, i) - v(l, i - 1));
          }
          final denom = totals[i];
          g0[i] = g0[i - 1] - (denom == 0 ? 0 : num / denom);
        }
        // Re-centre the whole stream on zero.
        double mid = 0;
        for (int i = 0; i < n; i++) {
          mid += g0[i] + totals[i] / 2;
        }
        mid /= n;
        for (int i = 0; i < n; i++) {
          g0[i] -= mid;
        }
    }
    final out = <List<(double, double)>>[];
    final base = [...g0];
    for (int l = 0; l < m; l++) {
      out.add([for (int i = 0; i < n; i++) (base[i], base[i] + v(l, i))]);
      for (int i = 0; i < n; i++) {
        base[i] += v(l, i);
      }
    }
    return out;
  }

  @override
  State<StreamgraphChart2D> createState() => _StreamgraphChart2DState();
}

class _StreamgraphChart2DState extends State<StreamgraphChart2D> with ChartControllerMixin<StreamgraphChart2D> {
  final Set<String> _hidden = {};

  @override
  ChartController? controllerOf(StreamgraphChart2D widget) => widget.controller;

  @override
  void resetZoom() {}

  List<CategorySeries> get _visible => [for (final s in widget.series) if (!_hidden.contains(s.name)) s];

  (Rect, List<List<(double, double)>>, double, double) _geometry(Size size) {
    final layers = StreamgraphChart2D.stack([for (final s in _visible) s.values], widget.baseline);
    var lo = double.infinity, hi = -double.infinity;
    for (final l in layers) {
      for (final (a, b) in l) {
        lo = math.min(lo, a);
        hi = math.max(hi, b);
      }
    }
    if (!lo.isFinite) (lo, hi) = (0, 1);
    if (lo == hi) hi = lo + 1;
    final pad = (hi - lo) * 0.04;
    lo -= pad;
    hi += pad;
    return (Rect.fromLTRB(8, 8, size.width - 8, size.height - 24), layers, lo, hi);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    final w = widget;
    if (w.series.isEmpty || w.labels.length < 2) {
      return ChartFrame(boundaryKey: chartBoundaryKey, title: w.title, subtitle: w.subtitle, plot: ChartEmptyState(message: w.emptyStateMessage));
    }
    final visible = _visible;
    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Streamgraph', w.title, [
        for (final s in w.series) summarizeValues(s.name, s.values, w.valueFormatter),
      ]),
      title: w.title,
      subtitle: w.subtitle,
      legendPosition: w.legendPosition,
      legendBuilder: w.showLegend
          ? (direction) => Chart2DLegend(
                direction: direction,
                entries: [for (final s in w.series) LegendEntry(label: s.name, color: s.color)],
                hidden: _hidden,
                onToggle: (name) => setState(() => _hidden.contains(name) ? _hidden.remove(name) : _hidden.add(name)),
              )
          : null,
      plot: HoverPlot<(int, int)>(
        enableAnimation: w.enableAnimation,
        animationKey: _hidden.length,
        hitTest: (pos, size) {
          final (p, layers, lo, hi) = _geometry(size);
          if (!p.contains(pos)) return null;
          final i = ((pos.dx - p.left) / p.width * (w.labels.length - 1)).round();
          final value = lo + (p.bottom - pos.dy) / p.height * (hi - lo);
          for (int l = 0; l < layers.length; l++) {
            final (a, b) = layers[l][i];
            if (value >= a && value <= b) return (l, i);
          }
          return (-1, i);
        },
        painterBuilder: (size, hover, progress) {
          final (p, layers, lo, hi) = _geometry(size);
          return _StreamPainter(
            labels: w.labels,
            series: visible,
            layers: layers,
            plot: p,
            lo: lo,
            hi: hi,
            theme: theme,
            hover: hover,
            progress: Curves.easeOutCubic.transform(progress),
          );
        },
        tooltipBuilder: (context, h, pointer, size) {
          final i = h.$2;
          final rows = [
            for (int l = visible.length - 1; l >= 0; l--)
              '${l == h.$1 ? '▶ ' : ''}${visible[l].name}: ${w.valueFormatter(i < visible[l].values.length ? visible[l].values[i] : 0)}',
          ];
          final total = [for (final s in visible) i < s.values.length ? s.values[i] : 0.0].fold(0.0, (a, b) => a + b);
          return positionChartTooltip(
            anchor: pointer,
            areaSize: size,
            cardWidth: 180,
            child: ChartTooltipCard(theme: theme, width: 180, title: w.labels[i], subtitle: rows.join('\n'), value: 'Total ${w.valueFormatter(total)}'),
          );
        },
      ),
    );
  }
}

class _StreamPainter extends CustomPainter {
  final List<String> labels;
  final List<CategorySeries> series;
  final List<List<(double, double)>> layers;
  final Rect plot;
  final double lo, hi;
  final ChartTheme theme;
  final (int, int)? hover;
  final double progress;

  _StreamPainter({
    required this.labels,
    required this.series,
    required this.layers,
    required this.plot,
    required this.lo,
    required this.hi,
    required this.theme,
    required this.hover,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = labels.length;
    double x(int i) => plot.left + plot.width * i / (n - 1);
    final mid = (lo + hi) / 2;
    // Entrance: layers swell out from the centre line.
    double y(double v) => plot.bottom - ((mid + (v - mid) * progress) - lo) / (hi - lo) * plot.height;

    void smooth(Path p, List<Offset> pts, {bool move = true}) {
      if (move) p.moveTo(pts.first.dx, pts.first.dy);
      for (int i = 1; i < pts.length; i++) {
        final mx = (pts[i - 1].dx + pts[i].dx) / 2;
        p.cubicTo(mx, pts[i - 1].dy, mx, pts[i].dy, pts[i].dx, pts[i].dy);
      }
    }

    for (int l = 0; l < layers.length; l++) {
      final top = [for (int i = 0; i < n; i++) Offset(x(i), y(layers[l][i].$2))];
      final bottom = [for (int i = n - 1; i >= 0; i--) Offset(x(i), y(layers[l][i].$1))];
      final path = Path();
      smooth(path, top);
      path.lineTo(bottom.first.dx, bottom.first.dy);
      smooth(path, bottom, move: false);
      path.close();
      final dim = hover != null && hover!.$1 >= 0 && hover!.$1 != l;
      final c = series[l].color;
      canvas.drawPath(path, Paint()..color = dim ? c.withValues(alpha: c.a * 0.35) : c.withValues(alpha: c.a * 0.9));
    }
    // Sparse x labels.
    final every = math.max(1, (n / math.max(1, plot.width / 70)).ceil());
    for (int i = 0; i < n; i += every) {
      final tp = layoutChartText(labels[i], color: theme.tickTextColor, fontSize: theme.tickFontSize, fontFamily: theme.fontFamily);
      tp.paint(canvas, Offset((x(i) - tp.width / 2).clamp(0, size.width - tp.width), plot.bottom + 6));
    }
    final h = hover;
    if (h != null) {
      Cartesian2DAxes.dashedLineStatic(canvas, Offset(x(h.$2), plot.top), Offset(x(h.$2), plot.bottom), Paint()
        ..color = theme.crosshairColor
        ..strokeWidth = 1);
    }
  }

  @override
  bool shouldRepaint(covariant _StreamPainter old) => true;
}

// ---------------------------------------------------------------------------
// Beeswarm
// ---------------------------------------------------------------------------

/// One row of a [BeeswarmChart2D].
class BeeswarmGroup {
  final String label;
  final List<double> values;

  /// Optional name per value, shown in the tooltip.
  final List<String>? pointLabels;
  final Color color;

  const BeeswarmGroup({required this.label, required this.values, required this.color, this.pointLabels});
}

/// A hovered dot: (group, value index).
typedef BeeswarmHit = (int group, int index);

/// A beeswarm (strip) plot: every value as a dot on a shared axis, nudged
/// sideways just enough not to overlap — the full distribution with no
/// binning, outliers in plain sight.
///
/// ```dart
/// BeeswarmChart2D(groups: [
///   BeeswarmGroup(label: 'Team A', color: Colors.indigo, values: responseTimes),
/// ])
/// ```
class BeeswarmChart2D extends StatefulWidget {
  final List<BeeswarmGroup> groups;
  final String? title;
  final String? subtitle;
  final String emptyStateMessage;
  final double dotRadius;

  /// Draw each group's median as a tick.
  final bool showMedian;
  final String Function(double value) valueFormatter;
  final bool enableAnimation;
  final ChartController? controller;
  final void Function(BeeswarmGroup group, int index)? onPointTap;

  const BeeswarmChart2D({
    super.key,
    required this.groups,
    this.title,
    this.subtitle,
    this.emptyStateMessage = 'No data',
    this.dotRadius = 3.5,
    this.showMedian = true,
    this.valueFormatter = Cartesian2DAxes.formatNumber,
    this.enableAnimation = true,
    this.controller,
    this.onPointTap,
  });

  /// Dot offsets from the row's centre line (pixels) for dots at screen
  /// positions [xs] with radius [r]: each dot goes as close to the centre
  /// as it can without overlapping dots already placed (in value order).
  static List<double> swarm(List<double> xs, double r, {double maxOffset = double.infinity}) {
    final order = List.generate(xs.length, (i) => i)..sort((a, b) => xs[a].compareTo(xs[b]));
    final out = List<double>.filled(xs.length, 0);
    final placed = <int>[];
    final d = 2 * r + 0.5;
    for (final i in order) {
      // Candidate offsets: 0, then just clear of each nearby dot, ± sides.
      final near = [for (final j in placed) if ((xs[j] - xs[i]).abs() < d) j];
      final candidates = <double>[0];
      for (final j in near) {
        final dx = xs[i] - xs[j];
        final dy = math.sqrt(math.max(0, d * d - dx * dx));
        candidates
          ..add(out[j] + dy)
          ..add(out[j] - dy);
      }
      candidates.sort((a, b) => a.abs().compareTo(b.abs()));
      var best = candidates.last;
      for (final c in candidates) {
        if (near.every((j) {
          final dx = xs[i] - xs[j], dy = c - out[j];
          return dx * dx + dy * dy >= d * d - 1e-6;
        })) {
          best = c;
          break;
        }
      }
      out[i] = best.clamp(-maxOffset, maxOffset);
      placed.add(i);
    }
    return out;
  }

  @override
  State<BeeswarmChart2D> createState() => _BeeswarmChart2DState();
}

class _BeeswarmChart2DState extends State<BeeswarmChart2D> with ChartControllerMixin<BeeswarmChart2D> {
  @override
  ChartController? controllerOf(BeeswarmChart2D widget) => widget.controller;

  @override
  void resetZoom() {}

  /// (axes, per group: dot centres).
  (Cartesian2DAxes, List<List<Offset>>) _layout(Size size, ChartTheme theme) {
    final w = widget;
    final all = [for (final g in w.groups) ...g.values.where((v) => v.isFinite)];
    var (lo, hi) = (all.reduce(math.min), all.reduce(math.max));
    if (lo == hi) {
      lo -= 1;
      hi += 1;
    }
    final (minX, maxX) = Cartesian2DAxes.niceExtent(lo, hi);
    double labelW = 0;
    for (final g in w.groups) {
      labelW = math.max(labelW, layoutChartText(g.label, color: theme.axisColor, fontSize: 11).width);
    }
    final plot = Rect.fromLTRB(math.min(size.width * 0.3, labelW + 16), 6, size.width - 14, size.height - 24);
    final axes = Cartesian2DAxes(plotArea: plot, minX: minX, maxX: maxX, minY: 0, maxY: 1, theme: theme);
    final rowH = plot.height / w.groups.length;
    final dots = <List<Offset>>[];
    for (int g = 0; g < w.groups.length; g++) {
      final cy = plot.top + rowH * (g + 0.5);
      final xs = [for (final v in w.groups[g].values) axes.toScreenX(v.isFinite ? v : minX)];
      final off = BeeswarmChart2D.swarm(xs, w.dotRadius, maxOffset: rowH / 2 - w.dotRadius);
      dots.add([for (int i = 0; i < xs.length; i++) Offset(xs[i], cy + off[i])]);
    }
    return (axes, dots);
  }

  static double _median(List<double> v) {
    final s = [...v.where((x) => x.isFinite)]..sort();
    if (s.isEmpty) return double.nan;
    return s.length.isOdd ? s[s.length ~/ 2] : (s[s.length ~/ 2 - 1] + s[s.length ~/ 2]) / 2;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    final w = widget;
    if (w.groups.every((g) => g.values.where((v) => v.isFinite).isEmpty)) {
      return ChartFrame(boundaryKey: chartBoundaryKey, title: w.title, subtitle: w.subtitle, plot: ChartEmptyState(message: w.emptyStateMessage));
    }
    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Beeswarm chart', w.title, [
        for (final g in w.groups) '${summarizeValues(g.label, g.values, w.valueFormatter)}, median ${w.valueFormatter(_median(g.values))}',
      ]),
      title: w.title,
      subtitle: w.subtitle,
      plot: HoverPlot<BeeswarmHit>(
        enableAnimation: w.enableAnimation,
        hitTest: (pos, size) {
          final (_, dots) = _layout(size, theme);
          BeeswarmHit? best;
          var bestD = w.dotRadius + 3;
          for (int g = 0; g < dots.length; g++) {
            for (int i = 0; i < dots[g].length; i++) {
              final d = (dots[g][i] - pos).distance;
              if (d < bestD) {
                bestD = d;
                best = (g, i);
              }
            }
          }
          return best;
        },
        onTap: (h) => w.onPointTap?.call(w.groups[h.$1], h.$2),
        painterBuilder: (size, hover, progress) {
          final (axes, dots) = _layout(size, theme);
          return _BeeswarmPainter(
            widget: w,
            axes: axes,
            dots: dots,
            medians: [for (final g in w.groups) _median(g.values)],
            theme: theme,
            hover: hover,
            progress: Curves.easeOutCubic.transform(progress),
          );
        },
        tooltipBuilder: (context, h, pointer, size) {
          final g = w.groups[h.$1];
          final v = g.values[h.$2];
          final rank = g.values.where((x) => x < v).length;
          return positionChartTooltip(
            anchor: pointer,
            areaSize: size,
            cardWidth: 170,
            child: ChartTooltipCard(
              theme: theme,
              width: 170,
              title: g.pointLabels != null && h.$2 < g.pointLabels!.length ? g.pointLabels![h.$2] : g.label,
              subtitle: '${g.pointLabels != null ? '${g.label} · ' : ''}'
                  '${(rank / math.max(1, g.values.length - 1) * 100).round()}th percentile',
              value: w.valueFormatter(v),
            ),
          );
        },
      ),
    );
  }
}

class _BeeswarmPainter extends CustomPainter {
  final BeeswarmChart2D widget;
  final Cartesian2DAxes axes;
  final List<List<Offset>> dots;
  final List<double> medians;
  final ChartTheme theme;
  final BeeswarmHit? hover;
  final double progress;

  _BeeswarmPainter({
    required this.widget,
    required this.axes,
    required this.dots,
    required this.medians,
    required this.theme,
    required this.hover,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = widget;
    final plot = axes.plotArea;
    final ticks = Cartesian2DAxes.niceTicks(axes.minX, axes.maxX, count: math.max(3, (plot.width / 80).floor()));
    for (final t in ticks) {
      final x = axes.toScreenX(t);
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), Paint()..color = theme.gridColor);
    }
    axes.drawXTicks(canvas, [for (final t in ticks) (axes.toScreenX(t), w.valueFormatter(t))]);
    final rowH = plot.height / w.groups.length;
    for (int g = 0; g < w.groups.length; g++) {
      final cy = plot.top + rowH * (g + 0.5);
      final label = layoutChartText(w.groups[g].label,
          color: theme.axisColor, fontSize: 11, fontWeight: FontWeight.w700, fontFamily: theme.fontFamily, maxWidth: plot.left - 10);
      label.paint(canvas, Offset(plot.left - 10 - label.width, cy - label.height / 2));
      if (g > 0) canvas.drawLine(Offset(plot.left, plot.top + rowH * g), Offset(plot.right, plot.top + rowH * g), Paint()..color = theme.gridColor);
      final color = w.groups[g].color;
      for (int i = 0; i < dots[g].length; i++) {
        // Entrance: dots drop from the centre line into the swarm.
        final p = Offset(dots[g][i].dx, cy + (dots[g][i].dy - cy) * progress);
        final hovered = hover == (g, i);
        canvas.drawCircle(p, w.dotRadius + (hovered ? 2 : 0), Paint()..color = color.withValues(alpha: color.a * (hovered ? 1 : 0.75)));
        if (hovered) {
          canvas.drawCircle(p, w.dotRadius + 2, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = theme.axisColor);
        }
      }
      if (w.showMedian && medians[g].isFinite) {
        final x = axes.toScreenX(medians[g]);
        canvas.drawLine(Offset(x, cy - rowH * 0.42), Offset(x, cy + rowH * 0.42), Paint()
          ..color = theme.axisColor
          ..strokeWidth = 2);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BeeswarmPainter old) => true;
}

// ---------------------------------------------------------------------------
// Ridgeline
// ---------------------------------------------------------------------------

/// One distribution of a [RidgelineChart2D].
class RidgelineGroup {
  final String label;
  final List<double> values;
  final Color? color;

  const RidgelineGroup({required this.label, required this.values, this.color});
}

/// A ridgeline (joy) plot: one smoothed distribution per group, stacked
/// with a little overlap — compare many distributions at once (by month,
/// by region, by version).
///
/// Densities are Gaussian kernel estimates with Silverman's bandwidth
/// (scaled by [bandwidthScale]).
class RidgelineChart2D extends StatefulWidget {
  final List<RidgelineGroup> groups;
  final String? title;
  final String? subtitle;
  final String emptyStateMessage;

  /// How far each ridge may rise into the row above (1 = one row).
  final double overlap;
  final double bandwidthScale;

  /// Colors cycle through [gradient] top to bottom when a group has none.
  final List<Color> gradient;
  final bool showMedian;
  final String Function(double value) valueFormatter;
  final bool enableAnimation;
  final ChartController? controller;

  const RidgelineChart2D({
    super.key,
    required this.groups,
    this.title,
    this.subtitle,
    this.emptyStateMessage = 'No data',
    this.overlap = 1.6,
    this.bandwidthScale = 1,
    this.gradient = const [Color(0xFF5C6BC0), Color(0xFF26A69A), Color(0xFFFFA726)],
    this.showMedian = true,
    this.valueFormatter = Cartesian2DAxes.formatNumber,
    this.enableAnimation = true,
    this.controller,
  });

  /// Gaussian kernel density of [values] at each of [at].
  static List<double> density(List<double> values, List<double> at, {double bandwidthScale = 1}) {
    final v = values.where((x) => x.isFinite).toList();
    if (v.isEmpty) return List.filled(at.length, 0);
    final n = v.length;
    final mean = v.reduce((a, b) => a + b) / n;
    final sd = math.sqrt(v.map((x) => (x - mean) * (x - mean)).fold(0.0, (a, b) => a + b) / math.max(1, n - 1));
    final sorted = [...v]..sort();
    final iqr = sorted[(n * 0.75).floor().clamp(0, n - 1)] - sorted[(n * 0.25).floor().clamp(0, n - 1)];
    var spread = math.min(sd, iqr / 1.34);
    if (!(spread > 0)) spread = sd > 0 ? sd : 1;
    final h = 0.9 * spread * math.pow(n, -0.2) * bandwidthScale;
    final k = 1 / (n * h * math.sqrt(2 * math.pi));
    return [
      for (final x in at) k * v.fold(0.0, (s, xi) => s + math.exp(-0.5 * ((x - xi) / h) * ((x - xi) / h))),
    ];
  }

  @override
  State<RidgelineChart2D> createState() => _RidgelineChart2DState();
}

class _RidgelineChart2DState extends State<RidgelineChart2D> with ChartControllerMixin<RidgelineChart2D> {
  @override
  ChartController? controllerOf(RidgelineChart2D widget) => widget.controller;

  @override
  void resetZoom() {}

  late (double, double, List<double>, List<List<double>>) _densities = _compute();

  @override
  void didUpdateWidget(covariant RidgelineChart2D old) {
    super.didUpdateWidget(old);
    if (!identical(old.groups, widget.groups) || old.bandwidthScale != widget.bandwidthScale) _densities = _compute();
  }

  (double, double, List<double>, List<List<double>>) _compute() {
    final all = [for (final g in widget.groups) ...g.values.where((v) => v.isFinite)];
    if (all.isEmpty) return (0, 1, const [], const []);
    var lo = all.reduce(math.min), hi = all.reduce(math.max);
    final pad = (hi - lo) * 0.1 + (hi == lo ? 1 : 0);
    lo -= pad;
    hi += pad;
    const n = 120;
    final xs = [for (int i = 0; i <= n; i++) lo + (hi - lo) * i / n];
    return (lo, hi, xs, [for (final g in widget.groups) RidgelineChart2D.density(g.values, xs, bandwidthScale: widget.bandwidthScale)]);
  }

  (Cartesian2DAxes, double) _layout(Size size, ChartTheme theme) {
    double labelW = 0;
    for (final g in widget.groups) {
      labelW = math.max(labelW, layoutChartText(g.label, color: theme.axisColor, fontSize: 11).width);
    }
    final (lo, hi, _, _) = _densities;
    const top = 8.0;
    final rows = widget.groups.length;
    // Leave room for the top ridge to rise into.
    final rowH = (size.height - 30 - top) / (rows - 1 + widget.overlap).clamp(1, double.infinity);
    final plot = Rect.fromLTRB(math.min(size.width * 0.3, labelW + 16), top, size.width - 14, size.height - 24);
    return (Cartesian2DAxes(plotArea: plot, minX: lo, maxX: hi, minY: 0, maxY: 1, theme: theme), rowH);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    final w = widget;
    final (_, _, xs, dens) = _densities;
    if (xs.isEmpty || w.groups.isEmpty) {
      return ChartFrame(boundaryKey: chartBoundaryKey, title: w.title, subtitle: w.subtitle, plot: ChartEmptyState(message: w.emptyStateMessage));
    }
    final peak = dens.expand((d) => d).fold(0.0, math.max);
    Color colorOf(int g) => w.groups[g].color ?? sampleGradient(w.gradient, w.groups.length == 1 ? 0 : g / (w.groups.length - 1));
    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Ridgeline chart', w.title, [
        for (final g in w.groups) '${summarizeValues(g.label, g.values, w.valueFormatter)}, median ${w.valueFormatter(_BeeswarmChart2DState._median(g.values))}',
      ]),
      title: w.title,
      subtitle: w.subtitle,
      plot: HoverPlot<(int, double)>(
        enableAnimation: w.enableAnimation,
        hitTest: (pos, size) {
          final (axes, rowH) = _layout(size, theme);
          final p = axes.plotArea;
          if (pos.dx < p.left || pos.dx > p.right) return null;
          final x = axes.toDataX(pos.dx);
          // Bottom-most ridge whose filled area contains the pointer.
          for (int g = w.groups.length - 1; g >= 0; g--) {
            final base = p.bottom - rowH * (w.groups.length - 1 - g);
            final i = ((x - xs.first) / (xs.last - xs.first) * (xs.length - 1)).round().clamp(0, xs.length - 1);
            final top = base - dens[g][i] / peak * rowH * w.overlap;
            if (pos.dy <= base && pos.dy >= top - 2) return (g, x);
          }
          return null;
        },
        painterBuilder: (size, hover, progress) {
          final (axes, rowH) = _layout(size, theme);
          return _RidgePainter(
            widget: w,
            axes: axes,
            rowH: rowH,
            xs: xs,
            dens: dens,
            peak: peak,
            colorOf: colorOf,
            theme: theme,
            hover: hover,
            progress: Curves.easeOutCubic.transform(progress),
          );
        },
        tooltipBuilder: (context, h, pointer, size) {
          final g = w.groups[h.$1];
          final v = g.values.where((x) => x.isFinite).toList();
          final below = v.where((x) => x <= h.$2).length;
          return positionChartTooltip(
            anchor: pointer,
            areaSize: size,
            cardWidth: 180,
            child: ChartTooltipCard(
              theme: theme,
              width: 180,
              title: g.label,
              subtitle: 'Median ${w.valueFormatter(_BeeswarmChart2DState._median(g.values))} · n = ${v.length}\n'
                  '${(below / math.max(1, v.length) * 100).round()}% at or below ${w.valueFormatter(h.$2)}',
              value: w.valueFormatter(h.$2),
            ),
          );
        },
      ),
    );
  }
}

class _RidgePainter extends CustomPainter {
  final RidgelineChart2D widget;
  final Cartesian2DAxes axes;
  final double rowH;
  final List<double> xs;
  final List<List<double>> dens;
  final double peak;
  final Color Function(int) colorOf;
  final ChartTheme theme;
  final (int, double)? hover;
  final double progress;

  _RidgePainter({
    required this.widget,
    required this.axes,
    required this.rowH,
    required this.xs,
    required this.dens,
    required this.peak,
    required this.colorOf,
    required this.theme,
    required this.hover,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = widget;
    final p = axes.plotArea;
    final ticks = Cartesian2DAxes.niceTicks(axes.minX, axes.maxX, count: math.max(3, (p.width / 80).floor()));
    for (final t in ticks) {
      if (t < axes.minX || t > axes.maxX) continue;
      canvas.drawLine(Offset(axes.toScreenX(t), p.top), Offset(axes.toScreenX(t), p.bottom), Paint()..color = theme.gridColor);
    }
    axes.drawXTicks(canvas, [for (final t in ticks) if (t >= axes.minX && t <= axes.maxX) (axes.toScreenX(t), w.valueFormatter(t))]);
    // Top rows first, so lower ridges overlap the ones above them.
    for (int g = 0; g < w.groups.length; g++) {
      final base = p.bottom - rowH * (w.groups.length - 1 - g);
      final pts = [for (int i = 0; i < xs.length; i++) Offset(axes.toScreenX(xs[i]), base - dens[g][i] / peak * rowH * w.overlap * progress)];
      final area = Path()..addPolygon([Offset(pts.first.dx, base), ...pts, Offset(pts.last.dx, base)], true);
      final c = colorOf(g);
      final dim = hover != null && hover!.$1 != g;
      canvas.drawPath(area, Paint()..color = c.withValues(alpha: c.a * (dim ? 0.45 : 0.85)));
      canvas.drawPath(Path()..addPolygon(pts, false), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = theme.tooltipBackgroundColor);
      canvas.drawLine(Offset(p.left, base), Offset(p.right, base), Paint()..color = theme.gridColor);
      if (w.showMedian) {
        final m = _BeeswarmChart2DState._median(w.groups[g].values);
        if (m.isFinite) {
          final x = axes.toScreenX(m);
          final i = ((m - xs.first) / (xs.last - xs.first) * (xs.length - 1)).round().clamp(0, xs.length - 1);
          canvas.drawLine(Offset(x, base), Offset(x, pts[i].dy), Paint()
            ..color = theme.tooltipBackgroundColor
            ..strokeWidth = 1.5);
        }
      }
      final label = layoutChartText(w.groups[g].label,
          color: theme.axisColor, fontSize: 11, fontWeight: FontWeight.w700, fontFamily: theme.fontFamily, maxWidth: p.left - 10);
      label.paint(canvas, Offset(p.left - 10 - label.width, base - label.height - 2));
    }
    final h = hover;
    if (h != null) {
      final x = axes.toScreenX(h.$2);
      Cartesian2DAxes.dashedLineStatic(canvas, Offset(x, p.top), Offset(x, p.bottom), Paint()
        ..color = theme.crosshairColor
        ..strokeWidth = 1);
    }
  }

  @override
  bool shouldRepaint(covariant _RidgePainter old) => true;
}
