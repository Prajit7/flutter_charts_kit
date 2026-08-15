
/// Which axes a drag-to-zoom selection affects.
enum ChartZoomMode {
  /// Zoom disabled — dragging just does nothing.
  none,

  /// Classic Highcharts line-chart behavior: drag left-right selects an
  /// x-range; y auto-rescales to fit whatever falls inside it.
  x,

  /// Drag draws a full rectangle; both x and y are zoomed to it. Better
  /// fit for scatter plots where both axes carry meaning.
  xy,
}

/// The current zoomed data-space window. `null` fields mean "auto" (use
/// the full data range on that axis).
class ChartZoomWindow {
  final double minX;
  final double maxX;
  final double? minY;
  final double? maxY;

  const ChartZoomWindow({required this.minX, required this.maxX, this.minY, this.maxY});
}
