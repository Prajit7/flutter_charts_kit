import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'cartesian_axes.dart';
import 'theme.dart';
import 'chart_chrome.dart';
import 'common.dart';
import 'controller.dart';
import 'hover_plot.dart';

/// A node in a [TreemapChart2D]. Leaves carry a [value]; a node with
/// [children] is sized by the sum of its descendants and drawn as a labelled
/// group around them.
class TreemapNode {
  final String label;

  /// Size of a leaf. Ignored for nodes with [children].
  final double value;
  final List<TreemapNode> children;

  /// Defaults to the parent's color, or the chart palette at the top level.
  final Color? color;

  const TreemapNode({required this.label, this.value = 0, this.children = const [], this.color});

  bool get isLeaf => children.isEmpty;

  /// The leaf value, or the sum of all descendant leaves.
  double get total => isLeaf ? math.max(0, value) : children.fold(0.0, (s, c) => s + c.total);
}

/// A laid-out [TreemapNode]: where it sits and how deep it is.
class TreemapTile {
  final TreemapNode node;
  final Rect rect;
  final Color color;
  final int depth;

  /// Labels from the root down to (and including) this node.
  final List<String> path;

  const TreemapTile(this.node, this.rect, this.color, this.depth, this.path);

  // Same node = same tile, so hovering within a tile doesn't re-fire callbacks.
  @override
  bool operator ==(Object other) => other is TreemapTile && identical(other.node, node);

  @override
  int get hashCode => identityHashCode(node);
}

/// A treemap: nested rectangles whose areas are proportional to their
/// values — good for budgets, disk usage, portfolio weights.
///
/// ```dart
/// TreemapChart2D(
///   nodes: [
///     TreemapNode(label: 'Engineering', children: [
///       TreemapNode(label: 'Salaries', value: 820),
///       TreemapNode(label: 'Cloud', value: 240),
///     ]),
///     TreemapNode(label: 'Marketing', value: 310),
///   ],
/// )
/// ```
///
/// Uses the squarified layout, which keeps tiles close to square so their
/// sizes are easy to compare.
class TreemapChart2D extends StatefulWidget {
  final List<TreemapNode> nodes;
  final String? title;
  final String? subtitle;
  final String emptyStateMessage;
  final String Function(double value) valueFormatter;

  /// Top-level colors, cycled. Children inherit their parent's color.
  final List<Color> palette;

  /// Space between sibling tiles.
  final double gap;

  /// Height of the label strip at the top of each group (node with children).
  final double groupHeaderHeight;
  final bool enableAnimation;
  final Duration animationDuration;

  /// Replaces the default tooltip card.
  final Widget Function(BuildContext context, TreemapTile tile)? tooltipBuilder;

  /// Export an image from outside the chart.
  final ChartController? controller;
  final ValueChanged<TreemapTile>? onTileTap;

  const TreemapChart2D({
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
      Color(0xFF6D4C41),
      Color(0xFF039BE5),
      Color(0xFFC0CA33),
      Color(0xFFD81B60),
    ],
    this.gap = 2,
    this.groupHeaderHeight = 18,
    this.enableAnimation = true,
    this.animationDuration = const Duration(milliseconds: 500),
    this.tooltipBuilder,
    this.controller,
    this.onTileTap,
  });

  @override
  State<TreemapChart2D> createState() => _TreemapChart2DState();
}

/// Squarified treemap layout (Bruls, Huizing & van Wijk): fills [rect] with
/// rows of tiles, adding each next-largest item to the current row only
/// while that keeps the row's worst aspect ratio from getting worse.
List<Rect> squarify(List<double> values, Rect rect) {
  final result = List<Rect>.filled(values.length, Rect.zero);
  final total = values.fold(0.0, (s, v) => s + v);
  if (total <= 0 || rect.isEmpty) return result;

  // Lay out largest-first; remember original positions.
  final order = List<int>.generate(values.length, (i) => i)..sort((a, b) => values[b].compareTo(values[a]));
  final scale = rect.width * rect.height / total;
  final areas = [for (final i in order) values[i] * scale];

  var free = rect;
  int start = 0;
  while (start < areas.length) {
    final side = math.min(free.width, free.height);
    double worst(int end) {
      // Worst aspect ratio of areas[start..end) laid along `side`.
      final row = areas.sublist(start, end);
      final sum = row.fold(0.0, (s, a) => s + a);
      if (sum <= 0) return double.infinity;
      final maxA = row.reduce(math.max), minA = row.reduce(math.min);
      return math.max(side * side * maxA / (sum * sum), sum * sum / (side * side * math.max(minA, 1e-9)));
    }

    int end = start + 1;
    while (end < areas.length && worst(end + 1) <= worst(end)) {
      end++;
    }

    final rowSum = areas.sublist(start, end).fold(0.0, (s, a) => s + a);
    final horizontal = free.width >= free.height; // row runs down the short (left) side
    final thickness = rowSum / side;
    double offset = 0;
    for (int k = start; k < end; k++) {
      final length = side == 0 ? 0.0 : areas[k] / thickness;
      result[order[k]] = horizontal
          ? Rect.fromLTWH(free.left, free.top + offset, thickness, length)
          : Rect.fromLTWH(free.left + offset, free.top, length, thickness);
      offset += length;
    }
    free = horizontal
        ? Rect.fromLTRB(free.left + thickness, free.top, free.right, free.bottom)
        : Rect.fromLTRB(free.left, free.top + thickness, free.right, free.bottom);
    start = end;
  }
  return result;
}

class _TreemapChart2DState extends State<TreemapChart2D> with ChartControllerMixin<TreemapChart2D> {
  @override
  ChartController? controllerOf(TreemapChart2D widget) => widget.controller;

