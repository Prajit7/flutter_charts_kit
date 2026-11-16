import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'theme.dart';
import 'cartesian_axes.dart';
import 'chart_chrome.dart';
import 'common.dart';
import 'controller.dart';
import 'legend.dart';
import 'models.dart';

/// One vertical axis of a [ParallelCoordinatesChart2D].
class ParallelAxis {
  final String label;

  /// Range of the axis; defaults to a nice range around the data.
  final double? min;
  final double? max;

  /// Put the minimum at the top (for "lower is better" measures).
  final bool inverted;
  final String Function(double value)? formatter;

  const ParallelAxis(this.label, {this.min, this.max, this.inverted = false, this.formatter});
}

/// One line of a [ParallelCoordinatesChart2D]: a value per axis.
class ParallelRecord {
  final List<double> values;
  final String? label;

  /// Records in the same group share a palette color (and a legend chip).
  final String? group;
  final Color? color;

  const ParallelRecord(this.values, {this.label, this.group, this.color});
}

/// Parallel coordinates: each record is a line crossing one vertical axis
/// per measure — compare many items across many dimensions (cars by price,
/// mileage, power; candidates by score; servers by CPU, memory, latency).
///
/// Drag along an axis to **brush** a range: only records passing every
/// brush stay highlighted. Tap an axis to clear its brush.
///
/// ```dart
/// ParallelCoordinatesChart2D(
///   axes: [ParallelAxis('Price'), ParallelAxis('MPG'), ParallelAxis('HP')],
///   records: [ParallelRecord([24000, 32, 150], label: 'Civic', group: 'Honda'), ...],
/// )
/// ```
class ParallelCoordinatesChart2D extends StatefulWidget {
  final List<ParallelAxis> axes;
  final List<ParallelRecord> records;
  final List<Color> palette;
  final String? title;
  final String? subtitle;
  final String emptyStateMessage;
  final bool showLegend;
  final ChartLegendPosition legendPosition;

  /// Curved (true) or straight segments between axes.
  final bool smooth;
  final double strokeWidth;
  final Widget Function(BuildContext context, ParallelRecord record)? tooltipBuilder;
  final ChartController? controller;
  final ValueChanged<ParallelRecord>? onRecordTap;

  /// Fired with the records passing every brush (all records when none).
  final ValueChanged<List<ParallelRecord>>? onSelectionChanged;

  const ParallelCoordinatesChart2D({
    super.key,
    required this.axes,
    required this.records,
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
    this.emptyStateMessage = 'No data',
    this.showLegend = true,
    this.legendPosition = ChartLegendPosition.bottom,
    this.smooth = false,
    this.strokeWidth = 1.4,
    this.tooltipBuilder,
    this.controller,
    this.onRecordTap,
    this.onSelectionChanged,
  });

  @override
  State<ParallelCoordinatesChart2D> createState() => _ParallelCoordinatesState();
}

