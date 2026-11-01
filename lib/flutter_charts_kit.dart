/// A generic, interactive 3D surface chart for Flutter.
library flutter_charts_kit;

export 'src/surface_3d_chart_widget.dart'
    show Surface3DChart, Surface3DChartState, Surface3DHit, Surface3DViewState;
export 'src/chart_controller.dart' show Surface3DChartController;
export 'src/geometry.dart' show Point3D, Projector, SurfaceQuad, SurfaceGeometry, fitProjector;
export 'src/painter.dart' show Surface3DPainter, SurfaceRenderMode;
export 'src/legend.dart' show Surface3DLegend;
export 'src/bar3d_chart.dart' show Bar3DChart;
export 'src/scatter3d_chart.dart' show Scatter3DChart, Scatter3DSeries, Scatter3DPoint, Scatter3DHit;

// 2D charts
export 'src/chart2d/models.dart'
    show
        ChartPoint,
        XySeries,
        CategorySeries,
        PieSlice,
        LegendEntry,
        ChartAxisType,
        ChartUpdateAnimation,
        ChartPointCallback,
        ChartBarCallback,
        ChartSliceCallback,
        ChartPointTooltipBuilder,
        ChartBarTooltipBuilder,
        ChartSliceTooltipBuilder;
export 'src/chart2d/legend.dart' show Chart2DLegend;
export 'src/chart2d/theme.dart' show ChartTheme, ChartThemeScope;
export 'src/chart2d/chart_chrome.dart' show ChartHeader, ChartEmptyState;
export 'src/chart2d/zoom.dart' show ChartZoomMode, ChartZoomWindow;
export 'src/chart2d/common.dart' show ChartLegendPosition;
export 'src/chart2d/controller.dart' show ChartController;
export 'src/chart2d/reference.dart' show ChartReferenceLine, ChartReferenceBand, ChartReferenceAxis;
export 'src/chart2d/curves.dart' show LineChartCurve;
export 'src/chart2d/line_chart.dart' show LineChart2D;
export 'src/chart2d/bar_chart.dart' show BarChart2D;
export 'src/chart2d/pie_chart.dart' show PieChart2D;
export 'src/chart2d/scatter_chart.dart' show ScatterChart2D;
export 'src/chart2d/combo_chart.dart' show ComboChart2D, ComboSeries, ComboSeriesType, ComboTooltipBuilder;
export 'src/chart2d/heatmap_chart.dart' show HeatmapChart2D, HeatmapCell;
export 'src/chart2d/sparkline.dart' show Sparkline, SparklineType;
export 'src/chart2d/gauge_chart.dart' show GaugeChart, GaugeRange, GaugeStyle;
export 'src/chart2d/radar_chart.dart' show RadarChart2D, RadarHit;
export 'src/chart2d/candlestick_chart.dart' show CandlestickChart2D, Candle, CandleStyle;
export 'src/chart2d/indicators.dart'
    show
        CandleIndicator,
        MovingAverageIndicator,
        MovingAverageType,
        BollingerBandsIndicator,
        VwapIndicator,
        RsiIndicator,
        MacdIndicator,
        IndicatorResult,
        IndicatorLine,
        IndicatorHistogram;
export 'src/chart2d/live_candles.dart' show LiveCandles;
export 'src/chart2d/distribution_charts.dart' show Histogram2D, HistogramBin, BoxPlot2D, BoxPlotGroup, BoxPlotStats;
export 'src/chart2d/funnel_chart.dart' show FunnelChart2D, FunnelStage;
export 'src/chart2d/treemap_chart.dart' show TreemapChart2D, TreemapNode, TreemapTile;
export 'src/chart2d/sankey_chart.dart' show SankeyChart2D, SankeyLink, SankeyNode, SankeyHit;
