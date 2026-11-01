import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Drives a 2D chart from outside — reset its zoom from your own toolbar, or
/// export what it currently shows as a PNG.
///
/// ```dart
/// final controller = ChartController();
/// ...
/// LineChart2D(controller: controller, series: ...);
/// ...
/// IconButton(icon: Icon(Icons.zoom_out_map), onPressed: controller.resetZoom);
/// final png = await controller.toPngBytes();
/// ```
///
/// One controller drives one chart at a time. Listen to it (it's a
/// [ChangeNotifier]) to rebuild when [isZoomed] changes.
class ChartController extends ChangeNotifier {
  VoidCallback? _resetZoom;
  GlobalKey? _boundaryKey;
  bool _isZoomed = false;

  /// Whether the attached chart is currently zoomed in.
  bool get isZoomed => _isZoomed;

  /// Whether a chart is currently attached to this controller.
  bool get isAttached => _boundaryKey != null;

  /// Called by the chart's State to hook itself up. Not for app code.
  void attach({required VoidCallback resetZoom, required GlobalKey boundaryKey}) {
    _resetZoom = resetZoom;
    _boundaryKey = boundaryKey;
  }

  /// Called by the chart's State when it goes away. Not for app code.
  void detach(GlobalKey boundaryKey) {
    if (_boundaryKey != boundaryKey) return; // another chart took over
    _resetZoom = null;
    _boundaryKey = null;
    _setZoomed(false);
  }

  /// Called by the chart's State whenever its zoom changes. Not for app code.
  void reportZoomed(bool zoomed) => _setZoomed(zoomed);

  void _setZoomed(bool zoomed) {
    if (_isZoomed == zoomed) return;
    _isZoomed = zoomed;
    // Zoom changes happen during gesture/build callbacks; notify after the
    // frame so listeners can safely call setState.
    SchedulerBinding.instance.addPostFrameCallback((_) => notifyListeners());
  }

  /// Clears any zoom on the attached chart.
  void resetZoom() => _resetZoom?.call();

  /// Renders the attached chart (title, plot, and legend) to an image.
  /// Returns null if no chart is attached or it hasn't been laid out yet.
  Future<ui.Image?> toImage({double pixelRatio = 2}) async {
    final boundary = _boundaryKey?.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;
    return boundary.toImage(pixelRatio: pixelRatio);
  }

  /// Same as [toImage], encoded as PNG bytes — ready to save or share.
  Future<Uint8List?> toPngBytes({double pixelRatio = 2}) async {
    final image = await toImage(pixelRatio: pixelRatio);
    if (image == null) return null;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}

/// Wires a chart's State to its optional [ChartController]: attaches on
/// init, re-attaches when the widget's controller changes, detaches on
/// dispose. Charts implement [controllerOf] and [resetZoom], wrap their
/// output in a [RepaintBoundary] keyed by [chartBoundaryKey], and call
/// [reportZoomed] when their zoom changes.
mixin ChartControllerMixin<T extends StatefulWidget> on State<T> {
  final GlobalKey chartBoundaryKey = GlobalKey();

  ChartController? controllerOf(T widget);

  void resetZoom();

  void reportZoomed(bool zoomed) => controllerOf(widget)?.reportZoomed(zoomed);

  @override
  void initState() {
    super.initState();
    controllerOf(widget)?.attach(resetZoom: resetZoom, boundaryKey: chartBoundaryKey);
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = controllerOf(oldWidget);
    final current = controllerOf(widget);
    if (previous != current) {
      previous?.detach(chartBoundaryKey);
      current?.attach(resetZoom: resetZoom, boundaryKey: chartBoundaryKey);
    }
  }

  @override
  void dispose() {
    controllerOf(widget)?.detach(chartBoundaryKey);
    super.dispose();
  }
}
