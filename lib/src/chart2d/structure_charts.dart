import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'theme.dart';
import 'chart_chrome.dart';
import 'common.dart';
import 'controller.dart';
import 'time_axis.dart';

// ---------------------------------------------------------------------------
// Tree / org chart
// ---------------------------------------------------------------------------

/// A node of a [TreeChart2D].
class TreeChartNode {
  final String label;
  final String? subtitle;

  /// Accent color of the node's box (defaults to the palette by depth).
  final Color? color;
  final List<TreeChartNode> children;

  const TreeChartNode({required this.label, this.subtitle, this.color, this.children = const []});

  int get size => 1 + children.fold(0, (s, c) => s + c.size);
}

/// How a [TreeChart2D] grows.
enum TreeOrientation { topDown, leftToRight }

/// A tree diagram / org chart: boxes connected parent to children. Tap a
/// node with children to collapse or expand it; drag to pan, pinch or
/// scroll to zoom.
///
/// ```dart
/// TreeChart2D(root: TreeChartNode(label: 'CEO', children: [
///   TreeChartNode(label: 'CTO', subtitle: 'Engineering', children: [...]),
///   TreeChartNode(label: 'CFO', subtitle: 'Finance'),
/// ]))
/// ```
class TreeChart2D extends StatefulWidget {
  final TreeChartNode root;
  final TreeOrientation orientation;
  final String? title;
  final String? subtitle;
  final double nodeWidth;
  final double nodeHeight;

  /// Gap between levels and between siblings.
  final double levelGap;
  final double siblingGap;

  /// Levels shown expanded at first (deeper nodes start collapsed);
  /// null expands everything.
  final int? initialDepth;
  final List<Color> palette;
  final ChartController? controller;
  final ValueChanged<TreeChartNode>? onNodeTap;

  const TreeChart2D({
    super.key,
    required this.root,
    this.orientation = TreeOrientation.topDown,
    this.title,
    this.subtitle,
    this.nodeWidth = 132,
    this.nodeHeight = 46,
    this.levelGap = 38,
    this.siblingGap = 14,
    this.initialDepth,
    this.palette = const [Color(0xFF3949AB), Color(0xFF00897B), Color(0xFFF4511E), Color(0xFF8E24AA), Color(0xFF039BE5)],
    this.controller,
    this.onNodeTap,
  });

  @override
  State<TreeChart2D> createState() => _TreeChart2DState();
}

/// A laid-out visible node: model-space box centre, depth, parent index.
class _TreeBox {
  final TreeChartNode node;
  final int depth;
  final int? parent;
  final bool collapsed;
  Offset center = Offset.zero;
  _TreeBox(this.node, this.depth, this.parent, this.collapsed);
}

class _TreeChart2DState extends State<TreeChart2D> with ChartControllerMixin<TreeChart2D> {
  final Set<TreeChartNode> _collapsed = {};
  double _zoom = 1;
  Offset _pan = Offset.zero;
  double _startZoom = 1;
  Offset _startPan = Offset.zero, _startFocal = Offset.zero;

  @override
  ChartController? controllerOf(TreeChart2D widget) => widget.controller;

  @override
  void resetZoom() => setState(() {
        _zoom = 1;
        _pan = Offset.zero;
        reportZoomed(false);
      });

  @override
  void initState() {
    super.initState();
    _initCollapse();
  }

  @override
  void didUpdateWidget(covariant TreeChart2D old) {
    super.didUpdateWidget(old);
    if (!identical(old.root, widget.root)) {
      _collapsed.clear();
      _initCollapse();
    }
  }

  void _initCollapse() {
    final d = widget.initialDepth;
    if (d == null) return;
    void walk(TreeChartNode n, int depth) {
      if (depth >= d && n.children.isNotEmpty) _collapsed.add(n);
      for (final c in n.children) {
        walk(c, depth + 1);
      }
    }

    walk(widget.root, 0);
  }

