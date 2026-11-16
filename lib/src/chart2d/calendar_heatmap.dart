import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'cartesian_axes.dart';
import 'theme.dart';
import 'common.dart';
import 'controller.dart';
import 'hover_plot.dart';

const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// A day in a [CalendarHeatmap], with its value (null when there's none).
class CalendarDay {
  final DateTime date;
  final double? value;

  const CalendarDay(this.date, this.value);

  @override
  bool operator ==(Object other) => other is CalendarDay && other.date == date;

  @override
  int get hashCode => date.hashCode;
}

/// A calendar heatmap: one square per day, in week columns — like a GitHub
/// contribution graph. Good for activity, habits, daily P&L, sales.
///
/// ```dart
/// CalendarHeatmap(
///   values: {DateTime(2026, 3, 2): 4, DateTime(2026, 3, 3): 9},
///   start: DateTime(2026, 1, 1),
///   end: DateTime(2026, 12, 31),
/// )
/// ```
///
/// Days are matched by calendar date (time of day is ignored). Colors are
/// bucketed into [levels] steps, or continuous when [levels] is null.
class CalendarHeatmap extends StatefulWidget {
  final Map<DateTime, double> values;

  /// First and last day shown. Default to the earliest/latest dates in
  /// [values], or the last year when empty.
  final DateTime? start;
  final DateTime? end;

  /// Colors from low to high value.
  final List<Color> gradient;

  /// Color for days without a value (and zero, unless [zeroIsEmpty] is false).
  final Color? emptyColor;
  final bool zeroIsEmpty;

  /// Number of color steps (GitHub uses 4), or null for a continuous scale.
  final int? levels;

  /// Monday as the first row (ISO); otherwise Sunday.
  final bool weekStartsOnMonday;
  final double cellGap;
  final double cellRadius;
  final bool showMonthLabels;
  final bool showWeekdayLabels;

  /// A "Less ▢▢▢▢ More" key under the grid.
  final bool showLegend;
  final String? title;
  final String? subtitle;
  final String Function(double value) valueFormatter;

  /// Text for a day in the tooltip; defaults to "3 Mar 2026".
  final String Function(DateTime date)? dateFormatter;
  final Widget Function(BuildContext context, CalendarDay day)? tooltipBuilder;
  final ChartController? controller;
  final ValueChanged<CalendarDay>? onDayTap;

  const CalendarHeatmap({
    super.key,
    required this.values,
    this.start,
    this.end,
    this.gradient = const [Color(0xFF9BE9A8), Color(0xFF40C463), Color(0xFF30A14E), Color(0xFF216E39)],
    this.emptyColor,
    this.zeroIsEmpty = true,
    this.levels = 4,
    this.weekStartsOnMonday = false,
    this.cellGap = 3,
    this.cellRadius = 2,
    this.showMonthLabels = true,
    this.showWeekdayLabels = true,
    this.showLegend = true,
    this.title,
    this.subtitle,
    this.valueFormatter = Cartesian2DAxes.formatNumber,
    this.dateFormatter,
    this.tooltipBuilder,
    this.controller,
    this.onDayTap,
  });

  @override
  State<CalendarHeatmap> createState() => _CalendarHeatmapState();
}

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

class _CalendarLayout {
  final DateTime first; // first day of the first week column
  final DateTime start;
  final DateTime end;
  final int weeks;
  final double cell;
  final Offset origin;
  final bool mondayFirst;

  _CalendarLayout(this.first, this.start, this.end, this.weeks, this.cell, this.origin, this.mondayFirst);

  int row(DateTime d) => mondayFirst ? d.weekday - 1 : d.weekday % 7;

  /// Calendar days between two dates (DST-safe).
  static int daysBetween(DateTime a, DateTime b) =>
      DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

  Rect rectOf(DateTime d) {
    final col = daysBetween(first, d) ~/ 7;
    return Rect.fromLTWH(origin.dx + col * cell, origin.dy + row(d) * cell, cell, cell);
  }

  DateTime? dayAt(Offset p) {
    final col = ((p.dx - origin.dx) / cell).floor(), r = ((p.dy - origin.dy) / cell).floor();
    if (col < 0 || col >= weeks || r < 0 || r > 6) return null;
    final d = DateTime(first.year, first.month, first.day + col * 7 + r);
    return d.isBefore(start) || d.isAfter(end) ? null : d;
  }
}

