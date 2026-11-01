import 'package:flutter/material.dart';

/// The interactive surface shared by charts without drag-to-zoom (heatmap,
/// radar, funnel, treemap, sankey, …): it measures itself, hit-tests mouse
/// hover and taps into a chart-specific hover value [H], and runs the
/// entrance animation.
///
/// Charts supply how to hit-test, how to paint (given the current hover and
/// animation progress) and, optionally, a tooltip for the hovered item.
/// Hovering only rebuilds this subtree — never the chart's header/legend.
class HoverPlot<H> extends StatefulWidget {
  /// What's under [position] in a plot of [size], or null for nothing.
  final H? Function(Offset position, Size size) hitTest;

  /// The painter for the current [hover] and entrance [progress] (0–1).
  final CustomPainter Function(Size size, H? hover, double progress) painterBuilder;

  /// A tooltip for [hover] — typically from `positionChartTooltip` — or null.
  final Widget? Function(BuildContext context, H hover, Offset pointer, Size size)? tooltipBuilder;

  final ValueChanged<H?>? onHover;
  final ValueChanged<H>? onTap;

  final bool enableAnimation;
  final Duration animationDuration;

  /// The animation replays when this changes (by `==`), e.g. the data.
  final Object? animationKey;

  const HoverPlot({
    super.key,
    required this.hitTest,
    required this.painterBuilder,
    this.tooltipBuilder,
    this.onHover,
    this.onTap,
    this.enableAnimation = true,
    this.animationDuration = const Duration(milliseconds: 600),
    this.animationKey,
  });

  @override
  State<HoverPlot<H>> createState() => _HoverPlotState<H>();
}

class _HoverPlotState<H> extends State<HoverPlot<H>> with SingleTickerProviderStateMixin {
  final ValueNotifier<(H, Offset)?> _hover = ValueNotifier(null);
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.animationDuration);
    if (widget.enableAnimation) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant HoverPlot<H> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animationKey != widget.animationKey) {
      _hover.value = null;
      if (widget.enableAnimation) _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _hover.dispose();
    super.dispose();
  }

  H? _update(Offset pos, Size size) {
    final hit = widget.hitTest(pos, size);
    final previous = _hover.value?.$1;
    _hover.value = hit == null ? null : (hit, pos);
    if (hit != previous) widget.onHover?.call(hit);
    return hit;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      return MouseRegion(
        onHover: (e) => _update(e.localPosition, size),
        onExit: (_) {
          if (_hover.value != null) widget.onHover?.call(null);
          _hover.value = null;
        },
        child: GestureDetector(
          onTapUp: (d) {
            final hit = _update(d.localPosition, size);
            if (hit != null) widget.onTap?.call(hit);
          },
          child: ValueListenableBuilder<(H, Offset)?>(
            valueListenable: _hover,
            builder: (context, hover, _) {
              final tooltip = hover == null ? null : widget.tooltipBuilder?.call(context, hover.$1, hover.$2, size);
              return Stack(children: [
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => CustomPaint(
                    size: size,
                    painter: widget.painterBuilder(size, hover?.$1, _controller.value),
                  ),
                ),
                if (tooltip != null) tooltip,
              ]);
            },
          ),
        ),
      );
    });
  }
}
