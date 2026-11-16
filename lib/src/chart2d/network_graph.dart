import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'theme.dart';
import 'chart_chrome.dart';
import 'common.dart';
import 'controller.dart';

/// A node of a [NetworkGraph2D].
class GraphNode {
  final String id;

  /// Shown on the node; defaults to [id].
  final String? label;

  /// Nodes in the same group share a palette color.
  final String? group;

  /// Scales the node's size (area ∝ value). Defaults to its degree.
  final double? value;
  final Color? color;

  const GraphNode({required this.id, this.label, this.group, this.value, this.color});
}

/// A link between two [GraphNode]s, by id.
class GraphEdge {
  final String source;
  final String target;

  /// Thicker, and a slightly stronger spring, for larger weights.
  final double weight;

  const GraphEdge(this.source, this.target, {this.weight = 1});
}

/// A force-directed network graph: nodes repel, links pull — clusters and
/// bridges emerge on their own. Good for dependency graphs, social and
/// organisational networks, knowledge maps.
///
/// ```dart
/// NetworkGraph2D(
///   nodes: [GraphNode(id: 'api', group: 'backend'), GraphNode(id: 'web', group: 'frontend')],
///   edges: [GraphEdge('web', 'api')],
/// )
/// ```
///
/// Drag a node to move it (the layout reacts), drag the background to pan,
/// pinch or scroll to zoom. Hovering a node highlights its neighbours.
class NetworkGraph2D extends StatefulWidget {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final String? title;
  final String? subtitle;
  final String emptyStateMessage;
  final List<Color> palette;

  /// Draw edges as arrows from source to target.
  final bool directed;
  final bool showLabels;

  /// Preferred edge length, in layout units (≈ pixels at zoom 1).
  final double linkDistance;

  /// How strongly nodes push apart.
  final double repulsion;

  /// Animate the layout settling (true), or compute it up front (false —
  /// deterministic, e.g. for screenshots).
  final bool enableAnimation;
  final Widget Function(BuildContext context, GraphNode node, int degree)? tooltipBuilder;
  final ChartController? controller;
  final ValueChanged<GraphNode>? onNodeTap;

  const NetworkGraph2D({
    super.key,
    required this.nodes,
    required this.edges,
    this.title,
    this.subtitle,
    this.emptyStateMessage = 'No nodes',
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
    this.directed = false,
    this.showLabels = true,
    this.linkDistance = 60,
    this.repulsion = 260,
    this.enableAnimation = true,
    this.tooltipBuilder,
    this.controller,
    this.onNodeTap,
  });

  @override
  State<NetworkGraph2D> createState() => _NetworkGraph2DState();
}

/// One simulated body.
class _Body {
  final GraphNode node;
  final double radius;
  double x, y, vx = 0, vy = 0;

  /// Pinned position while being dragged.
  double? fx, fy;

  _Body(this.node, this.radius, this.x, this.y);
}

