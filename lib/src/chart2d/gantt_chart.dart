import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'theme.dart';
import 'chart_chrome.dart';
import 'common.dart';
import 'controller.dart';
import 'time_axis.dart';

/// One bar (or milestone) of a [GanttChart2D].
class GanttTask {
  /// Unique id, used by [dependsOn]. Defaults to [label].
  final String? id;
  final String label;
  final DateTime start;

  /// Same as [start] for a milestone (drawn as a diamond).
  final DateTime end;

  /// Fraction done, 0–1, shown as a darker portion of the bar.
  final double? progress;

  /// Section heading the task is listed under (rows are grouped by it, in
  /// order of first appearance).
  final String? group;

  /// Ids of tasks that must finish first; drawn as arrows.
  final List<String> dependsOn;
  final Color? color;

  const GanttTask({
    this.id,
    required this.label,
    required this.start,
    required this.end,
    this.progress,
    this.group,
    this.dependsOn = const [],
    this.color,
  });

  /// A zero-length milestone.
  GanttTask.milestone({this.id, required this.label, required DateTime at, this.group, this.dependsOn = const [], this.color})
      : start = at,
        end = at,
        progress = null;

  String get key => id ?? label;
  bool get isMilestone => !end.isAfter(start);
}

/// A Gantt chart: tasks as bars along a time axis, with progress,
/// milestones, dependency arrows and a "today" marker.
///
/// ```dart
/// GanttChart2D(tasks: [
///   GanttTask(id: 'design', label: 'Design', start: DateTime(2026, 3, 2), end: DateTime(2026, 3, 13), progress: 1),
///   GanttTask(id: 'build', label: 'Build', start: DateTime(2026, 3, 16), end: DateTime(2026, 4, 10),
///       progress: 0.4, dependsOn: ['design']),
///   GanttTask.milestone(label: 'Launch', at: DateTime(2026, 4, 15), dependsOn: ['build']),
/// ])
/// ```
///
/// Drag to scroll the timeline, pinch or use the mouse wheel to zoom.
class GanttChart2D extends StatefulWidget {
  final List<GanttTask> tasks;
  final String? title;
  final String? subtitle;
  final String emptyStateMessage;

  /// Colors for tasks without their own, cycled by group (or task).
  final List<Color> palette;

  /// Draw a vertical line at this time; defaults to now. Set
  /// [showToday] false to hide it.
  final DateTime? today;
  final bool showToday;
  final bool showDependencies;

  /// Largest row height; rows shrink to fit the available height.
  final double maxRowHeight;

  /// Width of the task-name column (capped at a third of the chart).
  final double labelWidth;

  /// Formats dates in the tooltip; defaults to "3 Mar 2026".
  final String Function(DateTime date)? dateFormatter;
  final Widget Function(BuildContext context, GanttTask task)? tooltipBuilder;
  final ChartController? controller;
  final ValueChanged<GanttTask>? onTaskTap;

  const GanttChart2D({
    super.key,
    required this.tasks,
    this.title,
    this.subtitle,
    this.emptyStateMessage = 'No tasks',
    this.palette = const [Color(0xFF5C6BC0), Color(0xFF26A69A), Color(0xFFFFA726), Color(0xFFAB47BC), Color(0xFF42A5F5), Color(0xFFEC407A)],
    this.today,
    this.showToday = true,
    this.showDependencies = true,
    this.maxRowHeight = 30,
    this.labelWidth = 140,
    this.dateFormatter,
    this.tooltipBuilder,
    this.controller,
    this.onTaskTap,
  });

  @override
  State<GanttChart2D> createState() => _GanttChart2DState();
}

/// A row: a group heading (task null) or a task.
typedef _Row = ({String? group, GanttTask? task});

class _GanttLayout {
  final List<_Row> rows;
  final Rect chart; // the timeline area (excluding the name column and date header)
  final double rowHeight;
  final double lo; // ms at the left edge
  final double hi; // ms at the right edge

  _GanttLayout(this.rows, this.chart, this.rowHeight, this.lo, this.hi);

  double x(DateTime t) => chart.left + (t.millisecondsSinceEpoch - lo) / (hi - lo) * chart.width;
  double timeAt(double screenX) => lo + (screenX - chart.left) / chart.width * (hi - lo);
  Rect rowRect(int r) => Rect.fromLTWH(0, chart.top + r * rowHeight, chart.right, rowHeight);