class _ParallelCoordinatesState extends State<ParallelCoordinatesChart2D>
    with ChartControllerMixin<ParallelCoordinatesChart2D> {
  /// Brushes by axis index: a data-value range (lo, hi).
  final Map<int, (double, double)> _brushes = {};
  final Set<String> _hiddenGroups = {};
  final ValueNotifier<(int, Offset)?> _hover = ValueNotifier(null);
  int? _brushAxis;
  double? _brushStart;
  late List<(double, double)> _ranges;

  @override
  ChartController? controllerOf(ParallelCoordinatesChart2D widget) => widget.controller;

  /// "Reset" clears every brush.
  @override
  void resetZoom() {
    setState(_brushes.clear);
    reportZoomed(false);
    _notifySelection();
  }

  @override
  void initState() {
    super.initState();
    _ranges = _computeRanges();
  }

  @override
  void didUpdateWidget(covariant ParallelCoordinatesChart2D old) {
    super.didUpdateWidget(old);
    if (!identical(old.records, widget.records) || !identical(old.axes, widget.axes)) {
      _ranges = _computeRanges();
      _brushes.removeWhere((k, _) => k >= widget.axes.length);
    }
  }

  @override
  void dispose() {
    _hover.dispose();
    super.dispose();
  }

  List<(double, double)> _computeRanges() => [
        for (int a = 0; a < widget.axes.length; a++)
          () {
            final axis = widget.axes[a];
            final vs = [
              for (final r in widget.records)
                if (a < r.values.length && r.values[a].isFinite) r.values[a],
            ];
            if (vs.isEmpty) return (axis.min ?? 0.0, axis.max ?? 1.0);
            var lo = vs.reduce(math.min), hi = vs.reduce(math.max);
            if (lo == hi) {
              lo -= 1;
              hi += 1;
            }
            final (nlo, nhi) = Cartesian2DAxes.niceExtent(lo, hi, count: 5);
            return (axis.min ?? nlo, axis.max ?? nhi);
          }(),
      ];

  List<String?> get _groups {
    final g = <String?>[];
    for (final r in widget.records) {
      if (!g.contains(r.group)) g.add(r.group);
    }
    return g;
  }

  Color _color(ParallelRecord r) => r.color ?? widget.palette[_groups.indexOf(r.group) % widget.palette.length];

  bool _visible(ParallelRecord r) => r.group == null || !_hiddenGroups.contains(r.group);

  bool _selected(ParallelRecord r) {
    for (final MapEntry(key: a, value: (lo, hi)) in _brushes.entries) {
      if (a >= r.values.length) return false;
      final v = r.values[a];
      if (!(v >= lo && v <= hi)) return false;
    }
    return true;
  }

  void _notifySelection() =>
      widget.onSelectionChanged?.call([for (final r in widget.records) if (_visible(r) && _selected(r)) r]);

  Rect _plot(Size size) {
    const top = 22.0, bottom = 22.0;
    final first = layoutChartText(widget.axes.first.label, color: const Color(0xFF000000), fontSize: 11);
    final last = layoutChartText(widget.axes.last.label, color: const Color(0xFF000000), fontSize: 11);
    final left = math.max(36.0, first.width / 2 + 4), right = math.max(16.0, last.width / 2 + 4);
    return Rect.fromLTRB(left, top, math.max(left + 1, size.width - right), math.max(top + 1, size.height - bottom));
  }

  double _axisX(Rect plot, int a) =>
      widget.axes.length == 1 ? plot.center.dx : plot.left + plot.width * a / (widget.axes.length - 1);

  double _fraction(int a, double v) {
    final (lo, hi) = _ranges[a];
    final f = hi == lo ? 0.5 : (v - lo) / (hi - lo);
    return widget.axes[a].inverted ? 1 - f : f;
  }

  double _y(Rect plot, int a, double v) => plot.bottom - _fraction(a, v) * plot.height;

  double _valueAt(Rect plot, int a, double y) {
    final (lo, hi) = _ranges[a];
    var f = ((plot.bottom - y) / plot.height).clamp(0.0, 1.0);
    if (widget.axes[a].inverted) f = 1 - f;
    return lo + f * (hi - lo);
  }

  List<Offset> _points(Rect plot, ParallelRecord r) => [
        for (int a = 0; a < widget.axes.length && a < r.values.length; a++)
          if (r.values[a].isFinite) Offset(_axisX(plot, a), _y(plot, a, r.values[a].clamp(_ranges[a].$1, _ranges[a].$2).toDouble())),
      ];

  int? _axisNear(Rect plot, Offset p) {
    for (int a = 0; a < widget.axes.length; a++) {
      if ((p.dx - _axisX(plot, a)).abs() <= 14 && p.dy >= plot.top - 6 && p.dy <= plot.bottom + 6) return a;
    }
    return null;
  }

  /// Nearest visible record line within 8px.
  int? _recordAt(Rect plot, Offset p) {
    int? best;
    var bestD = 8.0;
    for (int i = 0; i < widget.records.length; i++) {
      final r = widget.records[i];
      if (!_visible(r) || !_selected(r)) continue;
      final pts = _points(plot, r);
      for (int k = 0; k + 1 < pts.length; k++) {
        final d = _segmentDistance(p, pts[k], pts[k + 1]);
        if (d < bestD) {
          bestD = d;
          best = i;
        }
      }
    }
    return best;
  }

  static double _segmentDistance(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.distanceSquared;
    final t = len2 == 0 ? 0.0 : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  String _fmt(int a, double v) => widget.axes[a].formatter?.call(v) ?? Cartesian2DAxes.formatNumber(v);

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    if (widget.axes.length < 2 || widget.records.isEmpty) {
      return ChartFrame(
        boundaryKey: chartBoundaryKey,
        title: widget.title,
        subtitle: widget.subtitle,
        plot: ChartEmptyState(message: widget.axes.length < 2 ? 'Needs at least two axes' : widget.emptyStateMessage),
      );
    }
    final groups = _groups.whereType<String>().toList();
    final selectedCount = widget.records.where((r) => _visible(r) && _selected(r)).length;
    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Parallel coordinates chart', widget.title, [
        '${widget.records.length} records across ${widget.axes.map((a) => a.label).join(', ')}',
        if (_brushes.isNotEmpty) '$selectedCount match the filters',
      ]),
      title: widget.title,
      subtitle: widget.subtitle,
      legendPosition: widget.legendPosition,
      legendBuilder: widget.showLegend && groups.isNotEmpty
          ? (direction) => Chart2DLegend(
                direction: direction,
                entries: [
                  for (final g in groups)
                    LegendEntry(label: g, color: _color(widget.records.firstWhere((r) => r.group == g))),
                ],
                hidden: _hiddenGroups,
                onToggle: (g) => setState(() {
                  _hiddenGroups.contains(g) ? _hiddenGroups.remove(g) : _hiddenGroups.add(g);
                  _notifySelection();
                }),
              )
          : null,
      plot: LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest;
        final plot = _plot(size);
        return MouseRegion(
          onHover: (e) {
            final i = _brushAxis == null ? _recordAt(plot, e.localPosition) : null;
            _hover.value = i == null ? null : (i, e.localPosition);
          },
          onExit: (_) => _hover.value = null,
          child: GestureDetector(
            // Brushes start where the finger went down, not after the slop.
            dragStartBehavior: DragStartBehavior.down,
            onTapUp: (d) {
              final a = _axisNear(plot, d.localPosition);
              if (a != null && _brushes.containsKey(a)) {
                setState(() => _brushes.remove(a));
                reportZoomed(_brushes.isNotEmpty);
                _notifySelection();
                return;
              }
              final i = _recordAt(plot, d.localPosition);
              _hover.value = i == null ? null : (i, d.localPosition);
              if (i != null) widget.onRecordTap?.call(widget.records[i]);
            },
            onVerticalDragStart: (d) {
              _brushAxis = _axisNear(plot, d.localPosition);
              _brushStart = d.localPosition.dy.clamp(plot.top, plot.bottom);
              _hover.value = null;
            },
            onVerticalDragUpdate: (d) {
              final a = _brushAxis, start = _brushStart;
              if (a == null || start == null) return;
              final y = d.localPosition.dy.clamp(plot.top, plot.bottom);
              final v0 = _valueAt(plot, a, start), v1 = _valueAt(plot, a, y);
              setState(() => _brushes[a] = (math.min(v0, v1), math.max(v0, v1)));
            },
            onVerticalDragEnd: (_) {
              final a = _brushAxis;
              _brushAxis = null;
              if (a == null) return;
              // A click-sized brush means "clear".
              final b = _brushes[a];
              if (b != null && (_y(plot, a, b.$1) - _y(plot, a, b.$2)).abs() < 3) setState(() => _brushes.remove(a));
              reportZoomed(_brushes.isNotEmpty);
              _notifySelection();
            },
            child: ValueListenableBuilder<(int, Offset)?>(
              valueListenable: _hover,
              builder: (context, hover, _) => Stack(children: [
                CustomPaint(
                  size: size,
                  painter: _ParallelPainter(state: this, plot: plot, theme: theme, hovered: hover?.$1),
                ),
                if (hover != null)
                  positionChartTooltip(
                    anchor: hover.$2,
                    areaSize: size,
                    cardWidth: 190,
                    child: widget.tooltipBuilder?.call(context, widget.records[hover.$1]) ??
                        ChartTooltipCard(
                          theme: theme,
                          width: 190,
                          title: widget.records[hover.$1].label ?? 'Record ${hover.$1 + 1}',
                          subtitle: [
                            for (int a = 0; a < widget.axes.length && a < widget.records[hover.$1].values.length; a++)
                              '${widget.axes[a].label}: ${_fmt(a, widget.records[hover.$1].values[a])}',
                          ].join('\n'),
                          value: widget.records[hover.$1].group ?? '',
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

class _ParallelPainter extends CustomPainter {
  final _ParallelCoordinatesState state;
  final Rect plot;
  final ChartTheme theme;
  final int? hovered;

  _ParallelPainter({required this.state, required this.plot, required this.theme, required this.hovered});

  Path _line(List<Offset> pts, bool smooth) {
    final p = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int k = 1; k < pts.length; k++) {
      if (smooth) {
        final mx = (pts[k - 1].dx + pts[k].dx) / 2;
        p.cubicTo(mx, pts[k - 1].dy, mx, pts[k].dy, pts[k].dx, pts[k].dy);
      } else {
        p.lineTo(pts[k].dx, pts[k].dy);
      }
    }
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = state;
    final w = s.widget;
    final filtering = s._brushes.isNotEmpty || hovered != null;

    // Unselected first (faint), then selected, then the hovered one on top.
    final background = <ParallelRecord>[], foreground = <ParallelRecord>[];
    for (final r in w.records) {
      if (!s._visible(r)) continue;
      (s._selected(r) ? foreground : background).add(r);
    }
    for (final r in background) {
      final pts = s._points(plot, r);
      if (pts.length < 2) continue;
      canvas.drawPath(_line(pts, w.smooth), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = theme.gridColor.withValues(alpha: theme.gridColor.a * 0.8));
    }
    for (final r in foreground) {
      final pts = s._points(plot, r);
      if (pts.length < 2) continue;
      final c = s._color(r);
      final alpha = hovered == null ? (filtering ? 0.9 : 0.78) : 0.25;
      canvas.drawPath(_line(pts, w.smooth), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w.strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..color = c.withValues(alpha: c.a * alpha));
    }
    if (hovered != null) {
      final r = w.records[hovered!];
      final pts = s._points(plot, r);
      if (pts.length >= 2) {
        canvas.drawPath(_line(pts, w.smooth), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w.strokeWidth + 1.6
          ..strokeJoin = StrokeJoin.round
          ..color = s._color(r));
        for (final p in pts) {
          canvas.drawCircle(p, 3.5, Paint()..color = s._color(r));
        }
      }
    }

    // Axes, ticks, labels, brushes.
    final axisPaint = Paint()
      ..color = theme.axisColor
      ..strokeWidth = 1;
    for (int a = 0; a < w.axes.length; a++) {
      final x = s._axisX(plot, a);
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), axisPaint);
      final (lo, hi) = s._ranges[a];
      for (final t in Cartesian2DAxes.niceTicks(lo, hi, count: 5)) {
        if (t < lo - 1e-9 || t > hi + 1e-9) continue;
        final y = s._y(plot, a, t);
        canvas.drawLine(Offset(x - 3, y), Offset(x, y), axisPaint);
        final tp = layoutChartText(s._fmt(a, t), color: theme.tickTextColor, fontSize: 9, fontFamily: theme.fontFamily);
        tp.paint(canvas, Offset(x - 5 - tp.width, y - tp.height / 2));
      }
      final label = layoutChartText(w.axes[a].label,
          color: theme.axisColor, fontSize: 11, fontWeight: FontWeight.w700, fontFamily: theme.fontFamily);
      label.paint(canvas, Offset(x - label.width / 2, plot.top - label.height - 6));

      final b = s._brushes[a];
      if (b != null) {
        final y0 = s._y(plot, a, b.$1), y1 = s._y(plot, a, b.$2);
        final r = RRect.fromRectAndRadius(Rect.fromLTRB(x - 7, math.min(y0, y1), x + 7, math.max(y0, y1)), const Radius.circular(3));
        canvas.drawRRect(r, Paint()..color = theme.crosshairColor.withValues(alpha: theme.crosshairColor.a * 0.25));
        canvas.drawRRect(r, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = theme.crosshairColor);
      }
    }
    if (s._brushes.isNotEmpty) {
      final n = w.records.where((r) => s._visible(r) && s._selected(r)).length;
      final tp = layoutChartText('$n of ${w.records.where(s._visible).length} match · tap an axis to clear',
          color: theme.tickTextColor, fontSize: 10, fontFamily: theme.fontFamily);
      tp.paint(canvas, Offset(plot.right - tp.width, plot.bottom + 6));
    }
  }

  @override
  bool shouldRepaint(covariant _ParallelPainter old) => true;
}
