import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'cartesian_axes.dart';
import 'theme.dart';
import 'chart_chrome.dart';
import 'common.dart';
import 'controller.dart';
import 'hover_plot.dart';

/// A flow of [value] from node [source] to node [target] (by node id).
class SankeyLink {
  final String source;
  final String target;
  final double value;

  /// Defaults to the source node's color.
  final Color? color;

  const SankeyLink({required this.source, required this.target, required this.value, this.color});
}

/// Optional styling for a node; nodes are otherwise created from link ids.
class SankeyNode {
  final String id;

  /// Shown instead of [id] when set.
  final String? label;
  final Color? color;

  const SankeyNode({required this.id, this.label, this.color});
}

/// What's under the pointer in a [SankeyChart2D]: a node or a link.
class SankeyHit {
  final String? nodeId;
  final SankeyLink? link;

  const SankeyHit.node(String this.nodeId) : link = null;
  const SankeyHit.link(SankeyLink this.link) : nodeId = null;

  @override
  bool operator ==(Object other) => other is SankeyHit && other.nodeId == nodeId && identical(other.link, link);

  @override
  int get hashCode => Object.hash(nodeId, identityHashCode(link));
}

/// A Sankey diagram: flows between stages, with band widths proportional to
/// the amount flowing — budgets, user journeys, energy, conversions.
///
/// ```dart
/// SankeyChart2D(
///   links: [
///     SankeyLink(source: 'Visits', target: 'Signed up', value: 3100),
///     SankeyLink(source: 'Visits', target: 'Bounced', value: 8900),
///     SankeyLink(source: 'Signed up', target: 'Paid', value: 380),
///   ],
/// )
/// ```
///
/// Nodes are placed in columns by their longest path from a source, with
/// end nodes pushed to the last column. Links that would form a cycle are
/// ignored — a Sankey diagram must flow one way.
class SankeyChart2D extends StatefulWidget {
  final List<SankeyLink> links;

  /// Optional labels/colors for nodes, by id.
  final List<SankeyNode> nodes;
  final String? title;
  final String? subtitle;
  final String emptyStateMessage;
  final String Function(double value) valueFormatter;
  final List<Color> palette;
  final double nodeWidth;

  /// Vertical space between nodes in the same column.
  final double nodePadding;
  final bool enableAnimation;
  final Duration animationDuration;

  /// Replaces the default tooltip card.
  final Widget Function(BuildContext context, SankeyHit hit)? tooltipBuilder;

  /// Export an image from outside the chart.
  final ChartController? controller;
  final ValueChanged<SankeyHit>? onTap;

  const SankeyChart2D({
    super.key,
    required this.links,
    this.nodes = const [],
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
    this.nodeWidth = 12,
    this.nodePadding = 10,
    this.enableAnimation = true,
    this.animationDuration = const Duration(milliseconds: 700),
    this.tooltipBuilder,
    this.controller,
    this.onTap,
  });

  @override
  State<SankeyChart2D> createState() => _SankeyChart2DState();
}

class _LaidNode {
  final String id;
  final String label;
  final Color color;
  int column = 0;
  double valueIn = 0;
  double valueOut = 0;
  Rect rect = Rect.zero;

  _LaidNode(this.id, this.label, this.color);

  double get value => math.max(valueIn, valueOut);
}

class _LaidLink {
  final SankeyLink link;
  final _LaidNode source;
  final _LaidNode target;
  double width = 0;
  double sourceY = 0; // centre of the band where it leaves the source
  double targetY = 0; // … and where it enters the target

  _LaidLink(this.link, this.source, this.target);

  /// The band: top edge left→right, bottom edge right→left.
  Path path() {
    final x0 = source.rect.right, x1 = target.rect.left;
    final xm = (x0 + x1) / 2;
    final h = width / 2;
    return Path()
      ..moveTo(x0, sourceY - h)
      ..cubicTo(xm, sourceY - h, xm, targetY - h, x1, targetY - h)
      ..lineTo(x1, targetY + h)
      ..cubicTo(xm, targetY + h, xm, sourceY + h, x0, sourceY + h)
      ..close();
  }
}

class _SankeyLayout {
  final List<_LaidNode> nodes;
  final List<_LaidLink> links;
  final int columns;

  _SankeyLayout(this.nodes, this.links, this.columns);
}

/// Drops links that would close a cycle (keeping the first-listed ones).
List<SankeyLink> _acyclic(List<SankeyLink> links) {
  final out = <String, Set<String>>{};
  bool reaches(String from, String to) {
    final seen = <String>{};
    final stack = [from];
    while (stack.isNotEmpty) {
      final n = stack.removeLast();
      if (n == to) return true;
      if (seen.add(n)) stack.addAll(out[n] ?? const {});
    }
    return false;
  }

  final kept = <SankeyLink>[];
  for (final l in links) {
    if (l.value <= 0 || l.source == l.target || reaches(l.target, l.source)) continue;
    (out[l.source] ??= {}).add(l.target);
    kept.add(l);
  }
  return kept;
}

