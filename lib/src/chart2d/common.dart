import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme.dart';
import 'zoom.dart';
import 'chart_chrome.dart';

/// Pieces shared by every 2D chart's interaction layer: the reset-zoom
/// button, the hover tooltip card, the drag-selection overlay, and the
/// drag-to-zoom gesture math. Internal — not exported from the package.

/// Small square button shown in a chart's top-right corner while zoomed.
class ChartResetZoomButton extends StatelessWidget {
  final VoidCallback onTap;
  final ChartTheme theme;
  final IconData icon;

  const ChartResetZoomButton({
    super.key,
    required this.onTap,
    required this.theme,
    this.icon = Icons.zoom_out_map,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.tooltipBackgroundColor,
      elevation: 1,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: theme.tooltipTextColor),
        ),
      ),
    );
  }
}

/// The hover/tap tooltip card: a bold [title], a muted [subtitle], and an
/// optional emphasised [value] line.
class ChartTooltipCard extends StatelessWidget {
  final ChartTheme theme;
  final String title;
  final String? subtitle;
  final String? value;
  final double? width;

  const ChartTooltipCard({
    super.key,
    required this.theme,
    required this.title,
    this.subtitle,
    this.value,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.tooltipBackgroundColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 12, color: theme.tooltipTextColor, fontFamily: theme.fontFamily)),
          if (subtitle != null)
            Text(subtitle!,
                style: TextStyle(
                    fontSize: 11,
                    color: theme.tooltipTextColor.withValues(alpha: 0.7),
                    fontFamily: theme.fontFamily)),
          if (value != null)
            Text(value!, style: TextStyle(fontSize: 13, color: theme.tooltipTextColor, fontFamily: theme.fontFamily)),
        ],
      ),
    );
  }
}

/// Places [child] (a tooltip of roughly [cardWidth]) beside [anchor] inside
/// a chart of [areaSize], flipping to the left of the anchor when it would
/// overflow the right edge. Must be used as a direct child of a [Stack].
Widget positionChartTooltip({
  required Offset anchor,
  required Size areaSize,
  required Widget child,
  double cardWidth = 150,
}) {
  double left = anchor.dx + 12;
  double top = anchor.dy - 50;
  if (left + cardWidth > areaSize.width) left = anchor.dx - cardWidth - 12;
  if (left < 0) left = 4;
  if (top < 0) top = 4;
  return Positioned(left: left, top: top, child: IgnorePointer(child: child));
}

/// Translucent rectangle drawn while the user drags out a zoom selection.
class ChartSelectionOverlay extends StatelessWidget {
  final Rect rect;
  final ChartTheme theme;

  const ChartSelectionOverlay({super.key, required this.rect, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            color: theme.crosshairColor.withValues(alpha: 0.15),
            border: Border.all(color: theme.crosshairColor, width: 1),
          ),
        ),
      ),
    );
  }
}

/// Tracks one drag-to-zoom gesture in screen space. Charts feed it pan
/// events and get back the selection rectangle to draw; converting that
/// rectangle into a data-space zoom window stays chart-specific.
class ChartDragZoom {
  Offset? _start;

  /// Begins a selection if [pos] is inside [plotArea]; drags that start on
  /// the axes or legend are ignored.
  void start(Offset pos, Rect plotArea) {
    _start = plotArea.contains(pos) ? pos : null;
  }

  /// The selection rectangle for the pointer at [pos], or null if no
  /// selection is in progress. In [ChartZoomMode.x] the band always spans
  /// the full plot height, since only its x-extent is used.
  Rect? update(Offset pos, Rect plotArea, ChartZoomMode mode) {
    final start = _start;
    if (start == null) return null;
    final clamped = Offset(
      pos.dx.clamp(plotArea.left, plotArea.right),
      pos.dy.clamp(plotArea.top, plotArea.bottom),
    );
    if (mode == ChartZoomMode.xy) return Rect.fromPoints(start, clamped);
    return Rect.fromLTRB(
      start.dx < clamped.dx ? start.dx : clamped.dx,
      plotArea.top,
      start.dx < clamped.dx ? clamped.dx : start.dx,
      plotArea.bottom,
    );
  }

  void end() => _start = null;

  /// Whether [rect] is too small to be an intentional zoom. In x mode only
  /// the width counts; in xy mode a sliver on either axis would collapse it.
  static bool isTooSmall(Rect rect, ChartZoomMode mode, double threshold) {
    if (mode == ChartZoomMode.xy) return rect.width < threshold || rect.height < threshold;
    return rect.width < threshold;
  }
}

/// Where a chart places its legend relative to the plot.
enum ChartLegendPosition { top, bottom, left, right, none }

