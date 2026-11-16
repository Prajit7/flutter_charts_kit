import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme.dart';
import 'chart_chrome.dart';
import 'common.dart';
import 'controller.dart';
import 'hover_plot.dart';

/// What the pointer is over in a [ChordChart2D]: a group arc ([target] is
/// null) or the ribbon between [source] and [target].
class ChordHit {
  final int source;
  final int? target;
  const ChordHit(this.source, [this.target]);

  bool get isGroup => target == null;

  @override
  bool operator ==(Object other) => other is ChordHit && other.source == source && other.target == target;

  @override
  int get hashCode => Object.hash(source, target);
}

/// A chord diagram: flows between groups as ribbons around a circle —
/// migration between regions, traffic between services, trade between
/// countries, transfers between teams.
///
/// `matrix[i][j]` is the flow from group i to group j. Each group's arc is
/// sized by its total outflow; a ribbon's two ends show both directions
/// (i→j at i's end, j→i at j's end) and it takes the color of the larger
/// side.
///
/// ```dart
/// ChordChart2D(
///   labels: ['North', 'South', 'East'],
///   matrix: [
///     [0, 12, 4],
///     [8, 0, 6],
///     [3, 9, 0],
///   ],
/// )
/// ```
///
/// Hover a group to isolate its flows; hover a ribbon for both directions.
class ChordChart2D extends StatefulWidget {
  final List<String> labels;

  /// Square matrix of flows, `matrix[from][to]`.
  final List<List<double>> matrix;
  final List<Color> palette;
  final String? title;
  final String? subtitle;
  final String emptyStateMessage;

  /// Gap between group arcs, in radians.
  final double padAngle;
  final bool showLabels;
  final String Function(double value) valueFormatter;
  final bool enableAnimation;
  final Duration animationDuration;
  final Widget Function(BuildContext context, ChordHit hit)? tooltipBuilder;
  final ChartController? controller;
  final ValueChanged<ChordHit>? onTap;

  const ChordChart2D({
    super.key,
    required this.labels,
    required this.matrix,
    this.palette = const [
      Color(0xFF3949AB),
      Color(0xFF00897B),
      Color(0xFFF4511E),
      Color(0xFF8E24AA),
      Color(0xFF039BE5),
      Color(0xFFC0CA33),
      Color(0xFFD81B60),
      Color(0xFF6D4C41),
    ],
    this.title,
    this.subtitle,
    this.emptyStateMessage = 'No flows',
    this.padAngle = 0.04,
    this.showLabels = true,
    this.valueFormatter = _defaultFormat,
    this.enableAnimation = true,
    this.animationDuration = const Duration(milliseconds: 700),
    this.tooltipBuilder,
    this.controller,
    this.onTap,
  });

  static String _defaultFormat(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  State<ChordChart2D> createState() => _ChordChart2DState();
}

/// Angular layout: each group's arc, and for each (i, j) the sub-arc at i's
/// end of the ribbon carrying i→j.
class _ChordLayout {
  final List<(double, double)> groups; // (start, end) angle
  final Map<(int, int), (double, double)> subgroups;
  final List<double> totals;
  final double grand;

  _ChordLayout(this.groups, this.subgroups, this.totals, this.grand);

  static _ChordLayout of(List<List<double>> m, double pad) {
    final n = m.length;
    final totals = [for (int i = 0; i < n; i++) m[i].take(n).fold(0.0, (s, v) => s + math.max(0, v))];
    final grand = totals.fold(0.0, (s, v) => s + v);
    final active = totals.where((t) => t > 0).length;
    final k = grand <= 0 ? 0.0 : (2 * math.pi - pad * active) / grand;
    final groups = <(double, double)>[];
    final subs = <(int, int), (double, double)>{};
    var a = -math.pi / 2; // start at 12 o'clock
    for (int i = 0; i < n; i++) {
      final start = a;
      // Sub-arcs ordered so ribbons to nearby groups don't cross: from the
      // next group clockwise around to the previous one.
      for (int s = 1; s <= n; s++) {
        final j = (i + s) % n;
        final v = math.max(0.0, m[i][j]);
        if (v <= 0) continue;
        subs[(i, j)] = (a, a + v * k);
        a += v * k;
      }
      groups.add((start, a));
      if (totals[i] > 0) a += pad;
    }
    return _ChordLayout(groups, subs, totals, grand);
  }
}

class _ChordChart2DState extends State<ChordChart2D> with ChartControllerMixin<ChordChart2D> {
  @override
  ChartController? controllerOf(ChordChart2D widget) => widget.controller;

  /// Nothing to reset: the chord diagram has no zoom.
  @override
  void resetZoom() {}

  late _ChordLayout _layout;