class _NetworkGraph2DState extends State<NetworkGraph2D>
    with SingleTickerProviderStateMixin, ChartControllerMixin<NetworkGraph2D> {
  List<_Body> _bodies = [];
  List<(int, int, double)> _links = []; // (source, target, weight) by body index
  Map<String, int> _index = {};
  List<Set<int>> _neighbours = [];
  late final Ticker _ticker;
  double _alpha = 1;

  /// User view transform (pan/zoom) on top of the auto-fit, once they touch it.
  Offset _pan = Offset.zero;
  double _zoom = 1;
  bool _userMoved = false;
  final ValueNotifier<int> _frame = ValueNotifier(0);
  final ValueNotifier<(int, Offset)?> _hover = ValueNotifier(null);
  int? _dragging;
  Offset _gestureStartPan = Offset.zero;
  double _gestureStartZoom = 1;
  Offset _gestureStartFocal = Offset.zero;

  @override
  ChartController? controllerOf(NetworkGraph2D widget) => widget.controller;

  @override
  void resetZoom() {
    _pan = Offset.zero;
    _zoom = 1;
    _userMoved = false;
    reportZoomed(false);
    _frame.value++;
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _step());
    _build();
  }

  @override
  void didUpdateWidget(covariant NetworkGraph2D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.nodes, widget.nodes) || !identical(oldWidget.edges, widget.edges)) _build();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    _hover.dispose();
    super.dispose();
  }

  /// Bodies start on a phyllotaxis spiral (evenly spread, deterministic);
  /// existing nodes keep their positions when the data changes.
  void _build() {
    final old = {for (final b in _bodies) b.node.id: b};
    final degree = <String, int>{};
    for (final e in widget.edges) {
      degree[e.source] = (degree[e.source] ?? 0) + 1;
      degree[e.target] = (degree[e.target] ?? 0) + 1;
    }
    _bodies = [
      for (int i = 0; i < widget.nodes.length; i++)
        () {
          final n = widget.nodes[i];
          final r = 5 + 2.2 * math.sqrt(math.max(1.0, n.value ?? (degree[n.id] ?? 0).toDouble()));
          final prev = old[n.id];
          final a = i * math.pi * (3 - math.sqrt(5)), d = 10 * math.sqrt(i + 0.5);
          return _Body(n, r, prev?.x ?? d * math.cos(a), prev?.y ?? d * math.sin(a));
        }(),
    ];
    _index = {for (int i = 0; i < _bodies.length; i++) _bodies[i].node.id: i};
    _links = [
      for (final e in widget.edges)
        if (_index.containsKey(e.source) && _index.containsKey(e.target) && e.source != e.target)
          (_index[e.source]!, _index[e.target]!, e.weight),
    ];
    _neighbours = [for (int i = 0; i < _bodies.length; i++) <int>{}];
    for (final (a, b, _) in _links) {
      _neighbours[a].add(b);
      _neighbours[b].add(a);
    }
    _alpha = 1;
    if (widget.enableAnimation) {
      if (!_ticker.isActive) _ticker.start();
    } else {
      for (int i = 0; i < 300 && _alpha > 0.001; i++) {
        _tick();
      }
      _frame.value++;
    }
  }

  void _step() {
    _tick();
    _frame.value++;
    if (_alpha <= 0.001 && _dragging == null) _ticker.stop();
  }

  /// One simulation step (velocity Verlet with decaying "temperature").
  void _tick() {
    final n = _bodies.length;
    _alpha += (0 - _alpha) * 0.0228;
    // Links: springs toward linkDistance.
    for (final (a, b, w) in _links) {
      final p = _bodies[a], q = _bodies[b];
      var dx = q.x + q.vx - p.x - p.vx, dy = q.y + q.vy - p.y - p.vy;
      final dist = math.max(1e-6, math.sqrt(dx * dx + dy * dy));
      final k = (dist - widget.linkDistance) / dist * _alpha * 0.3 * math.min(2, w);
      dx *= k;
      dy *= k;
      // Spread the pull by degree, so hubs don't get yanked around.
      final da = _neighbours[a].length, db = _neighbours[b].length;
      final bias = da / math.max(1, da + db);
      q.vx -= dx * bias;
      q.vy -= dy * bias;
      p.vx += dx * (1 - bias);
      p.vy += dy * (1 - bias);
    }
    // Repulsion (all pairs) and collision.
    for (int i = 0; i < n; i++) {
      final p = _bodies[i];
      for (int j = i + 1; j < n; j++) {
        final q = _bodies[j];
        var dx = q.x - p.x, dy = q.y - p.y;
        var d2 = dx * dx + dy * dy;
        if (d2 < 1e-6) {
          dx = (i - j) * 1e-3;
          dy = 1e-3;
          d2 = dx * dx + dy * dy;
        }
        final f = widget.repulsion * _alpha / d2;
        p.vx -= dx * f;
        p.vy -= dy * f;
        q.vx += dx * f;
        q.vy += dy * f;
        final minD = p.radius + q.radius + 3, d = math.sqrt(d2);
        if (d < minD) {
          final push = (minD - d) / d * 0.5;
          p.vx -= dx * push;
          p.vy -= dy * push;
          q.vx += dx * push;
          q.vy += dy * push;
        }
      }
    }
    // Gentle pull to the centre, then integrate with friction.
    for (final b in _bodies) {
      b.vx -= b.x * 0.02 * _alpha;
      b.vy -= b.y * 0.02 * _alpha;
      if (b.fx != null) {
        b.x = b.fx!;
        b.y = b.fy!;
        b.vx = b.vy = 0;
        continue;
      }
      b.vx *= 0.6;
      b.vy *= 0.6;
      b.x += b.vx;
      b.y += b.vy;
    }
  }

  /// Model → screen: fit the layout's bounds into [size], then apply the
  /// user's pan/zoom.
  (double, Offset) _transform(Size size) {
    if (_bodies.isEmpty) return (1, size.center(Offset.zero));
    double x0 = double.infinity, y0 = double.infinity, x1 = -double.infinity, y1 = -double.infinity;
    for (final b in _bodies) {
      x0 = math.min(x0, b.x - b.radius);
      y0 = math.min(y0, b.y - b.radius);
      x1 = math.max(x1, b.x + b.radius);
      y1 = math.max(y1, b.y + b.radius);
    }
    final pad = widget.showLabels ? 26.0 : 10.0;
    final fit = math.min(3.0, math.min((size.width - 2 * pad) / math.max(1, x1 - x0), (size.height - 2 * pad) / math.max(1, y1 - y0)));
    final scale = fit * _zoom;
    final center = size.center(Offset.zero) - Offset((x0 + x1) / 2, (y0 + y1) / 2) * scale + _pan;
    return (scale, center);
  }

  Offset _screen(_Body b, (double, Offset) t) => t.$2 + Offset(b.x, b.y) * t.$1;

  int? _nodeAt(Offset p, Size size) {
    final t = _transform(size);
    for (int i = _bodies.length - 1; i >= 0; i--) {
      if ((_screen(_bodies[i], t) - p).distance <= math.max(8, _bodies[i].radius * t.$1 + 3)) return i;
    }
    return null;
  }

  Color _color(GraphNode n) {
    if (n.color != null) return n.color!;
    final groups = <String?>[];
    for (final x in widget.nodes) {
      if (!groups.contains(x.group)) groups.add(x.group);
    }
    return widget.palette[groups.indexOf(n.group) % widget.palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    if (widget.nodes.isEmpty) {
      return ChartFrame(
        boundaryKey: chartBoundaryKey,
        title: widget.title,
        subtitle: widget.subtitle,
        plot: ChartEmptyState(message: widget.emptyStateMessage),
      );
    }
    final groups = {for (final n in widget.nodes) n.group}.whereType<String>();
    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Network graph', widget.title, [
        '${widget.nodes.length} nodes, ${_links.length} links',
        if (groups.isNotEmpty) 'groups: ${groups.join(', ')}',
      ]),
      title: widget.title,
      subtitle: widget.subtitle,
      plot: LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest;
        return Listener(
          onPointerSignal: (e) {
            if (e is! PointerScrollEvent) return;
            final f = math.exp(-e.scrollDelta.dy * 0.002);
            _zoomAround(e.localPosition, f, size);
          },
          child: MouseRegion(
            onHover: (e) {
              final i = _nodeAt(e.localPosition, size);
              _hover.value = i == null ? null : (i, e.localPosition);
            },
            onExit: (_) => _hover.value = null,
            child: GestureDetector(
              onTapUp: (d) {
                final i = _nodeAt(d.localPosition, size);
                _hover.value = i == null ? null : (i, d.localPosition);
                if (i != null) widget.onNodeTap?.call(_bodies[i].node);
              },
              onScaleStart: (d) {
                _dragging = d.pointerCount == 1 ? _nodeAt(d.localFocalPoint, size) : null;
                _gestureStartPan = _pan;
                _gestureStartZoom = _zoom;
                _gestureStartFocal = d.localFocalPoint;
                if (_dragging != null) {
                  final b = _bodies[_dragging!];
                  b.fx = b.x;
                  b.fy = b.y;
                  // Reheat so neighbours follow the dragged node.
                  _alpha = math.max(_alpha, 0.3);
                  if (!_ticker.isActive) _ticker.start();
                }
              },
              onScaleUpdate: (d) {
                _hover.value = null;
                final drag = _dragging;
                if (drag != null) {
                  final (scale, origin) = _transform(size);
                  final p = (d.localFocalPoint - origin) / scale;
                  _bodies[drag]
                    ..fx = p.dx
                    ..fy = p.dy;
                  return;
                }
                _userMoved = true;
                reportZoomed(true);
                _zoom = (_gestureStartZoom * d.scale).clamp(0.2, 8.0);
                _pan = _gestureStartPan + (d.localFocalPoint - _gestureStartFocal);
                _frame.value++;
              },
              onScaleEnd: (_) {
                final drag = _dragging;
                if (drag != null) {
                  _bodies[drag]
                    ..fx = null
                    ..fy = null;
                }
                _dragging = null;
              },
              child: AnimatedBuilder(
                animation: Listenable.merge([_frame, _hover]),
                builder: (context, _) {
                  final hover = _hover.value;
                  final t = _transform(size);
                  return Stack(children: [
                    CustomPaint(
                      size: size,
                      painter: _GraphPainter(state: this, transform: t, theme: theme, hovered: hover?.$1),
                    ),
                    if (_userMoved) Positioned(right: 8, top: 8, child: ChartResetZoomButton(theme: theme, onTap: resetZoom)),
                    if (hover != null)
                      positionChartTooltip(
                        anchor: _screen(_bodies[hover.$1], t),
                        areaSize: size,
                        cardWidth: 170,
                        child: widget.tooltipBuilder?.call(context, _bodies[hover.$1].node, _neighbours[hover.$1].length) ??
                            ChartTooltipCard(
                              theme: theme,
                              width: 170,
                              title: _bodies[hover.$1].node.label ?? _bodies[hover.$1].node.id,
                              subtitle: _bodies[hover.$1].node.group,
                              value: '${_neighbours[hover.$1].length} connection${_neighbours[hover.$1].length == 1 ? '' : 's'}',
                            ),
                      ),
                  ]);
                },
              ),
            ),
          ),
        );
      }),
    );
  }

  void _zoomAround(Offset p, double factor, Size size) {
    final newZoom = (_zoom * factor).clamp(0.2, 8.0);
    final f = newZoom / _zoom;
    // Keep the point under the pointer fixed.
    final (_, origin) = _transform(size);
    _pan += (p - origin) * (1 - f);
    _zoom = newZoom;
    _userMoved = true;
    reportZoomed(true);
    _frame.value++;
  }
}

