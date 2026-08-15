import 'package:flutter/material.dart';
import 'package:surface_3d_chart/surface_3d_chart.dart';

// The simplest possible use of Surface3DChart: hardcoded data, no
// networking, no state management beyond what the widget handles itself.
//
// Run this file specifically:
//   flutter run -t lib/simple_3d_demo.dart

void main() => runApp(const SimpleSurfaceDemoApp());

class SimpleSurfaceDemoApp extends StatelessWidget {
  const SimpleSurfaceDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SimpleSurfaceDemoScreen(),
    );
  }
}

class SimpleSurfaceDemoScreen extends StatelessWidget {
  const SimpleSurfaceDemoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // A 4x4 grid: data[row][col]. Rows are months, columns are regions.
    // Just made-up sales numbers.
    const data = [
      [12.0, 18.0, 9.0, 22.0],
      [15.0, 20.0, 11.0, 25.0],
      [19.0, 24.0, 14.0, 30.0],
      [23.0, 29.0, 17.0, 35.0],
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Simple 3D Surface Example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Surface3DChart(
          data: data,
          xLabels: const ['North', 'South', 'East', 'West'],
          yLabels: const ['Jan', 'Feb', 'Mar', 'Apr'],
          xAxisTitle: 'Region',
          yAxisTitle: 'Month',
          zAxisTitle: 'Sales',
          valueFormatter: (v) => '\$${v.toStringAsFixed(0)}k',
          gradient: const [Colors.teal, Colors.amber, Colors.deepOrange],
          showLegend: true,
        ),
      ),
    );
  }
}
