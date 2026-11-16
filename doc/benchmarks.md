# Benchmarks

Measured with `flutter test tool/benchmark_test.dart` on macos (Dart 3.13.5, debug/JIT, no GPU rasterisation).
Each figure is the median of 7 runs of build + layout + paint recording for a 1000×500 chart.
Release builds are several times faster; compare rows, not absolute numbers.

| Scenario | Size | Median time |
|---|---|---|
| Line chart: first paint / data update | 1k points | 5.3 ms |
| Line chart: hover (tooltip + crosshair) | 1k points | 1.0 ms |
| Line chart: first paint / data update | 10k points | 6.0 ms |
| Line chart: hover (tooltip + crosshair) | 10k points | 0.9 ms |
| Line chart: first paint / data update | 100k points | 29.3 ms |
| Line chart: hover (tooltip + crosshair) | 100k points | 2.8 ms |
| Line chart: first paint / data update | 1M points | 244.5 ms |
| Line chart: hover (tooltip + crosshair) | 1M points | 16.5 ms |
| Scatter chart: first paint | 50k points | 9.3 ms |
| Candlestick: data update (indicators recomputed) | 5k candles, 4 indicators | 4.2 ms |
| Candlestick: pan (drag gesture + repaint) | 5k candles, 300 visible | 5.1 ms |
| LTTB downsampling (used by line charts) | 1M → 2,000 points | 15.5 ms |