/// The outer layout every 2D chart shares: header, then the plot with its
/// legend on the chosen side, all inside a [RepaintBoundary] (keyed by
/// [boundaryKey]) so [ChartController.toImage] can capture it.
class ChartFrame extends StatelessWidget {
  final GlobalKey boundaryKey;
  final String? title;
  final String? subtitle;
  final ChartLegendPosition legendPosition;

  /// Builds the legend for a horizontal (top/bottom) or vertical
  /// (left/right) layout. Null means no legend.
  final Widget Function(Axis direction)? legendBuilder;
  final Widget plot;

  /// Read by screen readers in place of the (unreadable) painted plot —
  /// see [describeChart].
  final String? semanticLabel;

  const ChartFrame({
    super.key,
    required this.boundaryKey,
    required this.plot,
    this.title,
    this.subtitle,
    this.legendPosition = ChartLegendPosition.bottom,
    this.legendBuilder,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    final position = legendBuilder == null ? ChartLegendPosition.none : legendPosition;
    final plotArea = Expanded(child: plot);

    final Widget body = switch (position) {
      ChartLegendPosition.none => Column(children: [plotArea]),
      ChartLegendPosition.bottom => Column(children: [
          plotArea,
          Padding(padding: const EdgeInsets.only(top: 6), child: legendBuilder!(Axis.horizontal)),
        ]),
      ChartLegendPosition.top => Column(children: [
          Padding(padding: const EdgeInsets.only(bottom: 6), child: legendBuilder!(Axis.horizontal)),
          plotArea,
        ]),
      ChartLegendPosition.left => Row(children: [
          Padding(padding: const EdgeInsets.only(right: 6), child: legendBuilder!(Axis.vertical)),
          plotArea,
        ]),
      ChartLegendPosition.right => Row(children: [
          plotArea,
          Padding(padding: const EdgeInsets.only(left: 6), child: legendBuilder!(Axis.vertical)),
        ]),
    };

    return RepaintBoundary(
      key: boundaryKey,
      child: Semantics(
        container: true,
        // Keep the title/legend as their own nodes rather than merging their
        // text into this summary label.
        explicitChildNodes: true,
        label: semanticLabel,
        child: ColoredBox(
        color: theme.backgroundColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ChartHeader(title: title, subtitle: subtitle),
            Expanded(child: body),
          ],
        ),
      ),
      ),
    );
  }
}

/// Lays out a single-style label for drawing on a canvas, optionally
/// ellipsized to [maxWidth].
TextPainter layoutChartText(
  String text, {
  required Color color,
  double fontSize = 10,
  FontWeight fontWeight = FontWeight.w600,
  String? fontFamily,
  double? maxWidth,
  TextAlign textAlign = TextAlign.left,
}) {
  return TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: fontSize, fontWeight: fontWeight, fontFamily: fontFamily),
    ),
    textDirection: TextDirection.ltr,
    textAlign: textAlign,
    maxLines: maxWidth == null ? null : 1,
    ellipsis: maxWidth == null ? null : '…',
  )..layout(maxWidth: maxWidth ?? double.infinity);
}

/// A color [t] (0–1) of the way along [stops], interpolating linearly.
Color sampleGradient(List<Color> stops, double t) {
  if (stops.length == 1) return stops.first;
  final scaled = t.clamp(0.0, 1.0) * (stops.length - 1);
  final i = scaled.floor().clamp(0, stops.length - 2);
  return Color.lerp(stops[i], stops[i + 1], scaled - i)!;
}

/// Black or white, whichever reads better on [background].
Color contrastingTextColor(Color background) =>
    background.computeLuminance() > 0.45 ? const Color(0xDD000000) : const Color(0xFFFFFFFF);

/// A short screen-reader summary of a chart: its [kind] and [title], then
/// one [parts] entry per series/item. Charts pass this to [ChartFrame].
/// Wrap a chart in `Semantics(label: ..., excludeSemantics: true)` to
/// replace it with your own description.
String describeChart(String kind, String? title, Iterable<String> parts) {
  final head = (title == null || title.isEmpty) ? kind : '$kind, $title';
  final list = parts.toList();
  return list.isEmpty ? '$head.' : '$head. ${list.join('; ')}.';
}

/// "name: 12 values from 3 to 48" — the range of a series for [describeChart].
String summarizeValues(String name, Iterable<double> values, String Function(double) format) {
  final v = values.where((x) => x.isFinite).toList();
  if (v.isEmpty) return '$name: no data';
  final lo = v.reduce(math.min), hi = v.reduce(math.max);
  return '$name: ${v.length} value${v.length == 1 ? '' : 's'} from ${format(lo)} to ${format(hi)}';
}