  Rect barOf(int r) {
    final t = rows[r].task!;
    final y = chart.top + r * rowHeight;
    final pad = rowHeight * 0.22;
    return Rect.fromLTRB(x(t.start), y + pad, math.max(x(t.end), x(t.start) + 2), y + rowHeight - pad);
  }
}

class _GanttChart2DState extends State<GanttChart2D> with ChartControllerMixin<GanttChart2D> {
  final ValueNotifier<(int, Offset)?> _hover = ValueNotifier(null);
  final ValueNotifier<(double, double)?> _view = ValueNotifier(null);
  (double, double)? _gestureView;
  double _gestureFocalX = 0;
  Rect _gestureChart = Rect.zero;

  @override
  ChartController? controllerOf(GanttChart2D widget) => widget.controller;

  @override
  void resetZoom() => _view.value = null;

  @override
  void initState() {
    super.initState();
    _view.addListener(() => reportZoomed(_view.value != null));
  }

  @override
  void dispose() {
    _hover.dispose();
    _view.dispose();
    super.dispose();
  }

  List<_Row> get _rows {
    final groups = <String?>[];
    for (final t in widget.tasks) {
      if (!groups.contains(t.group)) groups.add(t.group);
    }
    return [
      for (final g in groups) ...[
        if (g != null) (group: g, task: null),
        for (final t in widget.tasks.where((t) => t.group == g)) (group: g, task: t),
      ],
    ];
  }

  (double, double) get _defaultView {
    final start = widget.tasks.map((t) => t.start.millisecondsSinceEpoch).reduce(math.min).toDouble();
    final end = widget.tasks.map((t) => t.end.millisecondsSinceEpoch).reduce(math.max).toDouble();
    final pad = math.max((end - start) * 0.04, const Duration(hours: 12).inMilliseconds.toDouble());
    return (start - pad, end + pad);
  }

  _GanttLayout _layout(Size size, ChartTheme theme) {
    final rows = _rows;
    final labelW = math.min(widget.labelWidth, size.width / 3);
    const header = 24.0;
    final rowH = math.min(widget.maxRowHeight, math.max(8.0, (size.height - header) / rows.length));
    final (lo, hi) = _view.value ?? _defaultView;
    return _GanttLayout(rows, Rect.fromLTRB(labelW, header, size.width, header + rowH * rows.length), rowH, lo, hi);
  }

  Color _color(GanttTask t) {
    if (t.color != null) return t.color!;
    final groups = <String?>[];
    for (final x in widget.tasks) {
      if (!groups.contains(x.group)) groups.add(x.group);
    }
    final i = t.group == null ? widget.tasks.indexOf(t) : groups.indexOf(t.group);
    return widget.palette[i % widget.palette.length];
  }

  String _date(DateTime d) => widget.dateFormatter?.call(d) ?? formatTime(d);

