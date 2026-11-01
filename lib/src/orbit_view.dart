import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'chart_controller.dart';
import 'chart2d/common.dart';
import 'chart2d/theme.dart';
import 'geometry.dart';

/// The interactive shell shared by [Bar3DChart] and [Scatter3DChart]:
/// drag to rotate (turntable), pinch or scroll to zoom, hover/tap to
/// hit-test, a reset button, an optional [Surface3DChartController], and an
/// entrance animation.
///
/// Charts provide the projection (usually [fitProjector] around their
/// model), how to hit-test and paint, and the tooltip for a hit [H].
class Orbit3DView<H> extends StatefulWidget {
  final double initialRotationX;
  final double initialRotationY;
  final double initialZoom;

  /// Builds the projector for the current view inside [size].
  final Projector Function(Size size, double rotationX, double rotationY, double zoom) projectorBuilder;
  final H? Function(Offset position, Size size, Projector projector) hitTest;
  final CustomPainter Function(Size size, Projector projector, H? hover, double progress) painterBuilder;
  final Widget? Function(BuildContext context, H hover, Offset pointer, Size size)? tooltipBuilder;

  /// Overlaid in a corner (e.g. a legend), or null.
  final Widget? overlay;
  final Alignment overlayAlignment;

  final bool showResetButton;
  final bool enableScrollZoom;
  final Surface3DChartController? controller;
  final ValueChanged<H?>? onHover;
  final ValueChanged<H>? onTap;
  final bool enableAnimation;
  final Duration animationDuration;

  /// The entrance animation replays when this changes (by `==`).
  final Object? animationKey;

  const Orbit3DView({
    super.key,
    required this.projectorBuilder,
    required this.hitTest,
    required this.painterBuilder,
    this.tooltipBuilder,
    this.initialRotationX = 0.6,
    this.initialRotationY = -0.7,
    this.initialZoom = 16,
    this.overlay,
    this.overlayAlignment = Alignment.bottomLeft,
    this.showResetButton = true,
    this.enableScrollZoom = true,
    this.controller,
    this.onHover,
    this.onTap,
    this.enableAnimation = true,
    this.animationDuration = const Duration(milliseconds: 700),
    this.animationKey,
  });

  @override
  State<Orbit3DView<H>> createState() => _Orbit3DViewState<H>();
}

class _OrbitState<H> {
  final double rotationX;
  final double rotationY;
  final double zoom;
  final H? hover;
  final Offset? pointer;

  const _OrbitState(this.rotationX, this.rotationY, this.zoom, [this.hover, this.pointer]);

  _OrbitState<H> withView(double rx, double ry, double z) => _OrbitState(rx, ry, z);
  _OrbitState<H> withHover(H? h, Offset? p) => _OrbitState(rotationX, rotationY, zoom, h, p);
}

class _Orbit3DViewState<H> extends State<Orbit3DView<H>> with SingleTickerProviderStateMixin {
  late final ValueNotifier<_OrbitState<H>> _view =
      ValueNotifier(_OrbitState(widget.initialRotationX, widget.initialRotationY, widget.initialZoom));
  late final AnimationController _controller;
  double _gestureBaseZoom = 16;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.animationDuration);
    widget.enableAnimation ? _controller.forward() : _controller.value = 1;
    widget.controller?.attach(_reset);
  }

  @override
  void didUpdateWidget(covariant Orbit3DView<H> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.detach();
      widget.controller?.attach(_reset);
    }
    if (oldWidget.animationKey != widget.animationKey) {
      _view.value = _view.value.withHover(null, null);
      if (widget.enableAnimation) _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    widget.controller?.detach();
    _controller.dispose();
    _view.dispose();
    super.dispose();
  }

  void _reset() => _view.value = _OrbitState(widget.initialRotationX, widget.initialRotationY, widget.initialZoom);

  Projector _projector(Size size) {
    final v = _view.value;
    return widget.projectorBuilder(size, v.rotationX, v.rotationY, v.zoom);
  }

  H? _updateHover(Offset pos, Size size) {
    final hit = widget.hitTest(pos, size, _projector(size));
    final previous = _view.value.hover;
    _view.value = _view.value.withHover(hit, hit == null ? null : pos);
    if (hit != previous) widget.onHover?.call(hit);
    return hit;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      return Listener(
        onPointerSignal: widget.enableScrollZoom
            ? (event) {
                if (event is PointerScrollEvent) {
                  final v = _view.value;
                  _view.value = v.withView(v.rotationX, v.rotationY, (v.zoom - event.scrollDelta.dy * 0.02).clamp(6.0, 48.0));
                }
              }
            : null,
        child: MouseRegion(
          onHover: (e) => _updateHover(e.localPosition, size),
          onExit: (_) {
            if (_view.value.hover != null) widget.onHover?.call(null);
            _view.value = _view.value.withHover(null, null);
          },
          child: GestureDetector(
            onScaleStart: (_) => _gestureBaseZoom = _view.value.zoom,
            onScaleUpdate: (d) {
              final v = _view.value;
              var rx = v.rotationX, ry = v.rotationY;
              // Only single-pointer movement rotates; a pinch's drifting
              // focal point shouldn't spin the model while zooming.
              if (d.pointerCount <= 1) {
                ry += d.focalPointDelta.dx * 0.01;
                // Keep the camera above the floor and short of straight down.
                rx = (rx + d.focalPointDelta.dy * 0.01).clamp(0.05, 1.5);
              }
              _view.value = v.withView(rx, ry, (_gestureBaseZoom * d.scale).clamp(6.0, 48.0));
            },
            onTapUp: (d) {
              final hit = _updateHover(d.localPosition, size);
              if (hit != null) widget.onTap?.call(hit);
            },
            child: AnimatedBuilder(
              animation: Listenable.merge([_view, _controller]),
              builder: (context, _) {
                final v = _view.value;
                final projector = _projector(size);
                final tooltip = v.hover == null ? null : widget.tooltipBuilder?.call(context, v.hover as H, v.pointer!, size);
                final a = widget.overlayAlignment;
                return Stack(children: [
                  CustomPaint(size: size, painter: widget.painterBuilder(size, projector, v.hover, _controller.value)),
                  if (widget.overlay != null)
                    Positioned(
                      left: a.x <= 0 ? 8 : null,
                      right: a.x > 0 ? 8 : null,
                      top: a.y <= 0 ? 8 : null,
                      bottom: a.y > 0 ? 8 : null,
                      child: widget.overlay!,
                    ),
                  if (widget.showResetButton)
                    Positioned(right: 8, top: 8, child: ChartResetZoomButton(theme: theme, icon: Icons.refresh, onTap: _reset)),
                  if (tooltip != null) tooltip,
                ]);
              },
            ),
          ),
        ),
      );
    });
  }
}