class _SankeyChart2DState extends State<SankeyChart2D> with ChartControllerMixin<SankeyChart2D> {
  @override
  ChartController? controllerOf(SankeyChart2D widget) => widget.controller;

  @override
  void resetZoom() {} // no zoom on this chart

  _SankeyLayout _layout(Size size, ChartTheme theme) {
    final links = _acyclic(widget.links);
    final styles = {for (final n in widget.nodes) n.id: n};
    final byId = <String, _LaidNode>{};
    _LaidNode node(String id) => byId.putIfAbsent(id, () {
          final style = styles[id];
          return _LaidNode(id, style?.label ?? id, style?.color ?? widget.palette[byId.length % widget.palette.length]);
        });
    // Declared nodes first, so their palette colors follow declaration order.
    for (final n in widget.nodes) {
      node(n.id);
    }
    final laid = [for (final l in links) _LaidLink(l, node(l.source), node(l.target))];
    for (final l in laid) {
      l.source.valueOut += l.link.value;
      l.target.valueIn += l.link.value;
    }
    final nodes = byId.values.where((n) => n.value > 0).toList();
    if (nodes.isEmpty) return _SankeyLayout(const [], const [], 0);

    // Columns: longest path from a source; sinks justified to the last column.
    bool changed = true;
    for (int guard = 0; changed && guard < nodes.length; guard++) {
      changed = false;
      for (final l in laid) {
        if (l.target.column < l.source.column + 1) {
          l.target.column = l.source.column + 1;
          changed = true;
        }
      }
    }
    final columns = nodes.map((n) => n.column).reduce(math.max) + 1;
    for (final n in nodes) {
      if (n.valueOut == 0) n.column = columns - 1;
    }

    // Nodes span the full width; labels sit beside them (inside the
    // neighbouring gap) and are ellipsized at paint time to fit.
    final area = Rect.fromLTRB(0, 4, size.width, size.height - 4);
    final colX = [
      for (int c = 0; c < columns; c++)
        columns == 1 ? area.center.dx - widget.nodeWidth / 2 : area.left + c * (area.width - widget.nodeWidth) / (columns - 1),
    ];

    final byColumn = [for (int c = 0; c < columns; c++) nodes.where((n) => n.column == c).toList()];
    final ky = byColumn
        .where((col) => col.isNotEmpty)
        .map((col) => (area.height - (col.length - 1) * widget.nodePadding) / col.fold(0.0, (s, n) => s + n.value))
        .reduce(math.min)
        .clamp(0.0, double.infinity);

    // Initial stacking in declaration order, centred vertically.
    for (int c = 0; c < columns; c++) {
      final col = byColumn[c];
      final total = col.fold(0.0, (s, n) => s + n.value * ky) + (col.length - 1) * widget.nodePadding;
      double y = area.top + (area.height - total) / 2;
      for (final n in col) {
        n.rect = Rect.fromLTWH(colX[c], y, widget.nodeWidth, math.max(1, n.value * ky));
        y += n.rect.height + widget.nodePadding;
      }
    }

    // Relaxation: nudge each node toward the weighted centre of its
    // neighbours (left-to-right, then right-to-left) to reduce crossings.
    void resolve(List<_LaidNode> col) {
      // By centre, not top: a tall node shouldn't claim the top slot just
      // because its upper edge reaches higher than a small node's.
      col.sort((a, b) => a.rect.center.dy.compareTo(b.rect.center.dy));
      double y = area.top;
      for (final n in col) {
        if (n.rect.top < y) n.rect = n.rect.translate(0, y - n.rect.top);
        y = n.rect.bottom + widget.nodePadding;
      }
      double bottom = area.bottom;
      for (final n in col.reversed) {
        if (n.rect.bottom > bottom) n.rect = n.rect.translate(0, bottom - n.rect.bottom);
        bottom = n.rect.top - widget.nodePadding;
      }
    }

    for (int iter = 0; iter < 6; iter++) {
      final alpha = math.pow(0.99, iter).toDouble();
      for (final forward in [true, false]) {
        final order = forward ? List.generate(columns, (i) => i) : List.generate(columns, (i) => columns - 1 - i);
        for (final c in order) {
          for (final n in byColumn[c]) {
            final neighbours = forward
                ? laid.where((l) => l.target == n).map((l) => (l.source.rect.center.dy, l.link.value))
                : laid.where((l) => l.source == n).map((l) => (l.target.rect.center.dy, l.link.value));
            final w = neighbours.fold(0.0, (s, e) => s + e.$2);
            if (w == 0) continue;
            final target = neighbours.fold(0.0, (s, e) => s + e.$1 * e.$2) / w;
            n.rect = n.rect.translate(0, (target - n.rect.center.dy) * alpha);
          }
          resolve(byColumn[c]);
        }
      }
    }

    // Link band positions: stacked within each node, ordered by the far end's
    // height so bands don't cross at the node.
    for (final n in nodes) {
      final outs = laid.where((l) => l.source == n).toList()..sort((a, b) => a.target.rect.center.dy.compareTo(b.target.rect.center.dy));
      double y = n.rect.top;
      for (final l in outs) {
        l.width = l.link.value * ky;
        l.sourceY = y + l.width / 2;
        y += l.width;
      }
      final ins = laid.where((l) => l.target == n).toList()..sort((a, b) => a.source.rect.center.dy.compareTo(b.source.rect.center.dy));
      y = n.rect.top;
      for (final l in ins) {
        l.targetY = y + l.link.value * ky / 2;
        y += l.link.value * ky;
      }
    }
    return _SankeyLayout(nodes, laid, columns);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    if (_acyclic(widget.links).isEmpty) {
      return ChartFrame(
        boundaryKey: chartBoundaryKey,
        title: widget.title,
        subtitle: widget.subtitle,
        plot: ChartEmptyState(message: widget.emptyStateMessage),
      );
    }
    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Flow diagram', widget.title, [for (final l in _acyclic(widget.links)) '${l.source} to ${l.target}: ${widget.valueFormatter(l.value)}']),
      title: widget.title,
      subtitle: widget.subtitle,
      plot: HoverPlot<SankeyHit>(
        enableAnimation: widget.enableAnimation,
        animationDuration: widget.animationDuration,
        animationKey: Object.hashAll([for (final l in widget.links) Object.hash(l.source, l.target, l.value)]),
        onTap: widget.onTap,
        hitTest: (pos, size) {
          final layout = _layout(size, theme);
          for (final n in layout.nodes) {
            if (n.rect.inflate(3).contains(pos)) return SankeyHit.node(n.id);
          }
          // Topmost (last drawn) link first.
          for (final l in layout.links.reversed) {
            if (l.path().contains(pos)) return SankeyHit.link(l.link);
          }
          return null;
        },
        painterBuilder: (size, hover, progress) => _SankeyPainter(_layout(size, theme), theme, hover, progress),
        tooltipBuilder: (context, hit, pointer, size) {
          final custom = widget.tooltipBuilder;
          final layout = _layout(size, theme);
          String label(String id) => layout.nodes.firstWhere((n) => n.id == id).label;
          final String title, value;
          String? subtitle;
          if (hit.link != null) {
            title = '${label(hit.link!.source)} → ${label(hit.link!.target)}';
            value = widget.valueFormatter(hit.link!.value);
            final out = layout.nodes.firstWhere((n) => n.id == hit.link!.source).valueOut;
            subtitle = '${(hit.link!.value / out * 100).toStringAsFixed(1)}% of ${label(hit.link!.source)}';
          } else {
            final n = layout.nodes.firstWhere((n) => n.id == hit.nodeId);
            title = n.label;
            value = widget.valueFormatter(n.value);
            subtitle = [
              if (n.valueIn > 0) 'In ${widget.valueFormatter(n.valueIn)}',
              if (n.valueOut > 0) 'Out ${widget.valueFormatter(n.valueOut)}',
            ].join('   ');
          }
          return positionChartTooltip(
            anchor: pointer,
            areaSize: size,
            cardWidth: 180,
            child: custom != null
                ? custom(context, hit)
                : ChartTooltipCard(theme: theme, width: 180, title: title, subtitle: subtitle, value: value),
          );
        },
      ),
    );
  }
}

