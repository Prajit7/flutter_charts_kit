import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_charts_kit/flutter_charts_kit.dart';

/// Fifth tab of the demo: network graph, chord diagram, parallel
/// coordinates and a world choropleth map.
class AdvancedChartsPage extends StatelessWidget {
  const AdvancedChartsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final padding = width < 600 ? 8.0 : (width < 1024 ? 16.0 : 24.0);
    Widget card(Widget child, {double height = 380}) => Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: SizedBox(height: height, child: child),
        );
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: 16),
      children: [
        card(const WorldMapDemo(), height: 420),
        card(networkDemo(), height: 420),
        card(chordDemo(), height: 420),
        card(parallelDemo()),
      ],
    );
  }
}

/// Population by country, from Natural Earth's public-domain 1:110m
/// boundaries bundled as an example asset.
class WorldMapDemo extends StatefulWidget {
  const WorldMapDemo({super.key});

  @override
  State<WorldMapDemo> createState() => _WorldMapDemoState();
}

class _WorldMapDemoState extends State<WorldMapDemo> {
  late final Future<(List<GeoFeature>, Map<String, double>)> _data = () async {
    // Antarctica has no population and would dominate a Mercator view.
    final features = GeoFeature.parse(await rootBundle.loadString('assets/world_110m.geojson'))
        .where((f) => f.id != 'Antarctica')
        .toList();
    final population = {
      for (final f in features)
        if (f.properties['pop'] is num) f.id: (f.properties['pop'] as num) / 1e6,
    };
    return (features, population);
  }();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _data,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) return const Center(child: CircularProgressIndicator());
        return ChoroplethMap2D(
          title: 'World population',
          subtitle: 'Your own GeoJSON · log color scale · drag, pinch or scroll to zoom',
          features: data.$1,
          values: data.$2,
          logScale: true,
          valueFormatter: formatPopulation,
        );
      },
    );
  }
}

/// Millions → "1.43B", "67M", "2.1M", "340k".
String formatPopulation(double millions) {
  if (millions >= 1000) return '${(millions / 1000).toStringAsFixed(2)}B';
  if (millions >= 10) return '${millions.round()}M';
  if (millions >= 1) return '${millions.toStringAsFixed(1)}M';
  final k = (millions * 1000).round();
  return k < 1 ? '<1k' : '${k}k';
}

Widget networkDemo({bool animate = true}) {
  const services = {
    'gateway': 'edge',
    'cdn': 'edge',
    'auth': 'core',
    'users': 'core',
    'orders': 'core',
    'payments': 'core',
    'catalog': 'core',
    'search': 'data',
    'postgres': 'data',
    'redis': 'data',
    'kafka': 'data',
    'email': 'workers',
    'billing': 'workers',
    'analytics': 'workers',
    'web': 'clients',
    'ios': 'clients',
    'android': 'clients',
  };
  const links = [
    ('web', 'cdn'), ('web', 'gateway'), ('ios', 'gateway'), ('android', 'gateway'),
    ('gateway', 'auth'), ('gateway', 'users'), ('gateway', 'orders'), ('gateway', 'catalog'), ('gateway', 'search'),
    ('auth', 'users'), ('auth', 'redis'), ('users', 'postgres'), ('orders', 'postgres'), ('orders', 'payments'),
    ('orders', 'kafka'), ('catalog', 'postgres'), ('catalog', 'search'), ('search', 'redis'), ('payments', 'kafka'),
    ('kafka', 'email'), ('kafka', 'billing'), ('kafka', 'analytics'), ('billing', 'postgres'), ('analytics', 'postgres'),
  ];
  return NetworkGraph2D(
    title: 'Service map',
    subtitle: 'Drag a node · hover to see its neighbours',
    directed: true,
    enableAnimation: animate,
    nodes: [for (final e in services.entries) GraphNode(id: e.key, group: e.value)],
    edges: [for (final (a, b) in links) GraphEdge(a, b)],
  );
}

Widget chordDemo({bool animate = true}) => ChordChart2D(
      enableAnimation: animate,
      title: 'Customer switching',
      subtitle: 'Users moving between plans last quarter (thousands)',
      labels: const ['Free', 'Starter', 'Pro', 'Team', 'Enterprise'],
      matrix: const [
        [0, 42, 12, 4, 0],
        [9, 0, 28, 11, 1],
        [3, 6, 0, 17, 5],
        [1, 2, 5, 0, 9],
        [0, 0, 1, 2, 0],
      ],
    );

Widget parallelDemo() {
  const cars = [
    ('Civic', 'Compact', [24.0, 36, 158, 1.3]),
    ('Corolla', 'Compact', [22.0, 35, 169, 1.36]),
    ('Golf', 'Compact', [26.0, 33, 147, 1.33]),
    ('Mazda3', 'Compact', [25.0, 31, 191, 1.41]),
    ('Camry', 'Sedan', [28.0, 32, 203, 1.56]),
    ('Accord', 'Sedan', [30.0, 32, 192, 1.48]),
    ('Model 3', 'Sedan', [42.0, 132, 283, 1.76]),
    ('A4', 'Sedan', [44.0, 28, 201, 1.62]),
    ('RAV4', 'SUV', [30.0, 30, 203, 1.6]),
    ('CR-V', 'SUV', [32.0, 30, 190, 1.6]),
    ('Model Y', 'SUV', [48.0, 122, 384, 1.98]),
    ('X5', 'SUV', [66.0, 23, 375, 2.26]),
    ('Tahoe', 'SUV', [58.0, 17, 355, 2.6]),
    ('F-150', 'Truck', [38.0, 20, 290, 2.1]),
    ('Ranger', 'Truck', [34.0, 23, 270, 1.94]),
    ('Tacoma', 'Truck', [36.0, 21, 278, 1.98]),
  ];
  return ParallelCoordinatesChart2D(
    title: 'Cars compared',
    subtitle: 'Drag along an axis to filter · tap the axis to clear',
    smooth: true,
    axes: [
      ParallelAxis('Price', formatter: (v) => '\$${v.round()}k'),
      const ParallelAxis('MPG(e)'),
      const ParallelAxis('Horsepower'),
      ParallelAxis('Weight', inverted: true, formatter: (v) => '${v.toStringAsFixed(1)}t'),
    ],
    records: [for (final (name, type, v) in cars) ParallelRecord([for (final x in v) x.toDouble()], label: name, group: type)],
  );
}
