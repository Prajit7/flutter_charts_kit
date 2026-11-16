import 'dart:ui' show Color;
import 'package:flutter/foundation.dart';

/// A drawing tool for [CandlestickChart2D].
enum DrawingTool {
  /// A line between two points.
  trendLine,

  /// A line from the first point through the second, extended to the edge.
  ray,

  /// A horizontal price level across the chart (one point).
  horizontalLine,

  /// Fibonacci retracement levels between two prices.
  fibonacci,

  /// A shaded box between two corners (a range or zone).
  rectangle,
}

/// A point of a drawing: a time (it may fall between candles or beyond
/// the last one) and a price.
@immutable
class DrawingPoint {
  final DateTime time;
  final double price;

  const DrawingPoint(this.time, this.price);

  Map<String, Object> toJson() => {'t': time.millisecondsSinceEpoch, 'p': price};

  factory DrawingPoint.fromJson(Map<String, dynamic> json) =>
      DrawingPoint(DateTime.fromMillisecondsSinceEpoch((json['t'] as num).toInt()), (json['p'] as num).toDouble());

  @override
  bool operator ==(Object other) => other is DrawingPoint && other.time == time && other.price == price;

  @override
  int get hashCode => Object.hash(time, price);
}

/// A user drawing on a candlestick chart.
@immutable
class ChartDrawing {
  final String id;
  final DrawingTool tool;

  /// One point for [DrawingTool.horizontalLine], two for the others.
  final List<DrawingPoint> points;
  final Color color;

  /// Fibonacci levels (0 = second point, 1 = first point).
  static const fibonacciLevels = [0.0, 0.236, 0.382, 0.5, 0.618, 0.786, 1.0];

  const ChartDrawing({required this.id, required this.tool, required this.points, required this.color});

  ChartDrawing copyWith({List<DrawingPoint>? points, Color? color}) =>
      ChartDrawing(id: id, tool: tool, points: points ?? this.points, color: color ?? this.color);

  /// Price at Fibonacci [level].
  double fibonacciPrice(double level) {
    final a = points.first.price, b = points.length > 1 ? points[1].price : a;
    return b + (a - b) * level;
  }

  Map<String, Object> toJson() => {
        'id': id,
        'tool': tool.name,
        'color': color.toARGB32(),
        'points': [for (final p in points) p.toJson()],
      };

  factory ChartDrawing.fromJson(Map<String, dynamic> json) => ChartDrawing(
        id: json['id'] as String,
        tool: DrawingTool.values.byName(json['tool'] as String),
        color: Color((json['color'] as num).toInt()),
        points: [for (final p in json['points'] as List) DrawingPoint.fromJson((p as Map).cast<String, dynamic>())],
      );
}

/// Holds a candlestick chart's drawings and the active drawing tool.
///
/// ```dart
/// final drawings = ChartDrawingController();
///
/// CandlestickChart2D(candles: candles, drawingController: drawings)
///
/// // From a toolbar:
/// drawings.startDrawing(DrawingTool.trendLine);  // then drag (or click twice) on the chart
/// drawings.removeSelected();                      // or press Delete / Backspace
/// final saved = jsonEncode(drawings.toJson());    // persist…
/// drawings.loadJson(jsonDecode(saved));           // …and restore
/// ```
///
/// On the chart: with a tool active, drag from the first point to the
/// second (or click/tap once for each point; one click for a horizontal
/// line). With no tool active, tap a drawing to select it, drag its
/// handles to reshape it, or drag its body to move it. Escape cancels.
class ChartDrawingController extends ChangeNotifier {
  final List<ChartDrawing> _drawings;
  DrawingTool? _tool;
  String? _selectedId;
  int _nextId = 1;

  /// Color for new drawings.
  Color color;

  /// Keep the tool active after finishing a drawing (to draw several).
  bool keepToolActive;

  ChartDrawingController({
    List<ChartDrawing> drawings = const [],
    this.color = const Color(0xFF2962FF),
    this.keepToolActive = false,
  }) : _drawings = [...drawings];

  List<ChartDrawing> get drawings => List.unmodifiable(_drawings);
  DrawingTool? get activeTool => _tool;
  String? get selectedId => _selectedId;
  ChartDrawing? get selected => _drawings.where((d) => d.id == _selectedId).firstOrNull;

  /// Arms [tool]: the next drag or clicks on the chart draw it.
  void startDrawing(DrawingTool tool) {
    _tool = tool;
    _selectedId = null;
    notifyListeners();
  }

  /// Disarms the active tool (an unfinished drawing is discarded).
  void cancelDrawing() {
    if (_tool == null) return;
    _tool = null;
    notifyListeners();
  }

  /// A new id for a drawing.
  String newId() {
    var id = 'd${_nextId++}';
    while (_drawings.any((d) => d.id == id)) {
      id = 'd${_nextId++}';
    }
    return id;
  }

  void add(ChartDrawing drawing) {
    _drawings.add(drawing);
    notifyListeners();
  }

  /// Adds a drawing the user just finished, selects it, and disarms the
  /// tool unless [keepToolActive].
  void finish(ChartDrawing drawing) {
    _drawings.add(drawing);
    _selectedId = drawing.id;
    if (!keepToolActive) _tool = null;
    notifyListeners();
  }

  /// Replaces the drawing with the same id.
  void update(ChartDrawing drawing) {
    final i = _drawings.indexWhere((d) => d.id == drawing.id);
    if (i < 0) return;
    _drawings[i] = drawing;
    notifyListeners();
  }

  void remove(String id) {
    _drawings.removeWhere((d) => d.id == id);
    if (_selectedId == id) _selectedId = null;
    notifyListeners();
  }

  /// Deletes the selected drawing; returns whether there was one.
  bool removeSelected() {
    final id = _selectedId;
    if (id == null) return false;
    remove(id);
    return true;
  }

  void clear() {
    _drawings.clear();
    _selectedId = null;
    notifyListeners();
  }

  void select(String? id) {
    if (_selectedId == id) return;
    _selectedId = id;
    notifyListeners();
  }

  /// The drawings as JSON-ready maps.
  List<Map<String, Object>> toJson() => [for (final d in _drawings) d.toJson()];

  /// Replaces all drawings with ones saved by [toJson].
  void loadJson(List<dynamic> json) {
    _drawings
      ..clear()
      ..addAll([for (final d in json) ChartDrawing.fromJson((d as Map).cast<String, dynamic>())]);
    _selectedId = null;
    notifyListeners();
  }
}