  @override
  void initState() {
    super.initState();
    _layout = _ChordLayout.of(widget.matrix, widget.padAngle);
  }

  @override
  void didUpdateWidget(covariant ChordChart2D old) {
    super.didUpdateWidget(old);
    if (!identical(old.matrix, widget.matrix) || old.padAngle != widget.padAngle) {
      _layout = _ChordLayout.of(widget.matrix, widget.padAngle);
    }
  }

  Color _color(int i) => widget.palette[i % widget.palette.length];

  /// (centre, outer radius of the group ring, ring thickness).
  (Offset, double, double) _geometry(Size size) {
    final labelRoom = widget.showLabels ? 46.0 : 6.0;
    final r = math.max(10.0, math.min(size.width, size.height) / 2 - labelRoom);
    return (size.center(Offset.zero), r, math.max(6, r * 0.07));
  }

  static double _norm(double a) {
    final t = (a + math.pi / 2) % (2 * math.pi);
    return t < 0 ? t + 2 * math.pi : t;
  }

  static bool _within(double a, (double, double) arc) {
    final t = _norm(a), s = _norm(arc.$1);
    final span = arc.$2 - arc.$1;
    final d = (t - s) % (2 * math.pi);
    return span > 0 && (d < 0 ? d + 2 * math.pi : d) <= span;
  }

  ChordHit? _hit(Offset pos, Size size) {
    final (c, r, ring) = _geometry(size);
    final v = pos - c;
    final d = v.distance, a = math.atan2(v.dy, v.dx);
    if (d >= r - ring && d <= r + 4) {
      for (int i = 0; i < _layout.groups.length; i++) {
        if (_layout.totals[i] > 0 && _within(a, _layout.groups[i])) return ChordHit(i);
      }
      return null;
    }
    if (d < r - ring) {
      // Topmost ribbon whose path contains the point (painted in key order).
      final inner = r - ring;
      ChordHit? found;
      for (final key in _ribbonKeys()) {
        if (_ribbonPath(c, inner, key.$1, key.$2).contains(pos)) found = ChordHit(key.$1, key.$2);
      }
      return found;
    }
    return null;
  }

  /// One ribbon per unordered pair with any flow (i < j), plus self-loops.
  List<(int, int)> _ribbonKeys() {
    final keys = <(int, int)>[];
    final n = widget.labels.length;
    for (int i = 0; i < n; i++) {
      for (int j = i; j < n; j++) {
        if (_layout.subgroups.containsKey((i, j)) || _layout.subgroups.containsKey((j, i))) keys.add((i, j));
      }
    }
    return keys;
  }

  Path _ribbonPath(Offset c, double r, int i, int j, {double progress = 1}) {
    // Each end: the sub-arc carrying that side's flow; a one-way flow gets
    // a sliver at the receiving end so the ribbon still has a target.
    (double, double) end(int a, int b) {
      final s = _layout.subgroups[(a, b)];
      if (s != null) return (s.$1, s.$1 + (s.$2 - s.$1) * progress);
      final g = _layout.groups[a];
      final mid = (g.$1 + g.$2) / 2;
      return (mid, mid + 0.004);
    }

    final (a0, a1) = end(i, j);
    final (b0, b1) = i == j ? (a0, a1) : end(j, i);
    Offset at(double ang) => c + Offset(math.cos(ang), math.sin(ang)) * r;
    final rect = Rect.fromCircle(center: c, radius: r);
    final p = Path()..moveTo(at(a0).dx, at(a0).dy);
    p.arcTo(rect, a0, a1 - a0, false);
    p.quadraticBezierTo(c.dx, c.dy, at(b0).dx, at(b0).dy);
    p.arcTo(rect, b0, b1 - b0, false);
    p.quadraticBezierTo(c.dx, c.dy, at(a0).dx, at(a0).dy);
    return p..close();
  }

