import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'cartesian_axes.dart';
import 'legend.dart';
import 'models.dart';
import 'theme.dart';
import 'chart_chrome.dart';
import 'common.dart';
import 'controller.dart';
import 'hover_plot.dart';

/// How [PolarBarChart2D] lays out its bars.
enum PolarBarStyle {
  /// Nightingale rose: one wedge per category around the circle, extending
  /// outward by value; series stack outward.
  rose,

  /// Radial bars: one concentric ring per category (and series), each an
  /// arc whose length is the value.
  radial,
}

/// A hovered/tapped polar bar.
class PolarBarHit {
  final String series;
  final int categoryIndex;
  final String category;
  final double value;

  const PolarBarHit(this.series, this.categoryIndex, this.category, this.value);

  @override
  bool operator ==(Object other) => other is PolarBarHit && other.series == series && other.categoryIndex == categoryIndex;

  @override
  int get hashCode => Object.hash(series, categoryIndex);
}

/// Bars arranged in a circle — a rose (Nightingale) chart for categories
/// around a cycle (months, hours, compass directions), or radial bars for
/// a compact ranking/progress display.
///
/// ```dart
/// PolarBarChart2D(
///   categories: ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'],
///   series: [CategorySeries(name: 'Wind', color: Colors.teal, values: [12, 8, 5, 3, 6, 14, 18, 15])],
/// )
/// ```
class PolarBarChart2D extends StatefulWidget {
  final List<String> categories;
  final List<CategorySeries> series;
  final PolarBarStyle style;

  /// Rose only: wedge *area* (not radius) proportional to value, so large
  /// values aren't visually exaggerated. On by default.
  final bool areaProportional;

  /// Value at the outer edge (rose) or full arc (radial). Defaults to a nice
  /// number above the data.
  final double? max;

  /// Radial only: degrees a full-scale bar sweeps (270 leaves a gap for labels).
  final double radialSweep;
  final String? title;
  final String? subtitle;
  final String emptyStateMessage;
  final String Function(double value) valueFormatter;
  final bool showGrid;
  final bool showLegend;
  final ChartLegendPosition legendPosition;
  final bool enableAnimation;
  final Duration animationDuration;
  final Widget Function(BuildContext context, PolarBarHit hit)? tooltipBuilder;
  final ChartController? controller;
  final ValueChanged<PolarBarHit>? onBarTap;

  const PolarBarChart2D({
    super.key,
    required this.categories,
    required this.series,
    this.style = PolarBarStyle.rose,
    this.areaProportional = true,
    this.max,
    this.radialSweep = 270,
    this.title,
    this.subtitle,
    this.emptyStateMessage = 'No data to display',
    this.valueFormatter = Cartesian2DAxes.formatNumber,
    this.showGrid = true,
    this.showLegend = true,
    this.legendPosition = ChartLegendPosition.bottom,
    this.enableAnimation = true,
    this.animationDuration = const Duration(milliseconds: 600),
    this.tooltipBuilder,
    this.controller,
    this.onBarTap,
  });

  @override
  State<PolarBarChart2D> createState() => _PolarBarChart2DState();
}

/// One drawable bar: its hit info and its annular sector.
class _Sector {
  final PolarBarHit hit;
  final Color color;
  final double r1, r2, start, sweep;
  const _Sector(this.hit, this.color, this.r1, this.r2, this.start, this.sweep);

  Path path(Offset c, [double progress = 1]) {
    final s = sweep * (progress.clamp(0.0, 1.0));
    final outer = r1 + (r2 - r1) * progress;
    return Path()
      ..addArc(Rect.fromCircle(center: c, radius: outer), start, s)
      ..arcTo(Rect.fromCircle(center: c, radius: r1), start + s, -s, false)
      ..close();
  }
}

class _PolarBarChart2DState extends State<PolarBarChart2D> with ChartControllerMixin<PolarBarChart2D> {
  final ValueNotifier<Set<String>> _hidden = ValueNotifier(const {});

  @override
  ChartController? controllerOf(PolarBarChart2D widget) => widget.controller;

  @override
  void resetZoom() {} // no zoom on this chart

  @override
  void dispose() {
    _hidden.dispose();
    super.dispose();
  }

  double _v(CategorySeries s, int i) => i < s.values.length ? math.max(0, s.values[i]) : 0;

