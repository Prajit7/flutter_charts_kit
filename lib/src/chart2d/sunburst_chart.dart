import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'cartesian_axes.dart';
import 'theme.dart';
import 'chart_chrome.dart';
import 'common.dart';
import 'controller.dart';
import 'hover_plot.dart';
import 'treemap_chart.dart' show TreemapNode;

/// A laid-out ring segment of a [SunburstChart2D].
class SunburstSegment {
  final TreemapNode node;

  /// Labels from the root down to this node.
  final List<String> path;
  final int depth;
  final double startAngle;
  final double sweep;
  final Color color;

  const SunburstSegment(this.node, this.path, this.depth, this.startAngle, this.sweep, this.color);

  @override
  bool operator ==(Object other) => other is SunburstSegment && identical(other.node, node);

  @override
  int get hashCode => identityHashCode(node);
}

/// A sunburst: a hierarchy as concentric rings, each node's arc
/// proportional to its value — the radial sibling of [TreemapChart2D], and
/// takes the same [TreemapNode]s.
///
/// Tap a segment that has children to zoom into it; tap the centre to go
/// back up.
///
/// ```dart
/// SunburstChart2D(nodes: [
///   TreemapNode(label: 'Engineering', children: [
///     TreemapNode(label: 'Salaries', value: 820),
///     TreemapNode(label: 'Cloud', value: 240),
///   ]),
///   TreemapNode(label: 'Marketing', value: 310),
/// ])
/// ```
class SunburstChart2D extends StatefulWidget {
  final List<TreemapNode> nodes;
  final String? title;
  final String? subtitle;
  final String emptyStateMessage;
  final String Function(double value) valueFormatter;
  final List<Color> palette;

  /// Radius of the centre hole as a fraction of the outer radius.
  final double centerRadiusRatio;

  /// Tap a segment with children to zoom in; tap the centre to zoom out.
  final bool drillDown;

  /// Label segments that are big enough.
  final bool showLabels;
  final bool enableAnimation;
  final Duration animationDuration;
  final Widget Function(BuildContext context, SunburstSegment segment)? tooltipBuilder;
  final ChartController? controller;
  final ValueChanged<SunburstSegment>? onSegmentTap;

  const SunburstChart2D({
    super.key,
    required this.nodes,
    this.title,
    this.subtitle,
    this.emptyStateMessage = 'No data to display',
    this.valueFormatter = Cartesian2DAxes.formatNumber,
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
    this.centerRadiusRatio = 0.28,
    this.drillDown = true,
    this.showLabels = true,
    this.enableAnimation = true,
    this.animationDuration = const Duration(milliseconds: 550),
    this.tooltipBuilder,
    this.controller,
    this.onSegmentTap,
  });

  @override
  State<SunburstChart2D> createState() => _SunburstChart2DState();
}

/// Sentinel hit for the centre circle (zoom out).
const _center = SunburstSegment(TreemapNode(label: ''), [], -1, 0, 0, Color(0x00000000));

class _SunburstChart2DState extends State<SunburstChart2D> with ChartControllerMixin<SunburstChart2D> {
  /// The drill-down path: nodes zoomed into, outermost first.
  final List<TreemapNode> _focus = [];

  @override
  ChartController? controllerOf(SunburstChart2D widget) => widget.controller;

  @override
  void resetZoom() => setState(_focus.clear);

