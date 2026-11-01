import 'dart:math' as math;
import 'dart:ui';

/// How [LineChart2D] and [ComboChart2D] connect consecutive points.
enum LineChartCurve {
  /// Straight segments between points.
  straight,

  /// A smooth monotone curve: passes through every point and never
  /// overshoots it, so a smoothed line can't invent peaks or dips.
  smooth,

  /// A staircase: each value holds until the next point ("step after").
  step,
}

/// Appends a path through [pts] (in screen space) to [path] using [curve].
/// With [connect], the first point is joined with a line from wherever
/// [path] currently ends; otherwise a new sub-path starts there.
void traceCurve(Path path, List<Offset> pts, LineChartCurve curve, {bool connect = false}) {
  if (pts.isEmpty) return;
  connect ? path.lineTo(pts.first.dx, pts.first.dy) : path.moveTo(pts.first.dx, pts.first.dy);
  switch (curve) {
    case LineChartCurve.straight:
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
    case LineChartCurve.step:
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i - 1].dy);
        path.lineTo(pts[i].dx, pts[i].dy);
      }
    case LineChartCurve.smooth:
      _traceMonotone(path, pts);
  }
}

/// Monotone cubic interpolation (Fritsch–Carlson). Tangents are limited so
/// the curve stays within each segment's y-range — no fake peaks. Works for
/// points traversed right-to-left too (used for stacked area floors).
void _traceMonotone(Path path, List<Offset> pts) {
  final n = pts.length;
  if (n < 3) {
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    return;
  }
  final d = List<double>.generate(n - 1, (i) {
    final dx = pts[i + 1].dx - pts[i].dx;
    return dx == 0 ? 0 : (pts[i + 1].dy - pts[i].dy) / dx;
  });
  final m = List<double>.filled(n, 0);
  m[0] = d[0];
  m[n - 1] = d[n - 2];
  for (int i = 1; i < n - 1; i++) {
    m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
  }
  for (int i = 0; i < n - 1; i++) {
    if (d[i] == 0) {
      m[i] = 0;
      m[i + 1] = 0;
      continue;
    }
    final a = m[i] / d[i], b = m[i + 1] / d[i];
    final s = a * a + b * b;
    if (s > 9) {
      final t = 3 / math.sqrt(s);
      m[i] = t * a * d[i];
      m[i + 1] = t * b * d[i];
    }
  }
  for (int i = 0; i < n - 1; i++) {
    final p0 = pts[i], p1 = pts[i + 1];
    final h = p1.dx - p0.dx;
    path.cubicTo(p0.dx + h / 3, p0.dy + m[i] * h / 3, p1.dx - h / 3, p1.dy - m[i + 1] * h / 3, p1.dx, p1.dy);
  }
}
