import 'package:flutter/foundation.dart';

/// Lets host apps trigger chart actions (like "reset view") from outside —
/// e.g. from a button in your own app bar rather than only the chart's
/// built-in reset button.
///
/// Usage:
/// ```dart
/// final controller = Surface3DChartController();
/// ...
/// Surface3DChart(controller: controller, ...);
/// ...
/// ElevatedButton(onPressed: controller.resetView, child: Text('Reset'));
/// ```
class Surface3DChartController {
  VoidCallback? _resetHandler;

  /// Called internally by the chart's State to hook itself up.
  void attach(VoidCallback resetHandler) {
    _resetHandler = resetHandler;
  }

  void detach() {
    _resetHandler = null;
  }

  /// Resets rotation and zoom back to the widget's initial values.
  void resetView() => _resetHandler?.call();
}
