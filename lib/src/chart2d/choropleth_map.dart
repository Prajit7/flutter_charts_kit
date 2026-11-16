import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'theme.dart';
import 'chart_chrome.dart';
import 'common.dart';
import 'controller.dart';
import 'cartesian_axes.dart';

/// One region of a map: an id, its GeoJSON properties, and its outline as
/// polygons of rings in (longitude, latitude) — the first ring of each
/// polygon is its outer boundary, the rest are holes.
class GeoFeature {
  final String id;
  final Map<String, dynamic> properties;
  final List<List<List<Offset>>> polygons;

  const GeoFeature({required this.id, this.properties = const {}, required this.polygons});

  /// Longitude/latitude bounding box.
  Rect get bounds {
    double x0 = double.infinity, y0 = double.infinity, x1 = -double.infinity, y1 = -double.infinity;
    for (final poly in polygons) {
      for (final p in poly.isEmpty ? const <Offset>[] : poly.first) {
        x0 = math.min(x0, p.dx);
        y0 = math.min(y0, p.dy);
        x1 = math.max(x1, p.dx);
        y1 = math.max(y1, p.dy);
      }
    }
    return x0.isFinite ? Rect.fromLTRB(x0, y0, x1, y1) : Rect.zero;
  }

  /// Parses a GeoJSON `FeatureCollection` (or a single `Feature`) —
  /// e.g. from a bundled asset: `GeoFeature.parse(await rootBundle.loadString('assets/india.geojson'))`.
  ///
  /// Each feature's id comes from [idProperty] in its properties, falling
  /// back to the feature's own `id`, then its index. Polygon and
  /// MultiPolygon geometries are read; points and lines are skipped.
  static List<GeoFeature> parse(String geojson, {String idProperty = 'name'}) {
    final root = jsonDecode(geojson);
    if (root is! Map) throw const FormatException('GeoJSON root must be an object');
    final features = root['type'] == 'FeatureCollection' ? (root['features'] as List? ?? const []) : [root];
    final out = <GeoFeature>[];
    for (int i = 0; i < features.length; i++) {
      final f = features[i];
      if (f is! Map) continue;
      final props = (f['properties'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      final geometry = f['geometry'];
      if (geometry is! Map) continue;
      final polygons = <List<List<Offset>>>[];
      List<Offset> ring(List r) => [
            for (final c in r)
              if (c is List && c.length >= 2) Offset((c[0] as num).toDouble(), (c[1] as num).toDouble()),
          ];
      List<List<Offset>> polygon(List p) => [for (final r in p) if (r is List) ring(r)];
      switch (geometry['type']) {
        case 'Polygon':
          polygons.add(polygon(geometry['coordinates'] as List));
        case 'MultiPolygon':
          for (final p in geometry['coordinates'] as List) {
            polygons.add(polygon(p as List));
          }
        default:
          continue;
      }
      final id = props[idProperty] ?? f['id'] ?? i;
      out.add(GeoFeature(id: '$id', properties: props, polygons: polygons));
    }
    return out;
  }
}

/// How longitude/latitude are flattened onto the screen.
enum MapProjection {
  /// Conformal; the usual web-map look. Latitudes are clamped to ±85°.
  mercator,

  /// Longitude and latitude as plain x/y — simple, good near the equator
  /// and for small regions.
  equirectangular,
}

/// A choropleth map: regions shaded by a value — sales by state,
/// population by country, results by district.
///
/// Bring your own boundaries as GeoJSON (the package bundles none, so it
/// stays small and works for any country or level):
///
/// ```dart
/// final features = GeoFeature.parse(await rootBundle.loadString('assets/world.geojson'));
///
/// ChoroplethMap2D(
///   features: features,
///   values: {'India': 1428, 'China': 1425, 'United States of America': 340},
///   valueFormatter: (v) => '${v.round()}M',
/// )
/// ```
///
/// Drag to pan, pinch or scroll to zoom; hover or tap a region.
class ChoroplethMap2D extends StatefulWidget {
  final List<GeoFeature> features;

  /// Value per feature id. Regions without a value use [noDataColor].
  final Map<String, double> values;
  final String? title;
  final String? subtitle;
  final String emptyStateMessage;
  final MapProjection projection;

  /// Low → high colors.
  final List<Color> gradient;
  final Color? noDataColor;

  /// Color scale range; defaults to the values' min and max.
  final double? min;
  final double? max;

  /// Shade by log10 of the value — for values spanning orders of magnitude
  /// (populations, revenue). Non-positive values show as no-data.
  final bool logScale;
  final bool showLegend;
  final String Function(double value) valueFormatter;
  final Widget Function(BuildContext context, GeoFeature feature, double? value)? tooltipBuilder;
  final ChartController? controller;
  final void Function(GeoFeature feature, double? value)? onRegionTap;

  const ChoroplethMap2D({
    super.key,
    required this.features,
    required this.values,
    this.title,
    this.subtitle,
    this.emptyStateMessage = 'No regions',
    this.projection = MapProjection.mercator,
    this.gradient = const [Color(0xFFE3F2FD), Color(0xFF64B5F6), Color(0xFF1565C0), Color(0xFF0D2A6B)],
    this.noDataColor,
    this.min,
    this.max,
    this.logScale = false,
    this.showLegend = true,
    this.valueFormatter = Cartesian2DAxes.formatNumber,
    this.tooltipBuilder,
    this.controller,
    this.onRegionTap,
  });

  @override
  State<ChoroplethMap2D> createState() => _ChoroplethMap2DState();
}

/// A feature's projected outline (in unit projection space) and bounds.
class _Shape {
  final GeoFeature feature;
  final List<List<Offset>> rings; // all rings, projected
  final Rect bounds;
  _Shape(this.feature, this.rings, this.bounds);
}

class _ChoroplethMap2DState extends State<ChoroplethMap2D> with ChartControllerMixin<ChoroplethMap2D> {
  List<_Shape> _shapes = [];
  Rect _world = Rect.zero;
  double _zoom = 1;
  Offset _pan = Offset.zero;
  double _startZoom = 1;
  Offset _startPan = Offset.zero, _startFocal = Offset.zero;
  final ValueNotifier<(int, Offset)?> _hover = ValueNotifier(null);
  final ValueNotifier<int> _view = ValueNotifier(0);

  /// Screen paths, cached per (size, zoom, pan).
  (Size, double, Offset)? _pathKey;
  List<Path> _paths = [];

  @override
  ChartController? controllerOf(ChoroplethMap2D widget) => widget.controller;

  @override
  void resetZoom() {
    _zoom = 1;
    _pan = Offset.zero;
    reportZoomed(false);
    _view.value++;
  }

  @override
  void initState() {
    super.initState();
    _project();
  }

  @override
  void didUpdateWidget(covariant ChoroplethMap2D old) {
    super.didUpdateWidget(old);
    if (!identical(old.features, widget.features) || old.projection != widget.projection) {
      _project();
      _pathKey = null;
    }
  }

  @override
  void dispose() {
    _hover.dispose();
    _view.dispose();
    super.dispose();
  }

  Offset _projectPoint(Offset lonLat) {
    final x = lonLat.dx * math.pi / 180;
    if (widget.projection == MapProjection.equirectangular) return Offset(x, -lonLat.dy * math.pi / 180);
    final lat = lonLat.dy.clamp(-85.0, 85.0) * math.pi / 180;
    return Offset(x, -math.log(math.tan(math.pi / 4 + lat / 2)));
  }

  void _project() {
    _shapes = [];
    Rect? world;
    for (final f in widget.features) {
      final rings = <List<Offset>>[];
      double x0 = double.infinity, y0 = double.infinity, x1 = -double.infinity, y1 = -double.infinity;
      for (final poly in f.polygons) {
        for (final r in poly) {
          final pr = [for (final p in r) _projectPoint(p)];
          for (final p in pr) {
            x0 = math.min(x0, p.dx);
            y0 = math.min(y0, p.dy);
            x1 = math.max(x1, p.dx);
            y1 = math.max(y1, p.dy);
          }
          if (pr.length >= 3) rings.add(pr);
        }
      }
      if (rings.isEmpty) continue;
      final b = Rect.fromLTRB(x0, y0, x1, y1);
      _shapes.add(_Shape(f, rings, b));
      world = world == null ? b : world.expandToInclude(b);
    }
    _world = world ?? Rect.zero;
  }

  /// Projection space → screen.
  (double, Offset) _transform(Size size) {
    final w = _world;
    if (w.isEmpty) return (1, Offset.zero);
    const pad = 6.0;
    final fit = math.min((size.width - 2 * pad) / w.width, (size.height - 2 * pad) / w.height);
    final scale = fit * _zoom;
    final origin = size.center(Offset.zero) - w.center * scale + _pan;
    return (scale, origin);
  }

  List<Path> _screenPaths(Size size) {
    final key = (size, _zoom, _pan);
    if (_pathKey == key) return _paths;
    final (scale, origin) = _transform(size);
    _paths = [
      for (final s in _shapes)
        () {
          final path = Path()..fillType = PathFillType.evenOdd;
          for (final r in s.rings) {
            path.addPolygon([for (final p in r) origin + p * scale], true);
          }
          return path;
        }(),
    ];
    _pathKey = key;
    return _paths;
  }

  int? _regionAt(Offset pos, Size size) {
    final (scale, origin) = _transform(size);
    final p = (pos - origin) / scale;
    for (int i = _shapes.length - 1; i >= 0; i--) {
      final s = _shapes[i];
      if (!s.bounds.contains(p)) continue;
      // Even-odd over all rings: inside an outer ring, outside its holes.
      var inside = false;
      for (final r in s.rings) {
        for (int a = 0, b = r.length - 1; a < r.length; b = a++) {
          if ((r[a].dy > p.dy) != (r[b].dy > p.dy) &&
              p.dx < (r[b].dx - r[a].dx) * (p.dy - r[a].dy) / (r[b].dy - r[a].dy) + r[a].dx) {
            inside = !inside;
          }
        }
      }
      if (inside) return i;
    }
    return null;
  }

  double? _value(GeoFeature f) {
    final v = widget.values[f.id];
    if (v == null || !v.isFinite || (widget.logScale && v <= 0)) return null;
    return v;
  }

  (double, double) get _range {
    final vs = [
      for (final s in _shapes)
        if (_value(s.feature) != null) _value(s.feature)!,
    ];
    final lo = widget.min ?? (vs.isEmpty ? 0.0 : vs.reduce(math.min));
    final hi = widget.max ?? (vs.isEmpty ? 1.0 : vs.reduce(math.max));
    return (lo, hi);
  }

  double _t(double v, (double, double) range) {
    double f(double x) => widget.logScale ? math.log(math.max(x, 1e-12)) / math.ln10 : x;
    final lo = f(range.$1), hi = f(range.$2);
    return hi == lo ? 1 : ((f(v) - lo) / (hi - lo)).clamp(0.0, 1.0);
  }

  void _zoomAround(Offset p, double factor, Size size) {
    final z = (_zoom * factor).clamp(1.0, 40.0);
    final f = z / _zoom;
    final (_, origin) = _transform(size);
    _pan += (p - origin) * (1 - f);
    _zoom = z;
    if (_zoom == 1) _pan = Offset.zero;
    reportZoomed(_zoom > 1);
    _view.value++;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    if (_shapes.isEmpty) {
      return ChartFrame(
        boundaryKey: chartBoundaryKey,
        title: widget.title,
        subtitle: widget.subtitle,
        plot: ChartEmptyState(message: widget.emptyStateMessage),
      );
    }
    final range = _range;
    final ranked = [
      for (final s in _shapes)
        if (_value(s.feature) != null) (s.feature.id, _value(s.feature)!),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return ChartFrame(
      boundaryKey: chartBoundaryKey,
      semanticLabel: describeChart('Map', widget.title, [
        '${ranked.length} of ${_shapes.length} regions have data',
        if (ranked.isNotEmpty) 'highest: ${ranked.take(3).map((r) => '${r.$1} ${widget.valueFormatter(r.$2)}').join(', ')}',
      ]),
      title: widget.title,
      subtitle: widget.subtitle,
      plot: LayoutBuilder(builder: (context, constraints) {
        final full = constraints.biggest;
        final legendH = widget.showLegend ? 34.0 : 0.0;
        final size = Size(full.width, math.max(10, full.height - legendH));
        return Column(children: [
          SizedBox(
            width: size.width,
            height: size.height,
            child: ClipRect(
              child: Listener(
                onPointerSignal: (e) {
                  if (e is PointerScrollEvent) _zoomAround(e.localPosition, math.exp(-e.scrollDelta.dy * 0.002), size);
                },
                child: MouseRegion(
                  onHover: (e) {
                    final i = _regionAt(e.localPosition, size);
                    _hover.value = i == null ? null : (i, e.localPosition);
                  },
                  onExit: (_) => _hover.value = null,
                  child: GestureDetector(
                    onTapUp: (d) {
                      final i = _regionAt(d.localPosition, size);
                      _hover.value = i == null ? null : (i, d.localPosition);
                      if (i != null) widget.onRegionTap?.call(_shapes[i].feature, _value(_shapes[i].feature));
                    },
                    onScaleStart: (d) {
                      _startZoom = _zoom;
                      _startPan = _pan;
                      _startFocal = d.localFocalPoint;
                    },
                    onScaleUpdate: (d) {
                      _hover.value = null;
                      final z = (_startZoom * d.scale).clamp(1.0, 40.0);
                      // Keep the gesture's start point under the fingers.
                      final (_, o0) = _transformFor(size, _startZoom, _startPan);
                      final anchor = (_startFocal - o0) / _startZoom;
                      final (_, base) = _transformFor(size, z, Offset.zero);
                      _zoom = z;
                      _pan = d.localFocalPoint - anchor * z - base;
                      if (_zoom == 1 && d.pointerCount > 1) _pan = Offset.zero;
                      reportZoomed(_zoom > 1 || _pan != Offset.zero);
                      _view.value++;
                    },
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_view, _hover]),
                      builder: (context, _) {
                        final hover = _hover.value;
                        final paths = _screenPaths(size);
                        return Stack(children: [
                          CustomPaint(
                            size: size,
                            painter: _MapPainter(
                              paths: paths,
                              colors: [
                                for (final s in _shapes)
                                  () {
                                    final v = _value(s.feature);
                                    return v == null
                                        ? (widget.noDataColor ?? theme.gridColor.withValues(alpha: theme.gridColor.a * 0.6))
                                        : sampleGradient(widget.gradient, _t(v, range));
                                  }(),
                              ],
                              hovered: hover?.$1,
                              theme: theme,
                            ),
                          ),
                          if (_zoom > 1 || _pan != Offset.zero)
                            Positioned(right: 8, top: 8, child: ChartResetZoomButton(theme: theme, onTap: resetZoom)),
                          if (hover != null)
                            positionChartTooltip(
                              anchor: hover.$2,
                              areaSize: size,
                              cardWidth: 180,
                              child: widget.tooltipBuilder
                                      ?.call(context, _shapes[hover.$1].feature, _value(_shapes[hover.$1].feature)) ??
                                  ChartTooltipCard(
                                    theme: theme,
                                    width: 180,
                                    title: _shapes[hover.$1].feature.id,
                                    subtitle: () {
                                      final v = _value(_shapes[hover.$1].feature);
                                      if (v == null) return null;
                                      final rank = ranked.indexWhere((r) => r.$1 == _shapes[hover.$1].feature.id) + 1;
                                      return 'Rank $rank of ${ranked.length}';
                                    }(),
                                    value: _value(_shapes[hover.$1].feature) == null
                                        ? 'No data'
                                        : widget.valueFormatter(_value(_shapes[hover.$1].feature)!),
                                  ),
                            ),
                        ]);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.showLegend)
            SizedBox(
              height: legendH,
              width: full.width,
              child: CustomPaint(
                painter: _ScalePainter(
                  gradient: widget.gradient,
                  range: range,
                  logScale: widget.logScale,
                  formatter: widget.valueFormatter,
                  theme: theme,
                ),
              ),
            ),
        ]);
      }),
    );
  }

  (double, Offset) _transformFor(Size size, double zoom, Offset pan) {
    final (z0, p0) = (_zoom, _pan);
    _zoom = zoom;
    _pan = pan;
    final t = _transform(size);
    _zoom = z0;
    _pan = p0;
    return t;
  }
}

class _MapPainter extends CustomPainter {
  final List<Path> paths;
  final List<Color> colors;
  final int? hovered;
  final ChartTheme theme;

  _MapPainter({required this.paths, required this.colors, required this.hovered, required this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = theme.tooltipBackgroundColor.withValues(alpha: 0.9);
    for (int i = 0; i < paths.length; i++) {
      canvas.drawPath(paths[i], Paint()..color = colors[i]);
      canvas.drawPath(paths[i], border);
    }
    if (hovered != null) {
      canvas.drawPath(paths[hovered!], Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = theme.axisColor);
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) =>
      !identical(old.paths, paths) || old.hovered != hovered || old.theme != theme || old.colors.length != colors.length;
}

/// The color scale under the map: a gradient bar with min/mid/max labels.
class _ScalePainter extends CustomPainter {
  final List<Color> gradient;
  final (double, double) range;
  final bool logScale;
  final String Function(double) formatter;
  final ChartTheme theme;

  _ScalePainter({required this.gradient, required this.range, required this.logScale, required this.formatter, required this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    final w = math.min(260.0, size.width - 32);
    final bar = Rect.fromLTWH((size.width - w) / 2, 6, w, 9);
    const steps = 48;
    for (int i = 0; i < steps; i++) {
      canvas.drawRect(
        Rect.fromLTWH(bar.left + bar.width * i / steps, bar.top, bar.width / steps + 0.5, bar.height),
        Paint()..color = sampleGradient(gradient, i / (steps - 1)),
      );
    }
    final (lo, hi) = range;
    final mid = logScale && lo > 0 ? math.sqrt(lo * hi) : (lo + hi) / 2;
    for (final (v, f) in [(lo, 0.0), (mid, 0.5), (hi, 1.0)]) {
      final tp = layoutChartText(formatter(v), color: theme.tickTextColor, fontSize: 9, fontFamily: theme.fontFamily);
      final x = (bar.left + bar.width * f - tp.width * f).clamp(0.0, math.max(0.0, size.width - tp.width)).toDouble();
      tp.paint(canvas, Offset(x, bar.bottom + 3));
    }
  }

  @override
  bool shouldRepaint(covariant _ScalePainter old) => old.range != range || old.theme != theme;
}