  double _max(List<CategorySeries> visible) {
    if (widget.max != null) return widget.max!;
    double m = 0;
    for (int i = 0; i < widget.categories.length; i++) {
      if (widget.style == PolarBarStyle.rose) {
        m = math.max(m, visible.fold(0.0, (a, s) => a + _v(s, i)));
      } else {
        for (final s in visible) {
          m = math.max(m, _v(s, i));
        }
      }
    }
    return m == 0 ? 1 : Cartesian2DAxes.niceExtent(0, m).$2;
  }

  (Offset, double) _geometry(Size size) =>
      (size.center(Offset.zero), math.max(0.0, math.min(size.width, size.height) / 2 - (widget.style == PolarBarStyle.rose ? 22 : 6)));

  List<_Sector> _sectors(Size size, List<CategorySeries> visible) {
    final (_, radius) = _geometry(size);
    final max = _max(visible);
    final n = widget.categories.length;
    final out = <_Sector>[];
    if (widget.style == PolarBarStyle.rose) {
      final slot = 2 * math.pi / n;
      double r(double v) => radius * (widget.areaProportional ? math.sqrt((v / max).clamp(0.0, 1.0)) : (v / max).clamp(0.0, 1.0));
      for (int i = 0; i < n; i++) {
        double acc = 0;
        for (final s in visible) {
          final v = _v(s, i);
          final r1 = r(acc), r2 = r(acc + v);
          acc += v;
          out.add(_Sector(PolarBarHit(s.name, i, widget.categories[i], v), s.color, r1, r2,
              -math.pi / 2 + i * slot + slot * 0.04, slot * 0.92));
        }
      }
    } else {
      // Rings from the outside in: category 0 is outermost.
      final rings = [for (int i = 0; i < n; i++) for (final s in visible) (i, s)];
      final inner = radius * 0.25;
      final thickness = (radius - inner) / math.max(1, rings.length);
      final full = widget.radialSweep * math.pi / 180;
      for (int k = 0; k < rings.length; k++) {
        final (i, s) = rings[k];
        final r2 = radius - k * thickness, r1 = r2 - thickness * 0.72;
        final v = _v(s, i);
        out.add(_Sector(PolarBarHit(s.name, i, widget.categories[i], v), s.color, r1, r2, -math.pi / 2, full * (v / max).clamp(0.0, 1.0)));
      }
    }
    return out;
  }

  PolarBarHit? _hit(Offset pos, Size size, List<CategorySeries> visible) {
    final (c, _) = _geometry(size);
    final d = (pos - c).distance;
    var a = math.atan2(pos.dy - c.dy, pos.dx - c.dx);
    if (a < -math.pi / 2) a += 2 * math.pi;
    for (final s in _sectors(size, visible)) {
      if (d >= s.r1 && d <= s.r2 && a >= s.start && a <= s.start + s.sweep) return s.hit;
      // Radial rings are easy to miss when short: the whole ring row counts.
      if (widget.style == PolarBarStyle.radial && d >= s.r1 && d <= s.r2) return s.hit;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    if (widget.categories.isEmpty || widget.series.isEmpty) {
      return ChartFrame(
        boundaryKey: chartBoundaryKey,
        title: widget.title,
        subtitle: widget.subtitle,
        plot: ChartEmptyState(message: widget.emptyStateMessage),
      );
    }
    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart(widget.style == PolarBarStyle.rose ? 'Rose chart' : 'Radial bar chart', widget.title, [
        '${widget.categories.length} categories',
        for (final s in widget.series) summarizeValues(s.name, s.values, widget.valueFormatter),
      ]),
      title: widget.title,
      subtitle: widget.subtitle,
      legendPosition: widget.legendPosition,
      legendBuilder: widget.showLegend && widget.series.length > 1
          ? (direction) => ValueListenableBuilder<Set<String>>(
                valueListenable: _hidden,
                builder: (context, hidden, _) => Chart2DLegend(
                  direction: direction,
                  entries: [for (final s in widget.series) LegendEntry(label: s.name, color: s.color)],
                  hidden: hidden,
                  onToggle: (name) {
                    final next = {...hidden};
                    next.contains(name) ? next.remove(name) : next.add(name);
                    _hidden.value = next;
                  },
                ),
              )
          : null,
      plot: ValueListenableBuilder<Set<String>>(
        valueListenable: _hidden,
        builder: (context, hidden, _) {
          final visible = widget.series.where((s) => !hidden.contains(s.name)).toList();
          return HoverPlot<PolarBarHit>(
            enableAnimation: widget.enableAnimation,
            animationDuration: widget.animationDuration,
            animationKey: Object.hashAll(widget.series),
            onTap: widget.onBarTap,
            hitTest: (pos, size) => _hit(pos, size, visible),
            painterBuilder: (size, hover, progress) {
              final (c, r) = _geometry(size);
              return _PolarPainter(
                sectors: _sectors(size, visible),
                center: c,
                radius: r,
                max: _max(visible),
                widget: widget,
                theme: theme,
                hover: hover,
                progress: Curves.easeOutCubic.transform(progress),
              );
            },
            tooltipBuilder: (context, hit, pointer, size) {
              final custom = widget.tooltipBuilder;
              return positionChartTooltip(
                anchor: pointer,
                areaSize: size,
                child: custom != null
                    ? custom(context, hit)
                    : ChartTooltipCard(
                        theme: theme,
                        width: 150,
                        title: widget.series.length > 1 ? hit.series : hit.category,
                        subtitle: widget.series.length > 1 ? hit.category : null,
                        value: widget.valueFormatter(hit.value),
                      ),
              );
            },
          );
        },
      ),
    );
  }
}

