import 'package:flutter/material.dart';
import 'cartesian_axes.dart';
import 'theme.dart';

/// Links the crosshairs of several charts: hovering one shows a crosshair at
/// the same x in all the others — the standard way to read a dashboard of
/// stacked charts (price, volume, indicators; revenue, costs, margin).
///
/// ```dart
/// final sync = ChartCrosshairSync();
/// ...
/// Column(children: [
///   Expanded(child: LineChart2D(crosshairSync: sync, series: revenue)),
///   Expanded(child: LineChart2D(crosshairSync: sync, series: costs)),
/// ])
/// ```
///
/// The x value is shared as-is, so linked charts must use the same x units:
/// data x for line/scatter, milliseconds since epoch for time axes and
/// candlesticks, the category index for bar/combo charts.
class ChartCrosshairSync extends ChangeNotifier {
  double? _x;
  Object? _source;

  /// The hovered x, or null when nothing is hovered.
  double? get x => _x;

  /// Publishes [x] on behalf of the chart [source].
  void update(Object source, double x) {
    if (_x == x && identical(_source, source)) return;
    _x = x;
    _source = source;
    notifyListeners();
  }

  /// Clears the crosshair, if [source] is the chart that set it.
  void clear(Object source) {
    if (!identical(_source, source)) return;
    _x = null;
    _source = null;
    notifyListeners();
  }

  /// The x another chart is hovering, as seen by [viewer] (null when
  /// nothing is hovered or [viewer] itself is the one hovering).
  double? xFor(Object viewer) => identical(_source, viewer) ? null : _x;
}

/// Paints a synced crosshair: a dashed vertical line at data [x] across
/// [axes]' plot, with optional [dots] (screen points, colored) on it.
class SyncCrosshairPainter extends CustomPainter {
  final Cartesian2DAxes axes;
  final double x;
  final List<(Offset, Color)> dots;
  final ChartTheme theme;

  SyncCrosshairPainter({required this.axes, required this.x, required this.theme, this.dots = const []});

  @override
  void paint(Canvas canvas, Size size) {
    final plot = axes.plotArea;
    final sx = axes.toScreenX(x);
    if (sx < plot.left - 0.5 || sx > plot.right + 0.5) return;
    axes.dashedLine(canvas, Offset(sx, plot.top), Offset(sx, plot.bottom), Paint()
      ..color = theme.crosshairColor
      ..strokeWidth = 1);
    for (final (p, color) in dots) {
      canvas.drawCircle(p, 4.5, Paint()..color = color);
      canvas.drawCircle(p, 4.5, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = theme.tooltipBackgroundColor);
    }
  }

  @override
  bool shouldRepaint(covariant SyncCrosshairPainter old) => old.x != x || old.axes.plotArea != axes.plotArea || old.dots.length != dots.length;
}

/// Paints a synced category highlight: a translucent band over [slot].
class SyncBandPainter extends CustomPainter {
  final Rect slot;
  final ChartTheme theme;

  SyncBandPainter({required this.slot, required this.theme});

  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawRect(slot, Paint()..color = theme.crosshairColor.withValues(alpha: theme.crosshairColor.a * 0.25));

  @override
  bool shouldRepaint(covariant SyncBandPainter old) => old.slot != slot;
}
