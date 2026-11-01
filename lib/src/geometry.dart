import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A point in 3D model space (before projection to the screen).
class Point3D {
  final double x, y, z;
  const Point3D(this.x, this.y, this.z);
}

/// Handles rotation + perspective projection from 3D model space to 2D
/// screen space. Knows nothing about what the data represents.
class Projector {
  final double rotationX;
  final double rotationY;
  final double zoom;
  final Offset center;

  /// Distance from the camera to the model's origin, in model units. Must
  /// comfortably exceed the model's radius, or near points blow up.
  final double cameraDistance;

  const Projector({
    required this.rotationX,
    required this.rotationY,
    required this.zoom,
    required this.center,
    this.cameraDistance = 700,
  });

  /// Rotated point, pre-perspective. Useful for depth sorting.
  ///
  /// A turntable camera: [rotationY] spins the model about its vertical
  /// (z) axis, then [rotationX] tilts it toward the viewer. Vertical lines
  /// in the model stay vertical on screen at every angle.
  Point3D rotate(Point3D p) {
    // Spin about the vertical axis.
    final cy = math.cos(rotationY), sy = math.sin(rotationY);
    final x = p.x * cy - p.y * sy;
    final y0 = p.x * sy + p.y * cy;

    // Tilt: positive rotationX looks down onto the floor; up (+z) is up-screen.
    final cx = math.cos(rotationX), sx = math.sin(rotationX);
    final y = y0 * sx - p.z * cx;
    final z = y0 * cx + p.z * sx;
    return Point3D(x, y, z);
  }

  Offset project(Point3D p) {
    final r = rotate(p);
    final perspective = cameraDistance / (cameraDistance - r.z);
    return Offset(
      center.dx + r.x * perspective * zoom / 20,
      center.dy + r.y * perspective * zoom / 20,
    );
  }
}

/// One rendered tile of the surface — the quad between four adjacent grid
/// points, plus enough metadata to support hit-testing and tooltips.
class SurfaceQuad {
  final Path path;
  final double value;
  final int colIndex; // index into xLabels
  final int rowIndex; // index into yLabels
  final Offset centroid; // screen point to anchor a tooltip
  final double depth; // rotated z, used for back-to-front painting

  SurfaceQuad({
    required this.path,
    required this.value,
    required this.colIndex,
    required this.rowIndex,
    required this.centroid,
    required this.depth,
  });
}

/// Builds the mesh of [SurfaceQuad]s for a `data[row][col]` grid. Shared by
/// the painter (drawing) and the widget (hit-testing), so both always agree
/// on where each tile actually is on screen.
class SurfaceGeometry {
  final List<List<double>> data;
  final double spacing;
  final double zScale;
  final Projector projector;

  SurfaceGeometry({
    required this.data,
    required this.spacing,
    required this.zScale,
    required this.projector,
  });

  Point3D gridPoint(int rowIdx, int colIdx) {
    final rows = data.length;
    final cols = data[0].length;
    final x = (colIdx - cols / 2) * spacing;
    final y = (rowIdx - rows / 2) * spacing;
    final z = data[rowIdx][colIdx] * zScale;
    return Point3D(x, y, z);
  }

  List<SurfaceQuad> buildQuads() {
    final quads = <SurfaceQuad>[];
    final rows = data.length;
    final cols = data[0].length;

    for (int r = 0; r < rows - 1; r++) {
      for (int c = 0; c < cols - 1; c++) {
        final p1 = gridPoint(r, c);
        final p2 = gridPoint(r, c + 1);
        final p3 = gridPoint(r + 1, c + 1);
        final p4 = gridPoint(r + 1, c);

        final s1 = projector.project(p1);
        final s2 = projector.project(p2);
        final s3 = projector.project(p3);
        final s4 = projector.project(p4);

        final path = Path()
          ..moveTo(s1.dx, s1.dy)
          ..lineTo(s2.dx, s2.dy)
          ..lineTo(s3.dx, s3.dy)
          ..lineTo(s4.dx, s4.dy)
          ..close();

        final avgValue =
            (data[r][c] + data[r][c + 1] + data[r + 1][c] + data[r + 1][c + 1]) / 4;

        final avgDepth = (projector.rotate(p1).z +
                projector.rotate(p2).z +
                projector.rotate(p3).z +
                projector.rotate(p4).z) /
            4;

        final centroid = Offset(
          (s1.dx + s2.dx + s3.dx + s4.dx) / 4,
          (s1.dy + s2.dy + s3.dy + s4.dy) / 4,
        );

        quads.add(SurfaceQuad(
          path: path,
          value: avgValue,
          colIndex: c,
          rowIndex: r,
          centroid: centroid,
          depth: avgDepth,
        ));
      }
    }
    // back-to-front so nearer tiles paint over farther ones
    quads.sort((a, b) => a.depth.compareTo(b.depth));
    return quads;
  }
}

/// A [Projector] that fits a model's bounding box — `x ∈ [xMin, xMax]`,
/// `y ∈ [yMin, yMax]`, `z ∈ [zMin, zMax]` in model space — into [area], leaving
/// [margin] pixels around it for axis labels.
///
/// The scale is measured at the fit rotation ([fitRotationX]/[fitRotationY],
/// typically the chart's initial view) so it stays constant while the user
/// rotates; the model is re-centred in [area] at every rotation.
///
/// [zoom] is relative to [defaultZoom]: at `zoom == defaultZoom` the model
/// fills the area; double it to zoom in 2×. The camera is pushed back in
/// proportion to the model's size, so large grids keep natural perspective.
Projector fitProjector({
  required Rect area,
  required double rotationX,
  required double rotationY,
  required double zoom,
  required double xMin,
  required double xMax,
  required double yMin,
  required double yMax,
  required double zMin,
  required double zMax,
  double? fitRotationX,
  double? fitRotationY,
  double defaultZoom = 16,
  double margin = 28,
}) {
  final corners = [
    for (final x in [xMin, xMax])
      for (final y in [yMin, yMax])
        for (final z in [zMin, zMax]) Point3D(x, y, z),
  ];
  // The camera distance must exceed the farthest corner from the origin
  // (the rotation centre), not just the box's own half-diagonal.
  final radius = corners.map((c) => math.sqrt(c.x * c.x + c.y * c.y + c.z * c.z)).reduce(math.max);
  final camera = math.max(700.0, radius * 3);

  // Projected bounds of the box at unit scale (zoom 20 = 1px per unit).
  Rect bounds(double rx, double ry) {
    final p = Projector(rotationX: rx, rotationY: ry, zoom: 20, center: Offset.zero, cameraDistance: camera);
    final pts = corners.map(p.project).toList();
    return Rect.fromLTRB(pts.map((o) => o.dx).reduce(math.min), pts.map((o) => o.dy).reduce(math.min),
        pts.map((o) => o.dx).reduce(math.max), pts.map((o) => o.dy).reduce(math.max));
  }

  final fit = bounds(fitRotationX ?? rotationX, fitRotationY ?? rotationY);
  final availW = math.max(1.0, area.width - 2 * margin), availH = math.max(1.0, area.height - 2 * margin);
  final scale = math.min(availW / math.max(fit.width, 1), availH / math.max(fit.height, 1)) * (zoom / defaultZoom);

  // Centre the current view's projected box in the area.
  final now = bounds(rotationX, rotationY);
  final center = area.center - now.center * scale;
  return Projector(rotationX: rotationX, rotationY: rotationY, zoom: scale * 20, center: center, cameraDistance: camera);
}
