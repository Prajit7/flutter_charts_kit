import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

/// A [TextPainter] that an SVG export can read back. Charts paint all their
/// text through this class: on an [SvgCanvas] it records the text and its
/// style as `<text>`, everywhere else it paints normally.
class ChartTextPainter extends TextPainter {
  ChartTextPainter({
    super.text,
    super.textAlign,
    super.textDirection,
    super.maxLines,
    super.ellipsis,
  });

  @override
  void paint(Canvas canvas, Offset offset) {
    if (canvas is SvgCanvas) {
      canvas._recordText(this, offset);
    } else {
      super.paint(canvas, offset);
    }
  }
}

String _num(double v) {
  if (!v.isFinite) return '0';
  final s = v.toStringAsFixed(2);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

String _escape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// Collects the elements and clip definitions of one SVG document.
class _SvgDocument {
  final Size size;
  final StringBuffer body = StringBuffer();
  final StringBuffer defs = StringBuffer();
  final Map<String, String> _clipIds = {};

  _SvgDocument(this.size);

  /// Emits [element], inside a clip group when [clip] is set.
  void add(String element, Rect? clip) {
    if (clip == null) {
      body.writeln(element);
      return;
    }
    if (clip.isEmpty) return; // fully clipped away
    final key = '${_num(clip.left)},${_num(clip.top)},${_num(clip.width)},${_num(clip.height)}';
    final id = _clipIds.putIfAbsent(key, () {
      final id = 'c${_clipIds.length}';
      defs.writeln('<clipPath id="$id"><rect x="${_num(clip.left)}" y="${_num(clip.top)}" '
          'width="${_num(clip.width)}" height="${_num(clip.height)}"/></clipPath>');
      return id;
    });
    body.writeln('<g clip-path="url(#$id)">$element</g>');
  }

  String toSvg({Color? background}) {
    final w = _num(size.width), h = _num(size.height);
    return [
      '<svg xmlns="http://www.w3.org/2000/svg" width="$w" height="$h" viewBox="0 0 $w $h" '
          'font-family="Roboto, Helvetica, Arial, sans-serif">',
      if (defs.isNotEmpty) '<defs>\n$defs</defs>',
      if (background != null && background.a > 0) '<rect width="$w" height="$h" fill="${_hex(background)}"/>',
      body.toString().trimRight(),
      '</svg>',
    ].join('\n');
  }
}

/// A [Canvas] that records drawing as SVG elements instead of pixels.
///
/// Supports what the package's charts use: lines, rects, rounded rects,
/// circles, ovals, arcs, paths (sampled into polylines, since Flutter paths
/// can't be read back), points, clip rects, transforms and [ChartTextPainter]
/// text. Shader fills (gradients) and images are skipped.
class SvgCanvas implements Canvas {
  final _SvgDocument _doc;
  Matrix4 _matrix;
  Rect? _clip;
  final List<(Matrix4, Rect?)> _stack = [];

  SvgCanvas._(this._doc, Matrix4 base, this._clip) : _matrix = base.clone();

  // ---- state ----

  @override
  void save() => _stack.add((_matrix.clone(), _clip));

  @override
  void saveLayer(Rect? bounds, Paint paint) => save();

  @override
  void restore() {
    if (_stack.isEmpty) return;
    final (m, c) = _stack.removeLast();
    _matrix = m;
    _clip = c;
  }

  @override
  int getSaveCount() => _stack.length + 1;

  @override
  void restoreToCount(int count) {
    while (getSaveCount() > count && _stack.isNotEmpty) {
      restore();
    }
  }

  @override
  void translate(double dx, double dy) => _matrix.multiply(Matrix4.translationValues(dx, dy, 0));

  @override
  void scale(double sx, [double? sy]) => _matrix.multiply(Matrix4.diagonal3Values(sx, sy ?? sx, 1));

  @override
  void rotate(double radians) => _matrix.rotateZ(radians);

  @override
  void transform(Float64List matrix4) => _matrix.multiply(Matrix4.fromFloat64List(matrix4));

  @override
  Float64List getTransform() => Float64List.fromList(_matrix.storage);

  @override
  void clipRect(Rect rect, {ui.ClipOp clipOp = ui.ClipOp.intersect, bool doAntiAlias = true}) {
    if (clipOp == ui.ClipOp.difference) return;
    final r = MatrixUtils.transformRect(_matrix, rect);
    _clip = _clip == null ? r : _clip!.intersect(r);
  }

  @override
  void clipRRect(RRect rrect, {bool doAntiAlias = true}) => clipRect(rrect.outerRect);

  @override
  void clipPath(Path path, {bool doAntiAlias = true}) => clipRect(path.getBounds());

  @override
  Rect getLocalClipBounds() => Rect.largest;

  @override
  Rect getDestinationClipBounds() => _clip ?? Rect.largest;

  // ---- helpers ----

  Offset _t(Offset p) => MatrixUtils.transformPoint(_matrix, p);

  /// How much the current transform scales lengths (for stroke widths).
  double get _scale {
    final m = _matrix.storage;
    return math.sqrt((m[0] * m[5] - m[1] * m[4]).abs());
  }

  bool get _axisAligned => _matrix.storage[1].abs() < 1e-9 && _matrix.storage[4].abs() < 1e-9;

  /// Fill/stroke attributes for [paint], or null for a paint we can't
  /// express (shader fills) — such shapes are skipped.
  String? _style(Paint paint) {
    if (paint.shader != null) return null;
    final c = paint.color;
    if (c.a == 0) return null;
    final color = _hex(c), opacity = c.a < 1 ? _num(c.a) : null;
    if (paint.style == PaintingStyle.stroke) {
      final cap = switch (paint.strokeCap) {
        StrokeCap.round => ' stroke-linecap="round"',
        StrokeCap.square => ' stroke-linecap="square"',
        StrokeCap.butt => '',
      };
      return 'fill="none" stroke="$color"${opacity == null ? '' : ' stroke-opacity="$opacity"'} '
          'stroke-width="${_num(math.max(paint.strokeWidth, 1) * _scale)}"$cap';
    }
    return 'fill="$color"${opacity == null ? '' : ' fill-opacity="$opacity"'}';
  }

  /// [paint] forced to a stroke (lines are always stroked).
  String? _strokeStyle(Paint paint) {
    final p = Paint()
      ..color = paint.color
      ..shader = paint.shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = paint.strokeWidth
      ..strokeCap = paint.strokeCap;
    return _style(p);
  }

  void _polygon(List<Offset> pts, bool closed, String style) {
    if (pts.length < 2) return;
    final d = StringBuffer('M${_num(pts.first.dx)} ${_num(pts.first.dy)}');
    for (final p in pts.skip(1)) {
      d.write('L${_num(p.dx)} ${_num(p.dy)}');
    }
    if (closed) d.write('Z');
    _doc.add('<path d="$d" $style/>', _clip);
  }

  // ---- drawing ----

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    final style = _strokeStyle(paint);
    if (style == null) return;
    final a = _t(p1), b = _t(p2);
    _doc.add('<line x1="${_num(a.dx)}" y1="${_num(a.dy)}" x2="${_num(b.dx)}" y2="${_num(b.dy)}" $style/>', _clip);
  }

  @override
  void drawRect(Rect rect, Paint paint) {
    final style = _style(paint);
    if (style == null) return;
    if (_axisAligned) {
      final r = MatrixUtils.transformRect(_matrix, rect);
      _doc.add('<rect x="${_num(r.left)}" y="${_num(r.top)}" width="${_num(r.width)}" height="${_num(r.height)}" $style/>', _clip);
    } else {
      _polygon([rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft].map(_t).toList(), true, style);
    }
  }

  @override
  void drawRRect(RRect rrect, Paint paint) {
    final style = _style(paint);
    if (style == null) return;
    if (_axisAligned) {
      // SVG rects take one radius; use the largest corner's.
      final r = MatrixUtils.transformRect(_matrix, rrect.outerRect);
      final rx = [rrect.tlRadiusX, rrect.trRadiusX, rrect.brRadiusX, rrect.blRadiusX].reduce(math.max) * _scale;
      _doc.add('<rect x="${_num(r.left)}" y="${_num(r.top)}" width="${_num(r.width)}" height="${_num(r.height)}" '
          'rx="${_num(rx)}" $style/>', _clip);
    } else {
      drawPath(Path()..addRRect(rrect), paint);
    }
  }

  @override
  void drawDRRect(RRect outer, RRect inner, Paint paint) => drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRRect(outer)
          ..addRRect(inner),
        paint,
      );

  @override
  void drawCircle(Offset c, double radius, Paint paint) {
    final style = _style(paint);
    if (style == null || radius <= 0) return;
    final p = _t(c);
    _doc.add('<circle cx="${_num(p.dx)}" cy="${_num(p.dy)}" r="${_num(radius * _scale)}" $style/>', _clip);
  }

  @override
  void drawOval(Rect rect, Paint paint) => drawPath(Path()..addOval(rect), paint);

  @override
  void drawArc(Rect rect, double startAngle, double sweepAngle, bool useCenter, Paint paint) {
    final path = Path();
    if (useCenter) path.moveTo(rect.center.dx, rect.center.dy);
    path.arcTo(rect, startAngle, sweepAngle, !useCenter);
    if (useCenter) path.close();
    drawPath(path, paint);
  }

  @override
  void drawPath(Path path, Paint paint) {
    final style = _style(paint);
    if (style == null) return;
    // Flutter can't read a path's commands back, so sample each contour.
    final d = StringBuffer();
    for (final metric in path.computeMetrics()) {
      final steps = math.max(2, math.min(4000, (metric.length * _scale / 1.5).ceil()));
      for (int i = 0; i <= steps; i++) {
        final pos = metric.getTangentForOffset(metric.length * i / steps)?.position;
        if (pos == null) continue;
        final p = _t(pos);
        d.write('${i == 0 ? 'M' : 'L'}${_num(p.dx)} ${_num(p.dy)}');
      }
      if (metric.isClosed) d.write('Z');
    }
    if (d.isEmpty) return;
    final rule = path.fillType == PathFillType.evenOdd ? ' fill-rule="evenodd"' : '';
    _doc.add('<path d="$d"$rule $style/>', _clip);
  }

  @override
  void drawPoints(ui.PointMode pointMode, List<Offset> points, Paint paint) {
    if (pointMode == ui.PointMode.points) {
      final dot = Paint()..color = paint.color;
      for (final p in points) {
        paint.strokeCap == StrokeCap.round
            ? drawCircle(p, paint.strokeWidth / 2, dot)
            : drawRect(Rect.fromCenter(center: p, width: paint.strokeWidth, height: paint.strokeWidth), dot);
      }
    } else if (pointMode == ui.PointMode.lines) {
      for (int i = 0; i + 1 < points.length; i += 2) {
        drawLine(points[i], points[i + 1], paint);
      }
    } else {
      final style = _strokeStyle(paint);
      if (style != null) _polygon(points.map(_t).toList(), false, style);
    }
  }

  @override
  void drawRawPoints(ui.PointMode pointMode, Float32List points, Paint paint) =>
      drawPoints(pointMode, [for (int i = 0; i + 1 < points.length; i += 2) Offset(points[i], points[i + 1])], paint);

  void _recordText(ChartTextPainter tp, Offset offset) {
    final span = tp.text;
    if (span == null) return;
    // (text, style) runs, inheriting the root style.
    final runs = <(String, TextStyle?)>[];
    void collect(InlineSpan s, TextStyle? inherited) {
      if (s is! TextSpan) return;
      final style = inherited == null ? s.style : inherited.merge(s.style);
      if (s.text != null && s.text!.isNotEmpty) runs.add((s.text!, style));
      for (final c in s.children ?? const <InlineSpan>[]) {
        collect(c, style);
      }
    }

    collect(span, null);
    if (runs.isEmpty) return;
    // Ellipsized text: keep what fit, plus the ellipsis.
    if (tp.didExceedMaxLines && runs.length == 1) {
      final fit = tp.getPositionForOffset(Offset(tp.width, tp.height / 2)).offset;
      final (text, style) = runs.single;
      runs[0] = ('${text.substring(0, math.max(0, math.min(text.length, fit - 1)))}…', style);
    }
    final baseline = offset.dy + tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final m = _matrix.storage;
    final tspans = StringBuffer();
    for (final (text, style) in runs) {
      tspans.write('<tspan${_textStyle(style)}>${_escape(text)}</tspan>');
    }
    // A transform attribute keeps rotated titles rotated; the clip group
    // around it stays in page coordinates.
    _doc.add(
      '<text x="${_num(offset.dx)}" y="${_num(baseline)}" '
      'transform="matrix(${_num(m[0])} ${_num(m[1])} ${_num(m[4])} ${_num(m[5])} ${_num(m[12])} ${_num(m[13])})"'
      '${_textStyle(runs.first.$2)}>$tspans</text>',
      _clip,
    );
  }

  // Unused by the charts; anything else draws nothing.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

