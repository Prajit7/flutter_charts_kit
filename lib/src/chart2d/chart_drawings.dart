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

  /// Two parallel lines: the first two points set the base line, the third
  /// sets the other line's offset.
  parallelChannel,

  /// A price/time ruler: change, percentage and bar count between two points.
  measure,

  /// A text note pinned at one point.
  text,
}

/// How many points a [DrawingTool] takes.
extension DrawingToolPoints on DrawingTool {
  int get pointCount => switch (this) {
        DrawingTool.horizontalLine || DrawingTool.text => 1,
        DrawingTool.parallelChannel => 3,
        _ => 2,
      };

  /// Whether the drawing has a price-vs-time line that alerts can watch.
  bool get supportsAlerts => this == DrawingTool.horizontalLine || this == DrawingTool.trendLine || this == DrawingTool.ray;
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

  /// Text of a [DrawingTool.text] note (and an optional label on others).
  final String? text;

  /// Watch this line for price crossings — see
  /// [CandlestickChart2D.onAlert]. Horizontal lines, trend lines and rays.
  final bool alert;

  /// Fibonacci levels (0 = second point, 1 = first point).
  static const fibonacciLevels = [0.0, 0.236, 0.382, 0.5, 0.618, 0.786, 1.0];

  const ChartDrawing({
    required this.id,
    required this.tool,
    required this.points,
    required this.color,
    this.text,
    this.alert = false,
  });

  ChartDrawing copyWith({List<DrawingPoint>? points, Color? color, String? text, bool? alert}) => ChartDrawing(
        id: id,
        tool: tool,
        points: points ?? this.points,
        color: color ?? this.color,
        text: text ?? this.text,
        alert: alert ?? this.alert,
      );

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
        if (text != null) 'text': text!,
        if (alert) 'alert': true,
      };

  factory ChartDrawing.fromJson(Map<String, dynamic> json) => ChartDrawing(
        id: json['id'] as String,
        tool: DrawingTool.values.byName(json['tool'] as String),
        color: Color((json['color'] as num).toInt()),
        points: [for (final p in json['points'] as List) DrawingPoint.fromJson((p as Map).cast<String, dynamic>())],
        text: json['text'] as String?,
        alert: json['alert'] == true,
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
/// drawings.setAlert(drawings.selectedId!, true); // fire onAlert when price crosses it
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

  /// Snap points to the nearest open/high/low/close of the candle under
  /// the pointer (when within a few pixels).
  bool magnet;

  /// Text for the next [DrawingTool.text] note.
  String noteText;

  ChartDrawingController({
    List<ChartDrawing> drawings = const [],
    this.color = const Color(0xFF2962FF),
    this.keepToolActive = false,
    this.magnet = false,
    this.noteText = 'Note',
  }) : _drawings = [...drawings];

  /// Turns price alerts on or off for drawing [id].
  void setAlert(String id, bool enabled) {
    final d = _drawings.where((d) => d.id == id).firstOrNull;
    if (d != null) update(d.copyWith(alert: enabled));
  }

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

/// A price crossing of an alert drawing, reported by
/// [CandlestickChart2D.onAlert].
@immutable
class DrawingAlert {
  final ChartDrawing drawing;

  /// The line's price at the crossing.
  final double level;
  final double previousPrice;
  final double price;
  final DateTime time;

  const DrawingAlert({
    required this.drawing,
    required this.level,
    required this.previousPrice,
    required this.price,
    required this.time,
  });

  /// Whether price crossed from below to above.
  bool get crossedUp => price > previousPrice;
}