  /// Tidy layout: leaves take consecutive slots along the breadth axis,
  /// parents sit centred over their children.
  (List<_TreeBox>, Rect) _layout() {
    final w = widget;
    final boxes = <_TreeBox>[];
    final down = w.orientation == TreeOrientation.topDown;
    final breadth = (down ? w.nodeWidth : w.nodeHeight) + w.siblingGap;
    final depthStep = (down ? w.nodeHeight : w.nodeWidth) + w.levelGap;
    var nextSlot = 0.0;
    double place(TreeChartNode n, int depth, int? parent) {
      final collapsed = _collapsed.contains(n);
      final i = boxes.length;
      boxes.add(_TreeBox(n, depth, parent, collapsed));
      double slot;
      if (collapsed || n.children.isEmpty) {
        slot = nextSlot;
        nextSlot += 1;
      } else {
        final slots = [for (final c in n.children) place(c, depth + 1, i)];
        slot = (slots.first + slots.last) / 2;
      }
      final b = slot * breadth, d = depth * depthStep;
      boxes[i].center = down ? Offset(b, d) : Offset(d, b);
      return slot;
    }

    place(w.root, 0, null);
    Rect bounds = Rect.zero;
    var first = true;
    for (final b in boxes) {
      final r = Rect.fromCenter(center: b.center, width: w.nodeWidth, height: w.nodeHeight);
      bounds = first ? r : bounds.expandToInclude(r);
      first = false;
    }
    return (boxes, bounds);
  }

  (double, Offset) _transform(Size size, Rect bounds) {
    const pad = 10.0;
    final fit = math.min(1.0, math.min((size.width - 2 * pad) / bounds.width, (size.height - 2 * pad) / bounds.height));
    final scale = fit * _zoom;
    return (scale, size.center(Offset.zero) - bounds.center * scale + _pan);
  }

  int? _hit(List<_TreeBox> boxes, Offset pos, (double, Offset) t) {
    for (int i = boxes.length - 1; i >= 0; i--) {
      final c = t.$2 + boxes[i].center * t.$1;
      final r = Rect.fromCenter(center: c, width: widget.nodeWidth * t.$1, height: widget.nodeHeight * t.$1);
      if (r.inflate(2).contains(pos)) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    final w = widget;
    final (boxes, bounds) = _layout();
    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Tree chart', w.title, [
        '${w.root.size} nodes, root ${w.root.label}',
        if (_collapsed.isNotEmpty) '${_collapsed.length} collapsed',
      ]),
      title: w.title,
      subtitle: w.subtitle,
      plot: LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest;
        final t = _transform(size, bounds);
        return Listener(
          onPointerSignal: (e) {
            if (e is! PointerScrollEvent) return;
            final f = math.exp(-e.scrollDelta.dy * 0.002);
            final z = (_zoom * f).clamp(0.3, 4.0);
            final (_, origin) = t;
            setState(() {
              _pan += (e.localPosition - origin) * (1 - z / _zoom);
              _zoom = z;
            });
            reportZoomed(true);
          },
          child: GestureDetector(
            onTapUp: (d) {
              final i = _hit(boxes, d.localPosition, t);
              if (i == null) return;
              final n = boxes[i].node;
              if (n.children.isNotEmpty) setState(() => _collapsed.contains(n) ? _collapsed.remove(n) : _collapsed.add(n));
              w.onNodeTap?.call(n);
            },
            onScaleStart: (d) {
              _startZoom = _zoom;
              _startPan = _pan;
              _startFocal = d.localFocalPoint;
            },
            onScaleUpdate: (d) {
              setState(() {
                _zoom = (_startZoom * d.scale).clamp(0.3, 4.0);
                _pan = _startPan + (d.localFocalPoint - _startFocal);
              });
              reportZoomed(true);
            },
            child: Stack(children: [
              CustomPaint(size: size, painter: _TreePainter(widget: w, boxes: boxes, transform: t, theme: theme)),
              if (_zoom != 1 || _pan != Offset.zero)
                Positioned(right: 8, top: 8, child: ChartResetZoomButton(theme: theme, onTap: resetZoom)),
            ]),
          ),
        );
      }),
    );
  }
}