String _textStyle(TextStyle? s) {
  if (s == null) return '';
  final b = StringBuffer();
  if (s.color != null) {
    b.write(' fill="${_hex(s.color!)}"');
    if (s.color!.a < 1) b.write(' fill-opacity="${_num(s.color!.a)}"');
  }
  if (s.fontSize != null) b.write(' font-size="${_num(s.fontSize!)}"');
  final w = s.fontWeight?.value;
  if (w != null && w != 400) b.write(' font-weight="$w"');
  // Name the chart's font, but fall back to common sans-serifs in viewers
  // that don't have it.
  if (s.fontFamily != null) b.write(' font-family="${_escape(s.fontFamily!)}, Helvetica, Arial, sans-serif"');
  return b.toString();
}

/// Renders the render tree under [root] as an SVG document: custom painters
/// are replayed into an [SvgCanvas]; text widgets, decorated/colored boxes
/// and cards are read from the render tree.
String renderTreeToSvg(RenderObject root, Size size, {Color? background}) {
  final doc = _SvgDocument(size);

  void fill(Matrix4 m, Rect rect, Color? color, {double radius = 0, bool circle = false}) {
    if (color == null || color.a == 0) return;
    final canvas = SvgCanvas._(doc, m, null);
    final paint = Paint()..color = color;
    if (circle) {
      canvas.drawCircle(rect.center, rect.shortestSide / 2, paint);
    } else if (radius > 0) {
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)), paint);
    } else {
      canvas.drawRect(rect, paint);
    }
  }

  void visit(RenderObject ro) {
    final m = ro.getTransformTo(root);
    if (ro is RenderCustomPaint) {
      ro.painter?.paint(SvgCanvas._(doc, m, null), ro.size);
      ro.visitChildren(visit);
      ro.foregroundPainter?.paint(SvgCanvas._(doc, m, null), ro.size);
      return;
    }
    if (ro is RenderParagraph) {
      _paragraph(doc, ro, m);
      return;
    }
    if (ro is RenderDecoratedBox && ro.decoration is BoxDecoration) {
      final d = ro.decoration as BoxDecoration;
      final r = d.borderRadius is BorderRadius ? (d.borderRadius! as BorderRadius).topLeft.x : 0.0;
      fill(m, Offset.zero & ro.size, d.color, radius: r, circle: d.shape == BoxShape.circle);
    } else if (ro is RenderPhysicalShape) {
      fill(m, Offset.zero & ro.size, ro.color, radius: 12);
    } else if (ro is RenderPhysicalModel) {
      fill(m, Offset.zero & ro.size, ro.color, radius: ro.borderRadius?.topLeft.x ?? 0);
    } else if (ro is RenderBox && ro.runtimeType.toString() == '_RenderColoredBox') {
      // ColoredBox's render object is private; its color is a public getter.
      try {
        fill(m, Offset.zero & ro.size, (ro as dynamic).color as Color);
      } catch (_) {}
    }
    ro.visitChildren(visit);
  }

  visit(root);
  return doc.toSvg(background: background);
}

