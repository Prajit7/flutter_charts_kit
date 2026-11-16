import 'package:flutter/material.dart';
import 'theme.dart';
import 'cartesian_axes.dart';
import 'models.dart';
import 'time_axis.dart';

/// A chart's numbers as a plain, scrollable table — an accessible
/// alternative to the picture, and handy for checking values.
///
/// Build one from your data with the named constructors, or pair it with a
/// chart using [ChartWithTable].
///
/// ```dart
/// ChartDataTable.fromCategorySeries(categories: months, series: revenue)
/// ```
class ChartDataTable extends StatelessWidget {
  final List<String> columns;
  final List<List<String>> rows;

  /// Columns aligned right (numbers); defaults to every column but the first.
  final Set<int>? numericColumns;
  final String? caption;

  const ChartDataTable({super.key, required this.columns, required this.rows, this.numericColumns, this.caption});

  /// One row per category, one column per series.
  factory ChartDataTable.fromCategorySeries({
    Key? key,
    required List<String> categories,
    required List<CategorySeries> series,
    String categoryLabel = 'Category',
    String Function(double value) valueFormatter = Cartesian2DAxes.formatNumber,
    String? caption,
  }) =>
      ChartDataTable(
        key: key,
        caption: caption,
        columns: [categoryLabel, for (final s in series) s.name],
        rows: [
          for (int c = 0; c < categories.length; c++)
            [
              categories[c],
              for (final s in series) c < s.values.length && s.values[c].isFinite ? valueFormatter(s.values[c]) : '–',
            ],
        ],
      );

  /// One row per distinct x across the series, one column per series.
  factory ChartDataTable.fromXySeries({
    Key? key,
    required List<XySeries> series,
    String xLabel = 'x',
    bool timeAxis = false,
    String Function(double x)? xFormatter,
    String Function(double value) valueFormatter = Cartesian2DAxes.formatNumber,
    String? caption,
  }) {
    final xs = <double>{for (final s in series) for (final p in s.data) p.x}.toList()..sort();
    final fx = xFormatter ?? (timeAxis ? (double x) => formatTime(DateTime.fromMillisecondsSinceEpoch(x.round())) : Cartesian2DAxes.formatNumber);
    final lookup = [for (final s in series) {for (final p in s.data) p.x: p.y}];
    return ChartDataTable(
      key: key,
      caption: caption,
      columns: [xLabel, for (final s in series) s.name],
      rows: [
        for (final x in xs)
          [
            fx(x),
            for (final m in lookup) m[x] == null ? '–' : valueFormatter(m[x]!),
          ],
      ],
    );
  }

  /// Label, value and share for pie/donut/funnel-style data.
  factory ChartDataTable.fromSlices({
    Key? key,
    required List<PieSlice> slices,
    String labelHeader = 'Label',
    String valueHeader = 'Value',
    String Function(double value) valueFormatter = Cartesian2DAxes.formatNumber,
    String? caption,
  }) {
    final total = slices.fold(0.0, (s, x) => s + x.value);
    return ChartDataTable(
      key: key,
      caption: caption,
      columns: [labelHeader, valueHeader, 'Share'],
      rows: [
        for (final s in slices)
          [s.label, valueFormatter(s.value), total == 0 ? '–' : '${(s.value / total * 100).toStringAsFixed(1)}%'],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    final numeric = numericColumns ?? {for (int i = 1; i < columns.length; i++) i};
    final head = TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: theme.axisColor, fontFamily: theme.fontFamily);
    final cell = TextStyle(fontSize: 12, color: theme.axisColor, fontFamily: theme.fontFamily, fontFeatures: const [FontFeature.tabularFigures()]);
    Widget text(String s, int col, TextStyle style) => Align(
          alignment: numeric.contains(col) ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(s, style: style),
        );
    return Semantics(
      label: caption,
      child: Scrollbar(
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 36,
              dataRowMinHeight: 30,
              dataRowMaxHeight: 34,
              columnSpacing: 24,
              horizontalMargin: 8,
              dividerThickness: 0.6,
              columns: [
                for (int i = 0; i < columns.length; i++) DataColumn(numeric: numeric.contains(i), label: text(columns[i], i, head)),
              ],
              rows: [
                for (final r in rows)
                  DataRow(cells: [
                    for (int i = 0; i < columns.length; i++) DataCell(text(i < r.length ? r[i] : '', i, cell)),
                  ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A chart with a small toggle to switch to its data as a table.
///
/// ```dart
/// ChartWithTable(
///   chart: BarChart2D(categories: months, series: revenue),
///   table: ChartDataTable.fromCategorySeries(categories: months, series: revenue),
/// )
/// ```
class ChartWithTable extends StatefulWidget {
  final Widget chart;
  final Widget table;
  final bool initiallyShowTable;

  const ChartWithTable({super.key, required this.chart, required this.table, this.initiallyShowTable = false});

  @override
  State<ChartWithTable> createState() => _ChartWithTableState();
}

class _ChartWithTableState extends State<ChartWithTable> {
  late bool _table = widget.initiallyShowTable;

  @override
  Widget build(BuildContext context) {
    final theme = ChartThemeScope.of(context);
    return Stack(children: [
      Positioned.fill(child: _table ? Padding(padding: const EdgeInsets.only(top: 36), child: widget.table) : widget.chart),
      Positioned(
        top: 0,
        right: 0,
        child: Tooltip(
          message: _table ? 'Show chart' : 'Show data table',
          child: IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            color: theme.subtitleColor,
            icon: Icon(_table ? Icons.insert_chart_outlined : Icons.table_rows_outlined),
            onPressed: () => setState(() => _table = !_table),
          ),
        ),
      ),
    ]);
  }
}