class _CalendarHeatmapState extends State<CalendarHeatmap> with ChartControllerMixin<CalendarHeatmap> {
  late Map<DateTime, double> _byDay;

  @override
  ChartController? controllerOf(CalendarHeatmap widget) => widget.controller;

  @override
  void resetZoom() {} // no zoom on this chart

  @override
  void initState() {
    super.initState();
    _index();
  }

  @override
  void didUpdateWidget(covariant CalendarHeatmap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.values, widget.values)) _index();
  }

  void _index() {
    _byDay = {};
    widget.values.forEach((k, v) => _byDay[_day(k)] = (_byDay[_day(k)] ?? 0) + v);
  }

  (DateTime, DateTime) get _range {
    final keys = _byDay.keys;
    final today = _day(DateTime.now());
    final end = _day(widget.end ?? (keys.isEmpty ? today : keys.reduce((a, b) => a.isAfter(b) ? a : b)));
    final start = _day(widget.start ?? (keys.isEmpty ? DateTime(end.year - 1, end.month, end.day + 1) : keys.reduce((a, b) => a.isBefore(b) ? a : b)));
    return start.isAfter(end) ? (end, start) : (start, end);
  }

  _CalendarLayout _layout(Size size, ChartTheme theme) {
    final (start, end) = _range;
    final mondayFirst = widget.weekStartsOnMonday;
    final back = mondayFirst ? start.weekday - 1 : start.weekday % 7;
    final first = DateTime(start.year, start.month, start.day - back);
    final weeks = _CalendarLayout.daysBetween(first, end) ~/ 7 + 1;
    final left = widget.showWeekdayLabels
        ? layoutChartText('Wed', color: theme.tickTextColor, fontSize: theme.tickFontSize, fontFamily: theme.fontFamily).width + 6
        : 0.0;
    final top = widget.showMonthLabels ? theme.tickFontSize + 8 : 0.0;
    final bottom = widget.showLegend ? 22.0 : 0.0;
    final cell = math.max(2.0, math.min((size.width - left) / weeks, (size.height - top - bottom) / 7));
    return _CalendarLayout(first, start, end, weeks, cell, Offset(left, top), mondayFirst);
  }

  (double, double) get _valueRange {
    final vs = _byDay.values.where((v) => !(widget.zeroIsEmpty && v == 0));
    if (vs.isEmpty) return (0, 1);
    return (vs.reduce(math.min), vs.reduce(math.max));
  }

  Color _colorFor(double? v, ChartTheme theme) {
    final empty = widget.emptyColor ?? theme.gridColor;
    if (v == null || (widget.zeroIsEmpty && v == 0)) return empty;
    final (lo, hi) = _valueRange;
    var t = hi == lo ? 1.0 : ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
    final levels = widget.levels;
    if (levels != null && levels > 0) t = ((t * levels).ceil().clamp(1, levels) - 1) / math.max(1, levels - 1);
    return sampleGradient(widget.gradient, t);
  }

  String _formatDate(DateTime d) => widget.dateFormatter?.call(d) ?? '${d.day} ${_monthNames[d.month - 1]} ${d.year}';

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    final (start, end) = _range;
    final active = _byDay.entries.where((e) => !e.key.isBefore(start) && !e.key.isAfter(end) && e.value != 0).toList();
    final total = active.fold(0.0, (s, e) => s + e.value);
    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Calendar heatmap', widget.title, [
        '${_formatDate(start)} to ${_formatDate(end)}',
        '${active.length} days with values, total ${widget.valueFormatter(total)}',
      ]),
      title: widget.title,
      subtitle: widget.subtitle,
      plot: HoverPlot<CalendarDay>(
        enableAnimation: false,
        hitTest: (pos, size) {
          final d = _layout(size, theme).dayAt(pos);
          return d == null ? null : CalendarDay(d, _byDay[d]);
        },
        onTap: widget.onDayTap,
        painterBuilder: (size, hover, _) => _CalendarPainter(
          layout: _layout(size, theme),
          state: this,
          theme: theme,
          hover: hover?.date,
        ),
        tooltipBuilder: (context, day, pointer, size) {
          final rect = _layout(size, theme).rectOf(day.date);
          final custom = widget.tooltipBuilder;
          return positionChartTooltip(
            anchor: Offset(rect.right, rect.top),
            areaSize: size,
            cardWidth: 140,
            child: custom != null
                ? custom(context, day)
                : ChartTooltipCard(
                    theme: theme,
                    width: 140,
                    title: _formatDate(day.date),
                    value: day.value == null ? 'No data' : widget.valueFormatter(day.value!),
                  ),
          );
        },
      ),
    );
  }
}