class _SankeyPainter extends CustomPainter {
  final _SankeyLayout layout;
  final ChartTheme theme;
  final SankeyHit? hover;
  final double progress;

  _SankeyPainter(this.layout, this.theme, this.hover, this.progress);

  bool _highlighted(_LaidLink l) {
    final h = hover;
    if (h == null) return false;
    if (h.link != null) return identical(h.link, l.link);
    return l.source.id == h.nodeId || l.target.id == h.nodeId;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Links reveal left-to-right.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * progress, size.height));
    for (final l in layout.links) {
      final color = l.link.color ?? l.source.color;
      final alpha = hover == null ? 0.35 : (_highlighted(l) ? 0.6 : 0.15);
      canvas.drawPath(l.path(), Paint()..color = color.withValues(alpha: alpha));
    }
    canvas.restore();

    final lastColumn = layout.columns - 1;
    final columnGap = layout.columns > 1 ? (size.width) / (layout.columns - 1) : size.width;
    for (final n in layout.nodes) {
      final isHovered = hover?.nodeId == n.id;
      canvas.drawRRect(RRect.fromRectAndRadius(n.rect, const Radius.circular(2)),
          Paint()..color = isHovered ? Color.lerp(n.color, Colors.black, 0.15)! : n.color);

      // Labels sit right of the node, except in the last column (left).
      final maxWidth = math.max(1.0, columnGap / 2 - n.rect.width - 10);
      final tp = layoutChartText(n.label, color: theme.axisColor, fontSize: 11, fontFamily: theme.fontFamily, maxWidth: maxWidth);
      final onLeft = n.column == lastColumn && layout.columns > 1;
      final x = onLeft ? n.rect.left - 6 - tp.width : n.rect.right + 6;
      tp.paint(canvas, Offset(x, n.rect.center.dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _SankeyPainter old) => true;
}