  double _flow(int i, int j) => i < widget.matrix.length && j < widget.matrix[i].length ? math.max(0, widget.matrix[i][j]) : 0;

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    final n = widget.labels.length;
    final valid = n > 0 && widget.matrix.length == n && widget.matrix.every((r) => r.length == n);
    if (!valid || _layout.grand <= 0) {
      return ChartFrame(
        boundaryKey: chartBoundaryKey,
        title: widget.title,
        subtitle: widget.subtitle,
        plot: ChartEmptyState(message: valid ? widget.emptyStateMessage : 'Matrix must be ${n}x$n'),
      );
    }
    final fmt = widget.valueFormatter;
    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Chord diagram', widget.title, [
        for (int i = 0; i < n; i++) '${widget.labels[i]}: ${fmt(_layout.totals[i])} out',
      ]),
      title: widget.title,
      subtitle: widget.subtitle,
      plot: HoverPlot<ChordHit>(
        enableAnimation: widget.enableAnimation,
        animationDuration: widget.animationDuration,
        animationKey: _layout.grand,
        hitTest: _hit,
        onTap: widget.onTap,
        painterBuilder: (size, hover, progress) {
          final (c, r, ring) = _geometry(size);
          final t = Curves.easeOutCubic.transform(progress);
          return _ChordPainter(
            state: this,
            center: c,
            radius: r,
            ring: ring,
            keys: _ribbonKeys(),
            theme: theme,
            hover: hover,
            progress: t,
          );
        },
        tooltipBuilder: (context, hit, pointer, size) {
          final custom = widget.tooltipBuilder;
          final i = hit.source, j = hit.target;
          final String title, value;
          String? subtitle;
          if (j == null) {
            final inflow = [for (int k = 0; k < n; k++) _flow(k, i)].fold(0.0, (s, v) => s + v);
            title = widget.labels[i];
            value = '${fmt(_layout.totals[i])} out';
            subtitle = '${fmt(inflow)} in · ${(_layout.totals[i] / _layout.grand * 100).toStringAsFixed(1)}% of all outflow';
          } else if (i == j) {
            title = '${widget.labels[i]} (within)';
            value = fmt(_flow(i, i));
          } else {
            title = '${widget.labels[i]} ⇄ ${widget.labels[j]}';
            value = '${fmt(_flow(i, j))} / ${fmt(_flow(j, i))}';
            subtitle = '${widget.labels[i]} → ${widget.labels[j]}: ${fmt(_flow(i, j))}\n'
                '${widget.labels[j]} → ${widget.labels[i]}: ${fmt(_flow(j, i))}';
          }
          return positionChartTooltip(
            anchor: pointer,
            areaSize: size,
            cardWidth: 200,
            child: custom != null
                ? custom(context, hit)
                : ChartTooltipCard(theme: theme, width: 200, title: title, subtitle: subtitle, value: value),
          );
        },
      ),
    );
  }
}

class _ChordPainter extends CustomPainter {
  final _ChordChart2DState state;
  final Offset center;
  final double radius;
  final double ring;
  final List<(int, int)> keys;
  final ChartTheme theme;
  final ChordHit? hover;
  final double progress;

  _ChordPainter({
    required this.state,
    required this.center,
    required this.radius,
    required this.ring,
    required this.keys,
    required this.theme,
    required this.hover,
    required this.progress,
  });

  bool _lit(int i, int j) {
    final h = hover;
    if (h == null) return true;
    if (h.isGroup) return i == h.source || j == h.source;
    return (i == h.source && j == h.target) || (i == h.target && j == h.source);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = state;
    final layout = s._layout;
    final inner = radius - ring;

    // Ribbons: colored by the side with the larger flow.
    for (final (i, j) in keys) {
      final color = s._color(s._flow(i, j) >= s._flow(j, i) ? i : j);
      final lit = _lit(i, j);
      final alpha = hover == null ? 0.62 : (lit ? 0.85 : 0.07);
      final path = s._ribbonPath(center, inner - 1, i, j, progress: progress);
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: color.a * alpha));
      if (lit && hover != null) {
        canvas.drawPath(path, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = color);
      }
    }

    // Group arcs and labels.
    final rect = Rect.fromCircle(center: center, radius: radius - ring / 2);
    for (int i = 0; i < layout.groups.length; i++) {
      if (layout.totals[i] <= 0) continue;
      final (a0, a1) = layout.groups[i];
      final sweep = (a1 - a0) * progress;
      final dim = hover != null && hover!.isGroup && hover!.source != i;
      final color = s._color(i);
      canvas.drawArc(rect, a0, sweep, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring
        ..color = dim ? color.withValues(alpha: color.a * 0.35) : color);
      if (!s.widget.showLabels || a1 - a0 < 0.06) continue;
      final mid = (a0 + a1) / 2;
      final dir = Offset(math.cos(mid), math.sin(mid));
      final anchor = center + dir * (radius + 6);
      final tp = layoutChartText(s.widget.labels[i],
          color: theme.axisColor.withValues(alpha: theme.axisColor.a * (dim ? 0.4 : 1)),
          fontSize: 11,
          fontFamily: theme.fontFamily,
          maxWidth: 90);
      // Grow outward from the ring: left of the anchor on the left side.
      final dx = dir.dx < -0.2 ? -tp.width : (dir.dx > 0.2 ? 0.0 : -tp.width / 2);
      final dy = dir.dy < -0.2 ? -tp.height : (dir.dy > 0.2 ? 0.0 : -tp.height / 2);
      tp.paint(canvas, anchor + Offset(dx, dy));
    }
  }

  @override
  bool shouldRepaint(covariant _ChordPainter old) => true;
}