  void _setView(double lo, double hi) {
    final (d0, d1) = _defaultView;
    final full = d1 - d0;
    final span = (hi - lo).clamp(const Duration(hours: 6).inMilliseconds.toDouble(), full * 4);
    _view.value = (lo, lo + span);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    if (widget.tasks.isEmpty) {
      return ChartFrame(
        boundaryKey: chartBoundaryKey,
        title: widget.title,
        subtitle: widget.subtitle,
        plot: ChartEmptyState(message: widget.emptyStateMessage),
      );
    }
    final done = widget.tasks.where((t) => (t.progress ?? 0) >= 1).length;
    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Gantt chart', widget.title, [
        '${widget.tasks.length} tasks, $done complete',
        'from ${_date(widget.tasks.map((t) => t.start).reduce((a, b) => a.isBefore(b) ? a : b))}'
            ' to ${_date(widget.tasks.map((t) => t.end).reduce((a, b) => a.isAfter(b) ? a : b))}',
      ]),
      title: widget.title,
      subtitle: widget.subtitle,
      plot: LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest;
        int? rowAt(Offset p) {
          final l = _layout(size, theme);
          if (p.dy < l.chart.top || p.dy >= l.chart.bottom) return null;
          final r = ((p.dy - l.chart.top) / l.rowHeight).floor();
          return r < l.rows.length && l.rows[r].task != null ? r : null;
        }

        void hover(Offset p) {
          final r = rowAt(p);
          _hover.value = r == null ? null : (r, p);
        }

        return Listener(
          onPointerSignal: (e) {
            if (e is! PointerScrollEvent) return;
            final l = _layout(size, theme);
            if (!l.chart.contains(e.localPosition)) return;
            if (e.scrollDelta.dx.abs() > e.scrollDelta.dy.abs()) {
              final per = (l.hi - l.lo) / l.chart.width;
              _setView(l.lo + e.scrollDelta.dx * per, l.hi + e.scrollDelta.dx * per);
            } else {
              final anchor = l.timeAt(e.localPosition.dx);
              final f = math.exp(e.scrollDelta.dy * 0.002);
              _setView(anchor - (anchor - l.lo) * f, anchor + (l.hi - anchor) * f);
            }
          },
          child: MouseRegion(
            onHover: (e) => hover(e.localPosition),
            onExit: (_) => _hover.value = null,
            child: GestureDetector(
              onTapUp: (d) {
                hover(d.localPosition);
                final h = _hover.value;
                if (h != null) widget.onTaskTap?.call(_layout(size, theme).rows[h.$1].task!);
              },
              onScaleStart: (d) {
                final l = _layout(size, theme);
                _gestureView = (l.lo, l.hi);
                _gestureFocalX = d.localFocalPoint.dx;
                _gestureChart = l.chart;
              },
              onScaleUpdate: (d) {
                final v = _gestureView;
                if (v == null) return;
                _hover.value = null;
                final span0 = v.$2 - v.$1, span = span0 / (d.horizontalScale > 0 ? d.horizontalScale : 1);
                final anchor = v.$1 + (_gestureFocalX - _gestureChart.left) / _gestureChart.width * span0;
                final lo = anchor - (d.localFocalPoint.dx - _gestureChart.left) / _gestureChart.width * span;
                _setView(lo, lo + span);
              },
              onScaleEnd: (_) => _gestureView = null,
              child: AnimatedBuilder(
                animation: Listenable.merge([_hover, _view]),
                builder: (context, _) {
                  final l = _layout(size, theme);
                  final h = _hover.value;
                  final task = h == null ? null : l.rows[h.$1].task;
                  return Stack(children: [
                    CustomPaint(
                      size: size,
                      painter: _GanttPainter(
                        layout: l,
                        state: this,
                        theme: theme,
                        hoverRow: h?.$1,
                      ),
                    ),
                    if (_view.value != null)
                      Positioned(right: 8, top: 28, child: ChartResetZoomButton(theme: theme, onTap: resetZoom)),
                    if (task != null)
                      positionChartTooltip(
                        anchor: Offset(l.barOf(h!.$1).right.clamp(l.chart.left, l.chart.right), l.barOf(h.$1).center.dy),
                        areaSize: size,
                        cardWidth: 180,
                        child: widget.tooltipBuilder?.call(context, task) ??
                            ChartTooltipCard(
                              theme: theme,
                              width: 180,
                              title: task.label,
                              subtitle: task.isMilestone
                                  ? 'Milestone · ${_date(task.start)}'
                                  : '${_date(task.start)} → ${_date(task.end)}\n'
                                      '${task.end.difference(task.start).inDays} days',
                              value: task.progress == null ? null : '${(task.progress! * 100).round()}% done',
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
}

class _GanttPainter extends CustomPainter {
  final _GanttLayout layout;
  final _GanttChart2DState state;
  final ChartTheme theme;
  final int? hoverRow;

  _GanttPainter({required this.layout, required this.state, required this.theme, required this.hoverRow});

  @override
  void paint(Canvas canvas, Size size) {
    final l = layout;
    final w = state.widget;
    final grid = Paint()
      ..color = theme.gridColor
      ..strokeWidth = 1;

    // Row stripes, and the hovered row's highlight.
    for (int r = 0; r < l.rows.length; r++) {
      final rect = l.rowRect(r);
      if (l.rows[r].task == null) {
        canvas.drawRect(rect, Paint()..color = theme.gridColor.withValues(alpha: theme.gridColor.a * 0.6));
      } else if (r == hoverRow) {
        canvas.drawRect(rect, Paint()..color = theme.crosshairColor.withValues(alpha: 0.12));
      }
    }

    // Date header + vertical grid (clipped to the timeline area).
    final ticks = timeTicks(l.lo, l.hi, maxTicks: math.max(2, (l.chart.width / 90).floor()));
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(l.chart.left, 0, l.chart.right, size.height));
    double lastRight = -double.infinity;
    for (final (ms, label) in ticks) {
      final x = l.chart.left + (ms - l.lo) / (l.hi - l.lo) * l.chart.width;
      canvas.drawLine(Offset(x, l.chart.top), Offset(x, l.chart.bottom), grid);
      final tp = layoutChartText(label, color: theme.tickTextColor, fontSize: theme.tickFontSize, fontFamily: theme.fontFamily);
      if (x + 4 > lastRight) {
        tp.paint(canvas, Offset(x + 4, (l.chart.top - tp.height) / 2));
        lastRight = x + 4 + tp.width + 8;
      }
    }

    // Today marker.
    if (w.showToday) {
      final x = l.x(w.today ?? DateTime.now());
      if (x >= l.chart.left && x <= l.chart.right) {
        canvas.drawLine(Offset(x, l.chart.top - 4), Offset(x, l.chart.bottom), Paint()
          ..color = const Color(0xFFEF5350)
          ..strokeWidth = 1.5);
      }
    }

    // Dependency arrows: from the end of the prerequisite to the start of
    // the dependent task, routed with an elbow.
    if (w.showDependencies) {
      final rowOf = {for (int r = 0; r < l.rows.length; r++) if (l.rows[r].task != null) l.rows[r].task!.key: r};
      final arrow = Paint()
        ..color = theme.tickTextColor
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      for (int r = 0; r < l.rows.length; r++) {
        final t = l.rows[r].task;
        if (t == null) continue;
        for (final dep in t.dependsOn) {
          final from = rowOf[dep];
          if (from == null) continue;
          final a = l.barOf(from), b = l.barOf(r);
          final start = Offset(a.right, a.center.dy), end = Offset(b.left, b.center.dy);
          final elbow = math.max(start.dx + 8, end.dx - 8);
          final path = Path()
            ..moveTo(start.dx, start.dy)
            ..lineTo(elbow, start.dy)
            ..lineTo(elbow, end.dy)
            ..lineTo(end.dx, end.dy);
          canvas.drawPath(path, arrow);
          canvas.drawPath(
            Path()
              ..moveTo(end.dx, end.dy)
              ..lineTo(end.dx - 5, end.dy - 3.5)
              ..lineTo(end.dx - 5, end.dy + 3.5)
              ..close(),
            Paint()..color = theme.tickTextColor,
          );
        }
      }
    }

    // Bars and milestones.
    for (int r = 0; r < l.rows.length; r++) {
      final t = l.rows[r].task;
      if (t == null) continue;
      final color = state._color(t);
      final bar = l.barOf(r);
      if (t.isMilestone) {
        final c = Offset(bar.left, bar.center.dy), s = bar.height * 0.6;
        canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy - s)
            ..lineTo(c.dx + s, c.dy)
            ..lineTo(c.dx, c.dy + s)
            ..lineTo(c.dx - s, c.dy)
            ..close(),
          Paint()..color = color,
        );
        continue;
      }
      final rr = RRect.fromRectAndRadius(bar, Radius.circular(math.min(4, bar.height / 3)));
      canvas.drawRRect(rr, Paint()..color = color.withValues(alpha: 0.45));
      final p = (t.progress ?? 0).clamp(0.0, 1.0);
      if (p > 0) {
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(bar.left, bar.top, bar.left + bar.width * p, bar.bottom));
        canvas.drawRRect(rr, Paint()..color = color);
        canvas.restore();
      }
      if (r == hoverRow) {
        canvas.drawRRect(rr, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = theme.axisColor);
      }
    }
    canvas.restore();

    // Name column (drawn last so it covers bars scrolled under it).
    canvas.drawRect(Rect.fromLTRB(0, 0, l.chart.left, size.height),
        Paint()..color = theme.backgroundColor.a == 0 ? Colors.transparent : theme.backgroundColor);
    canvas.drawLine(Offset(l.chart.left, 0), Offset(l.chart.left, l.chart.bottom), Paint()
      ..color = theme.axisColor
      ..strokeWidth = 1);
    for (int r = 0; r < l.rows.length; r++) {
      final row = l.rows[r];
      final isGroup = row.task == null;
      final tp = layoutChartText(
        isGroup ? row.group! : row.task!.label,
        color: isGroup ? theme.titleColor : theme.axisColor,
        fontSize: math.min(isGroup ? 12 : 11, l.rowHeight * 0.6),
        fontWeight: isGroup ? FontWeight.bold : FontWeight.w500,
        fontFamily: theme.fontFamily,
        maxWidth: math.max(1, l.chart.left - (isGroup ? 8 : 18)),
      );
      tp.paint(canvas, Offset(isGroup ? 4 : 14, l.chart.top + r * l.rowHeight + (l.rowHeight - tp.height) / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _GanttPainter old) => true;
}