class _TreePainter extends CustomPainter {
  final TreeChart2D widget;
  final List<_TreeBox> boxes;
  final (double, Offset) transform;
  final ChartTheme theme;

  _TreePainter({required this.widget, required this.boxes, required this.transform, required this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    final w = widget;
    final (s, o) = transform;
    final down = w.orientation == TreeOrientation.topDown;
    Offset at(Offset model) => o + model * s;
    final bw = w.nodeWidth * s, bh = w.nodeHeight * s;
    final link = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..color = theme.axisColor.withValues(alpha: theme.axisColor.a * 0.45);
    // Elbow connectors: down from the parent, across, down to the child.
    for (final b in boxes) {
      final p = b.parent;
      if (p == null) continue;
      final a = at(boxes[p].center), c = at(b.center);
      final path = Path();
      if (down) {
        final midY = (a.dy + bh / 2 + c.dy - bh / 2) / 2;
        path
          ..moveTo(a.dx, a.dy + bh / 2)
          ..lineTo(a.dx, midY)
          ..lineTo(c.dx, midY)
          ..lineTo(c.dx, c.dy - bh / 2);
      } else {
        final midX = (a.dx + bw / 2 + c.dx - bw / 2) / 2;
        path
          ..moveTo(a.dx + bw / 2, a.dy)
          ..lineTo(midX, a.dy)
          ..lineTo(midX, c.dy)
          ..lineTo(c.dx - bw / 2, c.dy);
      }
      canvas.drawPath(path, link);
    }
    for (final b in boxes) {
      final c = at(b.center);
      final r = Rect.fromCenter(center: c, width: bw, height: bh);
      if (!r.overlaps(Offset.zero & size)) continue;
      final accent = b.node.color ?? w.palette[b.depth % w.palette.length];
      final rr = RRect.fromRectAndRadius(r, Radius.circular(6 * s));
      canvas.drawRRect(rr, Paint()..color = theme.tooltipBackgroundColor);
      canvas.drawRRect(rr, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = accent.withValues(alpha: 0.7));
      canvas.save();
      canvas.clipRRect(rr);
      canvas.drawRect(Rect.fromLTWH(r.left, r.top, 4 * s, r.height), Paint()..color = accent);
      canvas.restore();
      if (s >= 0.45) {
        final title = layoutChartText(b.node.label,
            color: theme.tooltipTextColor, fontSize: 11.5 * s, fontWeight: FontWeight.w800, fontFamily: theme.fontFamily, maxWidth: bw - 14 * s);
        final sub = b.node.subtitle == null
            ? null
            : layoutChartText(b.node.subtitle!, color: theme.subtitleColor, fontSize: 10 * s, fontFamily: theme.fontFamily, maxWidth: bw - 14 * s);
        final h = title.height + (sub?.height ?? 0);
        title.paint(canvas, Offset(r.left + 9 * s, c.dy - h / 2));
        sub?.paint(canvas, Offset(r.left + 9 * s, c.dy - h / 2 + title.height));
      }
      // Collapsed nodes show how many are hidden below them.
      if (b.collapsed && b.node.children.isNotEmpty) {
        final hidden = b.node.size - 1;
        final tp = layoutChartText('+$hidden', color: Colors.white, fontSize: 9.5 * s, fontWeight: FontWeight.w800, fontFamily: theme.fontFamily);
        final badge = down ? Offset(c.dx, r.bottom) : Offset(r.right, c.dy);
        final br = RRect.fromRectAndRadius(Rect.fromCenter(center: badge, width: tp.width + 10 * s, height: tp.height + 4 * s), Radius.circular(10 * s));
        canvas.drawRRect(br, Paint()..color = accent);
        tp.paint(canvas, badge - Offset(tp.width / 2, tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TreePainter old) => true;
}

// ---------------------------------------------------------------------------
// Timeline
// ---------------------------------------------------------------------------

/// An event of a [TimelineChart2D]: a moment, or a span with [end].
class TimelineEvent {
  final DateTime start;
  final DateTime? end;
  final String title;
  final String? description;
  final Color? color;

  const TimelineEvent({required this.start, this.end, required this.title, this.description, this.color});

  bool get isSpan => end != null && end!.isAfter(start);
}

/// A timeline: events and periods along a time axis — releases and
/// incidents, project history, a company's story. Moments get labelled
/// cards on stems (alternating above and below, stacked so they never
/// overlap); spans get bars along the axis.
///
/// Drag to scroll, pinch or scroll to zoom; hover or tap an event.
class TimelineChart2D extends StatefulWidget {
  final List<TimelineEvent> events;
  final String? title;
  final String? subtitle;
  final String emptyStateMessage;
  final List<Color> palette;
  final String Function(DateTime time) dateFormatter;
  final ChartController? controller;
  final ValueChanged<TimelineEvent>? onEventTap;

  const TimelineChart2D({
    super.key,
    required this.events,
    this.title,
    this.subtitle,
    this.emptyStateMessage = 'No events',
    this.palette = const [Color(0xFF3949AB), Color(0xFF00897B), Color(0xFFF4511E), Color(0xFF8E24AA), Color(0xFF039BE5)],
    this.dateFormatter = formatTime,
    this.controller,
    this.onEventTap,
  });

  @override
  State<TimelineChart2D> createState() => _TimelineChart2DState();
}

/// A placed event: its card (moments) or bar (spans) in screen space.
class _Placed {
  final int index;
  final Rect box;
  final Offset anchor;
  final bool span;
  _Placed(this.index, this.box, this.anchor, this.span);
}

class _TimelineChart2DState extends State<TimelineChart2D> with ChartControllerMixin<TimelineChart2D> {
  (double, double)? _view;
  (double, double) _startView = (0, 1);
  double _startFocal = 0;
  int? _hover;

  @override
  ChartController? controllerOf(TimelineChart2D widget) => widget.controller;

  @override
  void resetZoom() => setState(() {
        _view = null;
        reportZoomed(false);
      });

  (double, double) get _full {
    var lo = double.infinity, hi = -double.infinity;
    for (final e in widget.events) {
      lo = math.min(lo, e.start.millisecondsSinceEpoch.toDouble());
      hi = math.max(hi, (e.end ?? e.start).millisecondsSinceEpoch.toDouble());
    }
    if (lo == hi) {
      lo -= 864e5;
      hi += 864e5;
    }
    final pad = (hi - lo) * 0.06;
    return (lo - pad, hi + pad);
  }

  Color _color(int i) => widget.events[i].color ?? widget.palette[i % widget.palette.length];

  List<_Placed> _place(Size size, ChartTheme theme, (double, double) view) {
    final w = widget;
    final axisY = size.height / 2;
    final (lo, hi) = view;
    double x(double ms) => 8 + (ms - lo) / (hi - lo) * (size.width - 16);
    final order = List.generate(w.events.length, (i) => i)..sort((a, b) => w.events[a].start.compareTo(w.events[b].start));
    final placed = <_Placed>[];
    // Spans: bars in lanes just below the axis.
    final spanLanes = <double>[];
    for (final i in order.where((i) => w.events[i].isSpan)) {
      final e = w.events[i];
      final a = x(e.start.millisecondsSinceEpoch.toDouble()), b = x(e.end!.millisecondsSinceEpoch.toDouble());
      var lane = spanLanes.indexWhere((end) => end < a - 4);
      if (lane < 0) {
        lane = spanLanes.length;
        spanLanes.add(b);
      } else {
        spanLanes[lane] = b;
      }
      final r = Rect.fromLTRB(a, axisY + 8 + lane * 16, math.max(a + 3, b), axisY + 8 + lane * 16 + 12);
      placed.add(_Placed(i, r, Offset(a, axisY), true));
    }
    final spanDepth = spanLanes.length * 16.0 + 10;
    // Moments: cards alternating above/below, each side in lanes.
    final lanes = <bool, List<double>>{true: [], false: []};
    var above = true;
    for (final i in order.where((i) => !w.events[i].isSpan)) {
      final e = w.events[i];
      final ax = x(e.start.millisecondsSinceEpoch.toDouble());
      final title = layoutChartText(e.title, color: theme.axisColor, fontSize: 11, fontWeight: FontWeight.w700, maxWidth: 150);
      final date = layoutChartText(w.dateFormatter(e.start), color: theme.subtitleColor, fontSize: 9.5, maxWidth: 150);
      final cw = math.max(title.width, date.width) + 14, ch = title.height + date.height + 8;
      final left = (ax - cw / 2).clamp(2.0, math.max(2.0, size.width - cw - 2)).toDouble();
      final side = lanes[above]!;
      var lane = side.indexWhere((end) => end < left - 6);
      if (lane < 0) {
        lane = side.length;
        side.add(left + cw);
      } else {
        side[lane] = left + cw;
      }
      final offset = 26 + lane * (ch + 8);
      final top = above ? axisY - offset - ch : axisY + spanDepth + offset - 16;
      placed.add(_Placed(i, Rect.fromLTWH(left, top, cw, ch), Offset(ax, axisY), false));
      above = !above;
    }
    return placed;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    final w = widget;
    if (w.events.isEmpty) {
      return ChartFrame(boundaryKey: chartBoundaryKey, title: w.title, subtitle: w.subtitle, plot: ChartEmptyState(message: w.emptyStateMessage));
    }
    final view = _view ?? _full;
    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Timeline', w.title, [
        '${w.events.length} events',
        for (final e in w.events.take(6)) '${w.dateFormatter(e.start)}: ${e.title}',
      ]),
      title: w.title,
      subtitle: w.subtitle,
      plot: LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest;
        final placed = _place(size, theme, view);
        int? hit(Offset p) {
          for (final pl in placed.reversed) {
            if (pl.box.inflate(3).contains(p) || (pl.anchor - p).distance < 7) return pl.index;
          }
          return null;
        }

        void zoom(double factor, double atX) {
          final (lo, hi) = view;
          final t = ((atX - 8) / (size.width - 16)).clamp(0.0, 1.0);
          final anchor = lo + (hi - lo) * t;
          final full = _full;
          final span = ((hi - lo) * factor).clamp(36e5, (full.$2 - full.$1) * 1.5);
          setState(() => _view = (anchor - span * t, anchor - span * t + span));
          reportZoomed(true);
        }

        return Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) zoom(math.exp(e.scrollDelta.dy * 0.002), e.localPosition.dx);
          },
          child: MouseRegion(
            onHover: (e) {
              final h = hit(e.localPosition);
              if (h != _hover) setState(() => _hover = h);
            },
            onExit: (_) => setState(() => _hover = null),
            child: GestureDetector(
              onTapUp: (d) {
                final h = hit(d.localPosition);
                setState(() => _hover = h);
                if (h != null) w.onEventTap?.call(w.events[h]);
              },
              onScaleStart: (d) {
                _startView = view;
                _startFocal = d.localFocalPoint.dx;
              },
              onScaleUpdate: (d) {
                final (lo, hi) = _startView;
                final span = (hi - lo) / d.horizontalScale.clamp(0.05, 20);
                final t = ((_startFocal - 8) / (size.width - 16)).clamp(0.0, 1.0);
                final anchor = lo + (hi - lo) * t;
                final shift = -(d.localFocalPoint.dx - _startFocal) / (size.width - 16) * span;
                setState(() => _view = (anchor - span * t + shift, anchor - span * t + span + shift));
                reportZoomed(true);
              },
              child: Stack(children: [
                CustomPaint(
                  size: size,
                  painter: _TimelinePainter(widget: w, placed: placed, view: view, colorOf: _color, theme: theme, hover: _hover),
                ),
                if (_view != null) Positioned(right: 8, top: 8, child: ChartResetZoomButton(theme: theme, onTap: resetZoom)),
                if (_hover != null && w.events[_hover!].description != null)
                  positionChartTooltip(
                    anchor: placed.firstWhere((p) => p.index == _hover).box.center,
                    areaSize: size,
                    cardWidth: 220,
                    child: ChartTooltipCard(
                      theme: theme,
                      width: 220,
                      title: w.events[_hover!].title,
                      subtitle: w.events[_hover!].description,
                      value: w.events[_hover!].isSpan
                          ? '${w.dateFormatter(w.events[_hover!].start)} – ${w.dateFormatter(w.events[_hover!].end!)}'
                          : w.dateFormatter(w.events[_hover!].start),
                    ),
                  ),
              ]),
            ),
          ),
        );
      }),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  final TimelineChart2D widget;
  final List<_Placed> placed;
  final (double, double) view;
  final Color Function(int) colorOf;
  final ChartTheme theme;
  final int? hover;

  _TimelinePainter({
    required this.widget,
    required this.placed,
    required this.view,
    required this.colorOf,
    required this.theme,
    required this.hover,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = widget;
    final axisY = size.height / 2;
    final (lo, hi) = view;
    double x(double ms) => 8 + (ms - lo) / (hi - lo) * (size.width - 16);
    canvas.drawLine(Offset(0, axisY), Offset(size.width, axisY), Paint()
      ..color = theme.axisColor
      ..strokeWidth = 2);
    for (final (ms, label) in timeTicks(lo, hi, maxTicks: math.max(2, (size.width / 110).floor()))) {
      final tx = x(ms);
      canvas.drawLine(Offset(tx, axisY - 4), Offset(tx, axisY + 4), Paint()
        ..color = theme.axisColor
        ..strokeWidth = 1.2);
      final tp = layoutChartText(label, color: theme.tickTextColor, fontSize: theme.tickFontSize, fontFamily: theme.fontFamily);
      tp.paint(canvas, Offset(tx + 3, axisY - tp.height - 3));
    }
    for (final p in placed) {
      final e = w.events[p.index];
      final color = colorOf(p.index);
      final dim = hover != null && hover != p.index;
      final c = dim ? color.withValues(alpha: color.a * 0.4) : color;
      if (p.span) {
        canvas.drawRRect(RRect.fromRectAndRadius(p.box, const Radius.circular(3)), Paint()..color = c);
        final tp = layoutChartText(e.title, color: contrastingTextColor(color), fontSize: 9.5, fontWeight: FontWeight.w700, fontFamily: theme.fontFamily, maxWidth: p.box.width - 6);
        if (p.box.width > 24) tp.paint(canvas, Offset(p.box.left + 3, p.box.center.dy - tp.height / 2));
        continue;
      }
      final stemEnd = p.box.top > axisY ? Offset(p.anchor.dx, p.box.top) : Offset(p.anchor.dx, p.box.bottom);
      canvas.drawLine(p.anchor, Offset(p.anchor.dx.clamp(p.box.left + 4, p.box.right - 4), stemEnd.dy), Paint()
        ..color = c
        ..strokeWidth = 1.2);
      canvas.drawCircle(p.anchor, hover == p.index ? 6 : 4.5, Paint()..color = c);
      canvas.drawCircle(p.anchor, hover == p.index ? 6 : 4.5, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = theme.tooltipBackgroundColor);
      final rr = RRect.fromRectAndRadius(p.box, const Radius.circular(5));
      canvas.drawRRect(rr, Paint()..color = theme.tooltipBackgroundColor);
      canvas.drawRRect(rr, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = hover == p.index ? 2 : 1.1
        ..color = c);
      final title = layoutChartText(e.title, color: dim ? theme.subtitleColor : theme.tooltipTextColor, fontSize: 11, fontWeight: FontWeight.w700, fontFamily: theme.fontFamily, maxWidth: 150);
      final date = layoutChartText(w.dateFormatter(e.start), color: c, fontSize: 9.5, fontWeight: FontWeight.w600, fontFamily: theme.fontFamily, maxWidth: 150);
      date.paint(canvas, p.box.topLeft + const Offset(7, 4));
      title.paint(canvas, p.box.topLeft + Offset(7, 4 + date.height));
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) => true;
}