class _PolarPainter extends CustomPainter {
  final List<_Sector> sectors;
  final Offset center;
  final double radius;
  final double max;
  final PolarBarChart2D widget;
  final ChartTheme theme;
  final PolarBarHit? hover;
  final double progress;

  _PolarPainter({
    required this.sectors,
    required this.center,
    required this.radius,
    required this.max,
    required this.widget,
    required this.theme,
    required this.hover,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (radius <= 0) return;
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = theme.gridColor;
    final f = widget.valueFormatter;
    final n = widget.categories.length;

    if (widget.style == PolarBarStyle.rose) {
      if (widget.showGrid) {
        final rings = Cartesian2DAxes.niceTicks(0, max, count: 4).skip(1).toList();
        for (final v in rings) {
          final r = radius * (widget.areaProportional ? math.sqrt(v / max) : v / max);
          canvas.drawCircle(center, r, grid);
          // The outer ring's value would collide with the top category label.
          if (v == rings.last) continue;
          final tp = layoutChartText(f(v), color: theme.tickTextColor, fontSize: theme.tickFontSize - 1, fontFamily: theme.fontFamily);
          tp.paint(canvas, center + Offset(3, -r - tp.height));
        }
      }
      // Category labels around the rim.
      for (int i = 0; i < n; i++) {
        final a = -math.pi / 2 + (i + 0.5) * 2 * math.pi / n;
        final tp = layoutChartText(widget.categories[i], color: theme.axisColor, fontSize: theme.tickFontSize, fontFamily: theme.fontFamily);
        final p = center + Offset(math.cos(a), math.sin(a)) * (radius + 6 + tp.height / 2);
        tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
      }
    } else {
      // Tracks behind each ring, labels at the ring starts.
      final full = widget.radialSweep * math.pi / 180;
      for (final s in sectors) {
        canvas.drawArc(Rect.fromCircle(center: center, radius: (s.r1 + s.r2) / 2), -math.pi / 2, full, false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = s.r2 - s.r1
              ..color = theme.gridColor.withValues(alpha: theme.gridColor.a * 0.7));
        final label = widget.series.length > 1 ? '${s.hit.category} · ${s.hit.series}' : s.hit.category;
        final tp = layoutChartText('$label  ${f(s.hit.value)}',
            color: theme.tickTextColor, fontSize: math.min(theme.tickFontSize, (s.r2 - s.r1) * 0.9), fontFamily: theme.fontFamily);
        tp.paint(canvas, Offset(center.dx - 6 - tp.width, center.dy - (s.r1 + s.r2) / 2 - tp.height / 2));
      }
    }

    for (final s in sectors) {
      final color = hover == null || hover == s.hit ? s.color : s.color.withValues(alpha: 0.5);
      canvas.drawPath(s.path(center, progress), Paint()..color = color);
      if (widget.style == PolarBarStyle.rose) {
        canvas.drawPath(s.path(center, progress),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = theme.backgroundColor.a == 0 ? Colors.white.withValues(alpha: 0.7) : theme.backgroundColor);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PolarPainter old) => true;
}
