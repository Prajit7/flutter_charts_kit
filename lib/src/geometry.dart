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

  const Projector({
    required this.rotationX,
    required this.rotationY,
    required this.zoom,
    required this.center,
  });

  /// Rotated point, pre-perspective. Useful for depth sorting.
  Point3D rotate(Point3D p) {
    double x = p.x, y = p.y, z = p.z;

    final y1 = y * math.cos(rotationX) - z * math.sin(rotationX);
    final z1 = y * math.sin(rotationX) + z * math.cos(rotationX);
    y = y1;
    z = z1;

    final x1 = x * math.cos(rotationY) + z * math.sin(rotationY);
    final z2 = -x * math.sin(rotationY) + z * math.cos(rotationY);
    x = x1;
    z = z2;

    return Point3D(x, y, z);
  }

  Offset project(Point3D p) {
    final r = rotate(p);
    const camera = 700.0;
    final perspective = camera / (camera - r.z);
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
