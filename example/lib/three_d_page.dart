import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_charts_kit/flutter_charts_kit.dart';

enum _View { surface, wireframe, bars, scatter }

/// The 3D tab: switch between a surface (solid or wireframe with contours),
/// 3D bars, and a 3D scatter plot. Drag to rotate, pinch/scroll to zoom.
class Surface3DPage extends StatefulWidget {
  const Surface3DPage({super.key});

  @override
  State<Surface3DPage> createState() => _Surface3DPageState();
}

class _Surface3DPageState extends State<Surface3DPage> {
  _View _view = _View.surface;

  static const _regions = ['North', 'South', 'East', 'West'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr'];
  static const _sales = [
    [12.0, 18.0, 9.0, 22.0],
    [15.0, 20.0, 11.0, 25.0],
    [19.0, 24.0, 14.0, 30.0],
    [23.0, 29.0, 17.0, 35.0],
  ];

  /// A smooth 16×16 terrain for the wireframe/contour view.
  static final _terrain = [
    for (int r = 0; r < 16; r++)
      [for (int c = 0; c < 16; c++) 50 + 35 * math.sin(r / 2.5) * math.cos(c / 3.0) + 10 * math.cos((r + c) / 4)],
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final padding = width < 600 ? 8.0 : (width < 1024 ? 16.0 : 24.0);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<_View>(
                segments: const [
                  ButtonSegment(value: _View.surface, label: Text('Surface'), icon: Icon(Icons.terrain)),
                  ButtonSegment(value: _View.wireframe, label: Text('Wireframe'), icon: Icon(Icons.grid_on)),
                  ButtonSegment(value: _View.bars, label: Text('Bars'), icon: Icon(Icons.view_in_ar)),
                  ButtonSegment(value: _View.scatter, label: Text('Scatter'), icon: Icon(Icons.bubble_chart)),
                ],
                selected: {_view},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _view = s.first),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(child: _chart()),
          ],
        ),
      ),
    );
  }

  Widget _chart() {
    switch (_view) {
      case _View.surface:
        return Surface3DChart(
          key: const ValueKey('surface'),
          data: _sales,
          xLabels: _regions,
          yLabels: _months,
          xAxisTitle: 'Region',
          yAxisTitle: 'Month',
          zAxisTitle: 'Sales',
          valueFormatter: (v) => '\$${v.toStringAsFixed(0)}k',
          gradient: const [Colors.teal, Colors.amber, Colors.deepOrange],
          showLegend: true,
        );
      case _View.wireframe:
        return Surface3DChart(
          key: const ValueKey('wireframe'),
          data: _terrain,
          xLabels: [for (int c = 0; c < 16; c++) '${c * 10}m'],
          yLabels: [for (int r = 0; r < 16; r++) '${r * 10}m'],
          xAxisTitle: 'East',
          yAxisTitle: 'North',
          zAxisTitle: 'Elevation',
          valueFormatter: (v) => v.toStringAsFixed(0),
          gradient: const [Color(0xFF1E88E5), Color(0xFF43A047), Color(0xFFFDD835), Color(0xFFE53935)],
          renderMode: SurfaceRenderMode.wireframe,
          showContours: true,
          contourLevels: 10,
        );
      case _View.bars:
        return Bar3DChart(
          key: const ValueKey('bars'),
          data: _sales,
          xLabels: _regions,
          yLabels: _months,
          xAxisTitle: 'Region',
          yAxisTitle: 'Month',
          zAxisTitle: 'Sales',
          valueFormatter: (v) => '\$${v.toStringAsFixed(0)}k',
          gradient: const [Colors.teal, Colors.amber, Colors.deepOrange],
          showLegend: true,
        );
      case _View.scatter:
        final rnd = math.Random(5);
        Scatter3DSeries cluster(String name, Color color, double cx, double cy, double cz) => Scatter3DSeries(
              name: name,
              color: color,
              points: [
                for (int i = 0; i < 25; i++)
                  Scatter3DPoint(
                    x: cx + (rnd.nextDouble() - 0.5) * 30,
                    y: cy + (rnd.nextDouble() - 0.5) * 30,
                    z: cz + (rnd.nextDouble() - 0.5) * 30,
                    label: '$name #${i + 1}',
                  ),
              ],
            );
        return Scatter3DChart(
          key: const ValueKey('scatter'),
          xAxisTitle: 'Age',
          yAxisTitle: 'Income (k)',
          zAxisTitle: 'Spend (k)',
          showDropLines: true,
          series: [
            cluster('Students', Colors.blue, 22, 20, 15),
            cluster('Professionals', Colors.orange, 38, 85, 45),
            cluster('Retirees', Colors.green, 68, 45, 30),
          ],
        );
    }
  }
}