class _CalendarPainter extends CustomPainter {
  final _CalendarLayout layout;
  final _CalendarHeatmapState state;
  final ChartTheme theme;
  final DateTime? hover;

  _CalendarPainter({required this.layout, required this.state, required this.theme, required this.hover});

  @override
  void paint(Canvas canvas, Size size) {
    final w = state.widget;
    final l = layout;
    final gap = math.min(w.cellGap, l.cell * 0.25);
    final radius = Radius.circular(math.min(w.cellRadius, l.cell / 3));

    for (var d = l.start; !d.isAfter(l.end); d = DateTime(d.year, d.month, d.day + 1)) {
      final r = l.rectOf(d).deflate(gap / 2);
      canvas.drawRRect(RRect.fromRectAndRadius(r, radius), Paint()..color = state._colorFor(state._byDay[d], theme));
      if (d == hover) {
        canvas.drawRRect(RRect.fromRectAndRadius(r.inflate(1), radius),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = theme.axisColor);
      }
    }

    final label = TextStyle(color: theme.tickTextColor, fontSize: theme.tickFontSize, fontFamily: theme.fontFamily);
    if (w.showMonthLabels) {
      // At the first week column containing each month's 1st (skipping
      // labels that would crowd the previous one).
      double lastRight = -double.infinity;
      for (var m = DateTime(l.start.year, l.start.month, 1); !m.isAfter(l.end); m = DateTime(m.year, m.month + 1, 1)) {
        final day = m.isBefore(l.start) ? l.start : m;
        final x = l.rectOf(day).left;
        final tp = layoutChartText(_monthNames[m.month - 1], color: label.color!, fontSize: label.fontSize!, fontFamily: label.fontFamily);
        if (x < lastRight + 4 || x + tp.width > size.width) continue;
        tp.paint(canvas, Offset(x, 0));
        lastRight = x + tp.width;
      }
    }
    if (w.showWeekdayLabels && l.cell >= 8) {
      final names = w.weekStartsOnMonday ? ['Mon', '', 'Wed', '', 'Fri', '', ''] : ['', 'Mon', '', 'Wed', '', 'Fri', ''];
      for (int r = 0; r < 7; r++) {
        if (names[r].isEmpty) continue;
        final tp = layoutChartText(names[r], color: label.color!, fontSize: label.fontSize!, fontFamily: label.fontFamily);
        tp.paint(canvas, Offset(0, l.origin.dy + r * l.cell + (l.cell - tp.height) / 2));
      }
    }

    if (w.showLegend) {
      final steps = w.levels ?? 5;
      final box = math.min(12.0, l.cell);
      final y = l.origin.dy + 7 * l.cell + 6;
      final more = layoutChartText('More', color: label.color!, fontSize: label.fontSize!, fontFamily: label.fontFamily);
      final less = layoutChartText('Less', color: label.color!, fontSize: label.fontSize!, fontFamily: label.fontFamily);
      final right = math.min(size.width, l.origin.dx + l.weeks * l.cell);
      var x = right - more.width;
      more.paint(canvas, Offset(x, y + (box - more.height) / 2));
      x -= 4;
      for (int i = steps - 1; i >= -1; i--) {
        x -= box + 2;
        final color = i < 0 ? (w.emptyColor ?? theme.gridColor) : sampleGradient(w.gradient, steps == 1 ? 1 : i / (steps - 1));
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, box, box), radius), Paint()..color = color);
      }
      less.paint(canvas, Offset(x - 4 - less.width, y + (box - less.height) / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _CalendarPainter old) => true;
}
