import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keyboard access for a chart's plot: Tab focuses it, the arrow keys step
/// through its items (bars, points, cells, slices…) as if hovered — the
/// tooltip shows and its text is announced to screen readers — Enter or
/// Space activates (taps) the item, Escape clears.
///
/// It works on any chart through two callbacks: [hitTest] (what's at a
/// position — items are found by probing the plot once per size) and
/// [onNavigate] (show the chart's hover at a position, or clear it with
/// null). Items are ordered left to right, then top to bottom; Left/Up go
/// back, Right/Down forward, Home/End jump to the ends.
class ChartKeyboardNavigator extends StatefulWidget {
  final Widget child;
  final Size size;
  final Object? Function(Offset position) hitTest;
  final void Function(Offset? position) onNavigate;
  final void Function(Offset position)? onActivate;

  /// Probing grid spacing in pixels.
  final double step;

  /// Changes when the chart's items change (the probe is redone).
  final Object? itemsKey;

  const ChartKeyboardNavigator({
    super.key,
    required this.child,
    required this.size,
    required this.hitTest,
    required this.onNavigate,
    this.onActivate,
    this.step = 6,
    this.itemsKey,
  });

  @override
  State<ChartKeyboardNavigator> createState() => _ChartKeyboardNavigatorState();
}

class _ChartKeyboardNavigatorState extends State<ChartKeyboardNavigator> {
  final FocusNode _focus = FocusNode(debugLabel: 'chart plot');
  final GlobalKey _contentKey = GlobalKey();
  List<Offset>? _items;
  (Size, Object?)? _itemsFor;
  int _index = -1;
  bool _focused = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// One representative point per distinct item: the centre of the probe
  /// points that hit it (nudged to the nearest hit point if the centre
  /// falls outside the item, e.g. for a curved shape).
  List<Offset> _probe() {
    final key = (widget.size, widget.itemsKey);
    if (_items != null && _itemsFor == key) return _items!;
    final s = widget.size;
    final hits = <Object, List<Offset>>{};
    final order = <Object>[];
    for (double y = widget.step / 2; y < s.height; y += widget.step) {
      for (double x = widget.step / 2; x < s.width; x += widget.step) {
        final p = Offset(x, y);
        final h = widget.hitTest(p);
        if (h == null) continue;
        (hits[h] ??= (() {
          order.add(h);
          return <Offset>[];
        })())
            .add(p);
      }
    }
    final points = <Offset>[];
    for (final h in order) {
      final ps = hits[h]!;
      var c = ps.fold(Offset.zero, (a, b) => a + b) / ps.length.toDouble();
      if (widget.hitTest(c) != h) c = ps.reduce((a, b) => (a - c).distance <= (b - c).distance ? a : b);
      points.add(c);
    }
    points.sort((a, b) {
      final dx = a.dx - b.dx;
      return dx.abs() > 1 ? dx.sign.toInt() : a.dy.compareTo(b.dy);
    });
    _items = points;
    _itemsFor = key;
    _index = -1;
    return points;
  }

  void _go(int index) {
    final items = _probe();
    if (items.isEmpty) return;
    _index = index.clamp(0, items.length - 1);
    widget.onNavigate(items[_index]);
    setState(() {});
    // Announce what the tooltip now says.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final text = _visibleText();
      if (text.isNotEmpty) {
        final view = View.maybeOf(context);
        if (view != null) {
          SemanticsService.sendAnnouncement(view, text, Directionality.maybeOf(context) ?? ui.TextDirection.ltr);
        }
      }
    });
  }

  /// Text painted by widgets inside the plot (the tooltip card).
  String _visibleText() {
    final root = _contentKey.currentContext?.findRenderObject();
    if (root == null) return '';
    final parts = <String>[];
    void visit(RenderObject ro) {
      if (ro is RenderParagraph) {
        final t = ro.text.toPlainText().trim();
        if (t.isNotEmpty && !t.runes.any((r) => r >= 0xE000 && r <= 0xF8FF)) parts.add(t);
        return;
      }
      ro.visitChildren(visit);
    }

    visit(root);
    return parts.join(', ');
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final n = _probe().length;
    if (n == 0) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.arrowDown) {
      _go(_index < 0 ? 0 : (_index + 1) % n);
    } else if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowUp) {
      _go(_index < 0 ? n - 1 : (_index - 1 + n) % n);
    } else if (k == LogicalKeyboardKey.home) {
      _go(0);
    } else if (k == LogicalKeyboardKey.end) {
      _go(n - 1);
    } else if ((k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.numpadEnter) && _index >= 0) {
      widget.onActivate?.call(_items![_index]);
    } else if (k == LogicalKeyboardKey.escape && _index >= 0) {
      _index = -1;
      widget.onNavigate(null);
      setState(() {});
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final showRing = _focused && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (!f && _index >= 0) {
          _index = -1;
          widget.onNavigate(null);
        }
      },
      child: Semantics(
        // Tell screen-reader users how to explore the plot.
        hint: 'Use arrow keys to move between data points',
        child: Stack(children: [
          KeyedSubtree(key: _contentKey, child: widget.child),
          if (showRing)
            IgnorePointer(
              child: Container(
                width: widget.size.width,
                height: widget.size.height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0x995C6BC0), width: 1.5),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// [ChartKeyboardNavigator] that measures itself: callbacks get the size.
class ChartKeyboardPlot extends StatelessWidget {
  final Widget child;
  final Object? Function(Offset position, Size size) hitTest;
  final void Function(Offset? position, Size size) onNavigate;
  final void Function(Offset position, Size size)? onActivate;
  final Object? itemsKey;

  const ChartKeyboardPlot({
    super.key,
    required this.child,
    required this.hitTest,
    required this.onNavigate,
    this.onActivate,
    this.itemsKey,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest;
        return ChartKeyboardNavigator(
          size: size,
          itemsKey: itemsKey,
          hitTest: (p) => hitTest(p, size),
          onNavigate: (p) => onNavigate(p, size),
          onActivate: onActivate == null ? null : (p) => onActivate!(p, size),
          child: child,
        );
      });
}