  @override
  void didUpdateWidget(covariant SunburstChart2D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.nodes, widget.nodes)) _focus.clear();
  }

  List<TreemapNode> get _roots => _focus.isEmpty ? widget.nodes : _focus.last.children;
  double get _total => _roots.fold(0.0, (s, n) => s + n.total);

  /// Segments for the current root, parents before children.
  List<SunburstSegment> _segments() {
    final out = <SunburstSegment>[];
    void place(List<TreemapNode> nodes, double start, double sweep, int depth, Color? inherited, List<String> path) {
      final total = nodes.fold(0.0, (s, n) => s + n.total);
      if (total <= 0) return;
      var a = start;
      for (int i = 0; i < nodes.length; i++) {
        final n = nodes[i];
        if (n.total <= 0) continue;
        final s = sweep * n.total / total;
        final color = n.color ?? inherited ?? widget.palette[i % widget.palette.length];
        final seg = SunburstSegment(n, [...path, n.label], depth, a, s, color);
        out.add(seg);
        if (!n.isLeaf) place(n.children, a, s, depth + 1, color, seg.path);
        a += s;
      }
    }

    final inherited = _focus.isEmpty ? null : _colorOfFocus();
    place(_roots, -math.pi / 2, 2 * math.pi, 0, inherited, [for (final f in _focus) f.label]);
    return out;
  }

  /// The color the focused node had at the top level, so drilling in keeps it.
  Color? _colorOfFocus() {
    final top = _focus.first;
    final i = widget.nodes.indexOf(top);
    return top.color ?? (i < 0 ? null : widget.palette[i % widget.palette.length]);
  }

  int get _depth {
    int d(TreemapNode n) => n.isLeaf ? 1 : 1 + n.children.map(d).fold(0, math.max);
    return _roots.map(d).fold(1, math.max);
  }

  (Offset, double, double) _geometry(Size size) {
    final r = math.max(0.0, math.min(size.width, size.height) / 2 - 4);
    final r0 = r * widget.centerRadiusRatio;
    return (size.center(Offset.zero), r0, (r - r0) / _depth);
  }

  SunburstSegment? _hit(Offset pos, Size size, List<SunburstSegment> segs) {
    final (c, r0, ring) = _geometry(size);
    final d = (pos - c).distance;
    if (d < r0) return _focus.isEmpty ? null : _center;
    final depth = ((d - r0) / ring).floor();
    var angle = math.atan2(pos.dy - c.dy, pos.dx - c.dx);
    if (angle < -math.pi / 2) angle += 2 * math.pi; // segments start at 12 o'clock
    for (final s in segs) {
      if (s.depth == depth && angle >= s.startAngle && angle < s.startAngle + s.sweep) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    if (widget.nodes.every((n) => n.total <= 0)) {
      return ChartFrame(
        boundaryKey: chartBoundaryKey,
        title: widget.title,
        subtitle: widget.subtitle,
        plot: ChartEmptyState(message: widget.emptyStateMessage),
      );
    }
    final segs = _segments();
    final total = _total;
    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Sunburst chart', widget.title, [
        if (_focus.isNotEmpty) 'zoomed into ${_focus.map((f) => f.label).join(' › ')}',
        for (final n in _roots) '${n.label}: ${widget.valueFormatter(n.total)}',
      ]),
      title: widget.title,
      subtitle: widget.subtitle,
      plot: HoverPlot<SunburstSegment>(
        enableAnimation: widget.enableAnimation,
        animationDuration: widget.animationDuration,
        // Replay the grow-in each time the user drills in or out.
        animationKey: Object.hash(_focus.length, _focus.isEmpty ? null : identityHashCode(_focus.last), total),
        hitTest: (pos, size) => _hit(pos, size, segs),
        onTap: (s) {
          if (identical(s, _center)) {
            setState(_focus.removeLast);
            return;
          }
          widget.onSegmentTap?.call(s);
          if (widget.drillDown && !s.node.isLeaf) setState(() => _focus.add(s.node));
        },
        painterBuilder: (size, hover, progress) {
          final (c, r0, ring) = _geometry(size);
          return _SunburstPainter(
            segments: segs,
            center: c,
            innerRadius: r0,
            ring: ring,
            centerLabel: _focus.isEmpty ? (widget.title ?? 'Total') : _focus.last.label,
            centerValue: widget.valueFormatter(total),
            canZoomOut: _focus.isNotEmpty,
            showLabels: widget.showLabels,
            theme: theme,
            hover: hover,
            progress: Curves.easeOutCubic.transform(progress),
          );
        },
        tooltipBuilder: (context, s, pointer, size) {
          if (identical(s, _center)) return null;
          final custom = widget.tooltipBuilder;
          final parent = s.depth == 0 ? total : segs.firstWhere((p) => !p.node.isLeaf && p.node.children.contains(s.node)).node.total;
          return positionChartTooltip(
            anchor: pointer,
            areaSize: size,
            cardWidth: 180,
            child: custom != null
                ? custom(context, s)
                : ChartTooltipCard(
                    theme: theme,
                    width: 180,
                    title: s.path.join(' › '),
                    subtitle: '${(s.node.total / total * 100).toStringAsFixed(1)}% of total'
                        '${s.depth > 0 ? ' · ${(s.node.total / parent * 100).toStringAsFixed(1)}% of parent' : ''}',
                    value: widget.valueFormatter(s.node.total),
                  ),
          );
        },
      ),
    );
  }
}