  @override
  void resetZoom() {} // no zoom on this chart

  /// All tiles, parents before their children (so children paint on top).
  List<TreemapTile> _layout(Size size) {
    final tiles = <TreemapTile>[];
    void place(List<TreemapNode> nodes, Rect area, int depth, Color? inherited, List<String> path) {
      final visible = nodes.where((n) => n.total > 0).toList();
      final rects = squarify([for (final n in visible) n.total], area);
      for (int i = 0; i < visible.length; i++) {
        final n = visible[i];
        final color = n.color ?? inherited ?? widget.palette[i % widget.palette.length];
        final r = rects[i].deflate(widget.gap / 2);
        if (r.width <= 0 || r.height <= 0) continue;
        final tile = TreemapTile(n, r, color, depth, [...path, n.label]);
        tiles.add(tile);
        if (!n.isLeaf) {
          // Children fill the group below its header strip (dropped when too small).
          final header = r.height > widget.groupHeaderHeight * 2.5 ? widget.groupHeaderHeight : 0.0;
          place(n.children, Rect.fromLTRB(r.left, r.top + header, r.right, r.bottom), depth + 1, color, tile.path);
        }
      }
    }

    place(widget.nodes, Offset.zero & size, 0, null, const []);
    return tiles;
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
    final grandTotal = widget.nodes.fold(0.0, (s, n) => s + n.total);
    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Treemap', widget.title, [for (final n in widget.nodes) '${n.label}: ${widget.valueFormatter(n.total)}']),
      title: widget.title,
      subtitle: widget.subtitle,
      plot: HoverPlot<TreemapTile>(
        enableAnimation: widget.enableAnimation,
        animationDuration: widget.animationDuration,
        animationKey: grandTotal,
        onTap: widget.onTileTap,
        hitTest: (pos, size) {
          // Deepest tile under the pointer: the leaf, not its group.
          TreemapTile? hit;
          for (final t in _layout(size)) {
            if (t.rect.contains(pos) && t.node.isLeaf) hit = t;
          }
          return hit;
        },
        painterBuilder: (size, hover, progress) => _TreemapPainter(
          tiles: _layout(size),
          valueFormatter: widget.valueFormatter,
          headerHeight: widget.groupHeaderHeight,
          theme: theme,
          hover: hover,
          progress: progress,
        ),
        tooltipBuilder: (context, tile, pointer, size) {
          final custom = widget.tooltipBuilder;
          return positionChartTooltip(
            anchor: pointer,
            areaSize: size,
            cardWidth: 170,
            child: custom != null
                ? custom(context, tile)
                : ChartTooltipCard(
                    theme: theme,
                    width: 170,
                    title: tile.path.join(' › '),
                    subtitle: '${(tile.node.total / grandTotal * 100).toStringAsFixed(1)}% of total',
                    value: widget.valueFormatter(tile.node.total),
                  ),
          );
        },
      ),
    );
  }
}

class _TreemapPainter extends CustomPainter {
  final List<TreemapTile> tiles;
  final String Function(double) valueFormatter;
  final double headerHeight;
  final ChartTheme theme;
  final TreemapTile? hover;
  final double progress;

  _TreemapPainter({
    required this.tiles,
    required this.valueFormatter,
    required this.headerHeight,
    required this.theme,
    required this.hover,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final t in tiles) {
      // Entrance: groups appear first, then deeper levels.
      final p = ((progress * 1.6 - t.depth * 0.3)).clamp(0.0, 1.0);
      if (p == 0) continue;
      final isHovered = hover != null && identical(hover!.node, t.node);
      if (t.node.isLeaf) {
        // Leaves shade lighter with depth so siblings in a group stay distinct.
        final base = Color.lerp(t.color, Colors.white, (t.depth * 0.12).clamp(0.0, 0.4))!;
        final color = isHovered ? Color.lerp(base, Colors.black, 0.12)! : base;
        canvas.drawRRect(RRect.fromRectAndRadius(t.rect, const Radius.circular(2)),
            Paint()..color = color.withValues(alpha: color.a * p));
        if (p >= 1) _label(canvas, t, contrastingTextColor(color));
      } else {
        canvas.drawRRect(RRect.fromRectAndRadius(t.rect, const Radius.circular(3)),
            Paint()..color = t.color.withValues(alpha: 0.18 * p));
        if (t.rect.height > headerHeight * 2.5 && p >= 1) {
          final tp = layoutChartText(t.node.label,
              color: theme.axisColor, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: theme.fontFamily, maxWidth: math.max(1, t.rect.width - 8));
          tp.paint(canvas, t.rect.topLeft + Offset(4, (headerHeight - tp.height) / 2));
        }
      }
    }
  }

  /// Label + value in the tile's top-left, only if it fits.
  void _label(Canvas canvas, TreemapTile t, Color color) {
    final r = t.rect;
    if (r.width < 28 || r.height < 16) return;
    final name = layoutChartText(t.node.label, color: color, fontSize: 11, fontFamily: theme.fontFamily, maxWidth: r.width - 8);
    name.paint(canvas, r.topLeft + const Offset(4, 3));
    final value = layoutChartText(valueFormatter(t.node.total),
        color: color.withValues(alpha: 0.85), fontSize: 10, fontWeight: FontWeight.w400, fontFamily: theme.fontFamily, maxWidth: r.width - 8);
    if (name.height + value.height + 6 <= r.height) value.paint(canvas, r.topLeft + Offset(4, 3 + name.height));
  }

  @override
  bool shouldRepaint(covariant _TreemapPainter old) => true;
}