/// A Text widget's paragraph as `<text>`, one line per `\n`.
void _paragraph(_SvgDocument doc, RenderParagraph p, Matrix4 m) {
  final style = p.text.style;
  final text = p.text.toPlainText();
  // Icons are glyphs in a private-use font range; they can't be exported as text.
  if (text.isEmpty || style?.fontFamily == 'MaterialIcons' || text.runes.any((r) => r >= 0xE000 && r <= 0xF8FF)) return;
  final size = style?.fontSize ?? 14;
  final lineHeight = size * (style?.height ?? 1.2);
  final anchor = switch (p.textAlign) {
    TextAlign.center => (' text-anchor="middle"', p.size.width / 2),
    TextAlign.right || TextAlign.end => (' text-anchor="end"', p.size.width),
    _ => ('', 0.0),
  };
  final s = m.storage;
  final lines = text.split('\n');
  for (int i = 0; i < lines.length; i++) {
    doc.add(
      '<text x="${_num(anchor.$2)}" y="${_num(size * 0.95 + i * lineHeight)}"${anchor.$1} '
      'transform="matrix(${_num(s[0])} ${_num(s[1])} ${_num(s[4])} ${_num(s[5])} ${_num(s[12])} ${_num(s[13])})"'
      '${_textStyle(style)}>${_escape(lines[i])}</text>',
      null,
    );
  }
}