class _SunburstPainter extends CustomPainter {
  final List<SunburstSegment> segments;
  final Offset center;
  final double innerRadius;
  final double ring;
  final String centerLabel;
  final String centerValue;
  final bool canZoomOut;
  final bool showLabels;
  final ChartTheme theme;
  final SunburstSegment? hover;
  final double progress;

  _SunburstPainter({
    required this.segments,
    required this.center,
    required this.innerRadius,
    required this.ring,
    required this.centerLabel,
    required this.centerValue,
    required this.canZoomOut,
    required this.showLabels,
    required this.theme,
    required this.hover,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (ring <= 0) return;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = theme.backgroundColor.a == 0 ? Colors.white : theme.backgroundColor;
    final hoverIsCenter = hover != null && hover!.depth < 0;
    for (final s in segments) {
      final r1 = innerRadius + s.depth * ring, r2 = r1 + ring;
      final sweep = s.sweep * progress;
      if (sweep <= 0) continue;
      final path = Path()
        ..addArc(Rect.fromCircle(center: center, radius: r2), s.startAngle, sweep)
        ..arcTo(Rect.fromCircle(center: center, radius: r1), s.startAngle + sweep, -sweep, false)
        ..close();
      // Deeper rings lighten so siblings in a branch stay distinguishable.
      var color = Color.lerp(s.color, Colors.white, (s.depth * 0.16).clamp(0.0, 0.5))!;
      if (hover != null && !hoverIsCenter && hover != s) color = color.withValues(alpha: 0.55);
      canvas.drawPath(path, Paint()..color = color);
      canvas.drawPath(path, border);

      if (showLabels && progress >= 1) {
        final mid = s.startAngle + s.sweep / 2;
        final rMid = (r1 + r2) / 2;
        final arcLength = s.sweep * rMid;
        final tp = layoutChartText(s.node.label,
            color: contrastingTextColor(color), fontSize: 10, fontFamily: theme.fontFamily, maxWidth: ring - 6);
        // Radial text (reads outward) if it fits the ring and the slice is
        // tall enough for a line of text.
        if (tp.width <= ring - 6 && arcLength >= tp.height + 2) {
          canvas.save();
          canvas.translate(center.dx + math.cos(mid) * rMid, center.dy + math.sin(mid) * rMid);
          // Keep text upright on the left half.
          final flip = mid > math.pi / 2 && mid < 3 * math.pi / 2;
          canvas.rotate(flip ? mid + math.pi : mid);
          tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
          canvas.restore();
        }
      }
    }

    // Centre: the current root's name and total; a back arrow when zoomed.
    final name = layoutChartText(canZoomOut ? '← $centerLabel' : centerLabel,
        color: theme.subtitleColor, fontSize: 11, fontFamily: theme.fontFamily, maxWidth: innerRadius * 1.7);
    final value = layoutChartText(centerValue,
        color: theme.titleColor, fontSize: math.max(12, innerRadius * 0.3), fontWeight: FontWeight.bold, fontFamily: theme.fontFamily, maxWidth: innerRadius * 1.8);
    if (hoverIsCenter) canvas.drawCircle(center, innerRadius - 2, Paint()..color = theme.gridColor);
    final h = name.height + value.height;
    name.paint(canvas, center - Offset(name.width / 2, h / 2));
    value.paint(canvas, center - Offset(value.width / 2, h / 2 - name.height));
  }

  @override
  bool shouldRepaint(covariant _SunburstPainter old) => true;
}