class _GraphPainter extends CustomPainter {
  final _NetworkGraph2DState state;
  final (double, Offset) transform;
  final ChartTheme theme;
  final int? hovered;

  _GraphPainter({required this.state, required this.transform, required this.theme, required this.hovered});

  @override
  void paint(Canvas canvas, Size size) {
    final s = state;
    final (scale, _) = transform;
    final focus = hovered == null ? null : {hovered!, ...s._neighbours[hovered!]};
    final edgeColor = theme.axisColor;

    for (final (a, b, w) in s._links) {
      final p = s._screen(s._bodies[a], transform), q = s._screen(s._bodies[b], transform);
      final lit = focus == null || (focus.contains(a) && focus.contains(b) && (a == hovered || b == hovered));
      final paint = Paint()
        ..color = edgeColor.withValues(alpha: edgeColor.a * (lit ? (focus == null ? 0.3 : 0.75) : 0.08))
        ..strokeWidth = math.min(4, 0.8 + w * 0.6);
      canvas.drawLine(p, q, paint);
      if (s.widget.directed) {
        // Arrowhead at the target's rim.
        final dir = q - p;
        final len = dir.distance;
        if (len < 1) continue;
        final u = dir / len;
        final tip = q - u * (s._bodies[b].radius * scale + 1);
        final n = Offset(-u.dy, u.dx);
        canvas.drawPath(
          Path()
            ..moveTo(tip.dx, tip.dy)
            ..lineTo(tip.dx - u.dx * 7 + n.dx * 3.5, tip.dy - u.dy * 7 + n.dy * 3.5)
            ..lineTo(tip.dx - u.dx * 7 - n.dx * 3.5, tip.dy - u.dy * 7 - n.dy * 3.5)
            ..close(),
          Paint()..color = paint.color,
        );
      }
    }

    for (int i = 0; i < s._bodies.length; i++) {
      final b = s._bodies[i];
      final p = s._screen(b, transform);
      final dim = focus != null && !focus.contains(i);
      final color = s._color(b.node);
      final r = b.radius * scale.clamp(0.5, 2.0);
      canvas.drawCircle(p, r, Paint()..color = dim ? color.withValues(alpha: 0.25) : color);
      canvas.drawCircle(p, r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = i == hovered ? 2.5 : 1.2
        ..color = i == hovered ? theme.axisColor : theme.tooltipBackgroundColor);
      if (s.widget.showLabels && !dim) {
        final tp = layoutChartText(b.node.label ?? b.node.id,
            color: theme.axisColor.withValues(alpha: theme.axisColor.a * (dim ? 0.3 : 1)), fontSize: 10, fontFamily: theme.fontFamily);
        tp.paint(canvas, p + Offset(-tp.width / 2, r + 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter old) => true;
}
