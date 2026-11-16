import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_charts_kit/flutter_charts_kit.dart';

import 'code_card.dart';

/// Sixth tab of the demo: option payoff, open interest, market depth,
/// volatility smile, and the candlestick chart's candle types, volume
/// profile and drawing tools.
class OptionsChartsPage extends StatelessWidget {
  const OptionsChartsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final padding = width < 600 ? 8.0 : (width < 1024 ? 16.0 : 24.0);
    Widget card(Widget child, String code, {double height = 380}) => CodeCard(code: snippets[code]!, height: height, child: child);
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: 16),
      children: [
        card(const PayoffDemo(), 'payoff', height: 420),
        card(oiDemo(), 'oi'),
        card(const LiveDepthDemo(), 'depth'),
        card(smileDemo(), 'smile'),
        card(greeksDemo(), 'greeks', height: 440),
        card(oiTrendDemo(), 'oiTrend', height: 420),
        // The toolbars wrap onto several rows on phones.
        card(const TradingToolsDemo(), 'trading', height: width < 600 ? 980 : 640),
      ],
    );
  }
}

const _spot = 24480.0;
const _lot = 75.0;

String _inr(double v) {
  final s = v.abs().round().toString();
  // Indian digit grouping: 12,34,567.
  final last3 = s.length <= 3 ? s : s.substring(s.length - 3);
  var rest = s.length <= 3 ? '' : s.substring(0, s.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) groups.insert(0, rest);
  final body = [...groups, last3].join(',');
  return '${v < 0 ? '-' : ''}$body';
}

String _pnl(double v) => v > 0.5 ? '+₹${_inr(v)}' : (v < -0.5 ? '-₹${_inr(-v)}' : '₹0');

/// Strategy picker over the payoff chart.
class PayoffDemo extends StatefulWidget {
  final bool animate;
  final int initial;
  const PayoffDemo({super.key, this.animate = true, this.initial = 0});

  @override
  State<PayoffDemo> createState() => _PayoffDemoState();
}

class _PayoffDemoState extends State<PayoffDemo> {
  late int _pick = widget.initial;

  /// Premiums from Black-Scholes at 13% IV, 6 days out — realistic and
  /// consistent with the chart's "today" curve.
  static OptionLeg _leg(OptionType type, double strike, double qty) {
    final premium = OptionMath.blackScholes(type: type, spot: _spot, strike: strike, years: 6 / 365, volatility: 0.13);
    final p = double.parse(premium.toStringAsFixed(1));
    return type == OptionType.call
        ? OptionLeg.call(strike: strike, premium: p, quantity: qty, lotSize: _lot)
        : OptionLeg.put(strike: strike, premium: p, quantity: qty, lotSize: _lot);
  }

  static final strategies = <String, List<OptionLeg>>{
    'Iron condor': [
      _leg(OptionType.put, 24200, 1),
      _leg(OptionType.put, 24300, -1),
      _leg(OptionType.call, 24700, -1),
      _leg(OptionType.call, 24800, 1),
    ],
    'Short straddle': [_leg(OptionType.call, 24500, -1), _leg(OptionType.put, 24500, -1)],
    'Bull call spread': [_leg(OptionType.call, 24400, 1), _leg(OptionType.call, 24700, -1)],
    'Long strangle': [_leg(OptionType.call, 24700, 1), _leg(OptionType.put, 24300, 1)],
  };

  @override
  Widget build(BuildContext context) {
    final names = strategies.keys.toList();
    return Column(children: [
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (int i = 0; i < names.length; i++)
          ChoiceChip(
            label: Text(names[i]),
            selected: _pick == i,
            onSelected: (_) => setState(() => _pick = i),
          ),
      ]),
      const SizedBox(height: 8),
      Expanded(
        child: OptionPayoffChart2D(
          title: 'NIFTY ${names[_pick].toLowerCase()} · 6 days to expiry',
          subtitle: 'Expiry payoff (fill), today at 13% IV (thin line), ±1σ expected move',
          legs: strategies[names[_pick]]!,
          spot: _spot,
          daysToExpiry: 6,
          volatility: 0.13,
          enableAnimation: widget.animate,
          pnlFormatter: _pnl,
          priceFormatter: (v) => _inr(v),
        ),
      ),
    ]);
  }
}

/// A synthetic but realistically shaped option chain: call OI piles up at
/// round strikes above spot (resistance), put OI below (support).
List<OptionStrikeData> sampleChain() {
  final rnd = math.Random(11);
  return [
    for (double k = 23500; k <= 25500; k += 50)
      () {
        final round = k % 500 == 0 ? 2.2 : (k % 100 == 0 ? 1.4 : 0.8);
        final call = (k >= _spot ? math.exp(-((k - 25000) * (k - 25000)) / (2 * 350 * 350)) : 0.18 * math.exp((k - _spot) / 300)) *
            round *
            (60 + rnd.nextDouble() * 25) *
            1e5;
        final put = (k <= _spot ? math.exp(-((k - 24000) * (k - 24000)) / (2 * 350 * 350)) : 0.18 * math.exp((_spot - k) / 300)) *
            round *
            (60 + rnd.nextDouble() * 25) *
            1e5;
        return OptionStrikeData(
          strike: k,
          callOI: call.roundToDouble(),
          putOI: put.roundToDouble(),
          callOIChange: (call * (rnd.nextDouble() * 0.5 - 0.15)).roundToDouble(),
          putOIChange: (put * (rnd.nextDouble() * 0.5 - 0.1)).roundToDouble(),
        );
      }(),
  ];
}

Widget oiDemo({OpenInterestView view = OpenInterestView.total}) => OpenInterestChart2D(
      title: 'NIFTY open interest',
      subtitle: 'Drag sideways for more strikes · hover a strike for details',
      spot: _spot,
      view: view,
      strikes: sampleChain(),
      strikeFormatter: (v) => _inr(v),
    );

/// An order book around [mid] with occasional walls.
(List<DepthLevel>, List<DepthLevel>) sampleBook(double mid, math.Random rnd) {
  const tick = 0.5;
  final bids = <DepthLevel>[], asks = <DepthLevel>[];
  for (int i = 0; i < 60; i++) {
    double size(int i) => (40 + rnd.nextDouble() * 160 + i * 6) * (rnd.nextDouble() < 0.06 ? 6 : 1);
    bids.add(DepthLevel(mid - tick * (i + 1), size(i).roundToDouble(), orders: 1 + rnd.nextInt(30)));
    asks.add(DepthLevel(mid + tick * (i + 1), size(i).roundToDouble(), orders: 1 + rnd.nextInt(30)));
  }
  return (bids, asks);
}

/// Market depth fed by a simulated book that ticks every 600 ms.
class LiveDepthDemo extends StatefulWidget {
  final bool live;
  const LiveDepthDemo({super.key, this.live = true});

  @override
  State<LiveDepthDemo> createState() => _LiveDepthDemoState();
}

class _LiveDepthDemoState extends State<LiveDepthDemo> {
  final _rnd = math.Random(5);
  double _mid = _spot + 0.25;
  late (List<DepthLevel>, List<DepthLevel>) _book = sampleBook(_mid, _rnd);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.live) {
      _timer = Timer.periodic(const Duration(milliseconds: 600), (_) {
        setState(() {
          _mid += (_rnd.nextInt(3) - 1) * 0.5;
          _book = sampleBook(_mid, _rnd);
        });
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MarketDepthChart2D(
        title: 'NIFTY FUT market depth',
        subtitle: widget.live ? 'Simulated live order book · hover for size and value' : 'Order book: bids left, asks right',
        bids: _book.$1,
        asks: _book.$2,
        enableAnimation: widget.live,
        priceFormatter: (v) => v.toStringAsFixed(1),
        sizeFormatter: (v) => OpenInterestChart2D.compactNumber(v),
      );
}

Widget smileDemo() {
  // A skewed smile, steeper for the near expiry; IVs recovered from
  // Black-Scholes prices to show OptionMath.impliedVolatility round-trips.
  double iv(double k, double days) {
    final m = math.log(k / _spot);
    // Near expiries smile harder; far ones are flatter and pricier at the money.
    final atm = 0.124 + 0.018 * math.sqrt(days / 90);
    final skew = -0.9 / math.sqrt(days / 6), curve = 60 / math.sqrt(days / 6);
    final sigma = atm + skew * m + curve * m * m;
    final type = k < _spot ? OptionType.put : OptionType.call;
    final price = OptionMath.blackScholes(type: type, spot: _spot, strike: k, years: days / 365, volatility: sigma);
    return OptionMath.impliedVolatility(price: price, type: type, spot: _spot, strike: k, years: days / 365) ?? sigma;
  }

  return VolatilitySmileChart2D(
    title: 'NIFTY volatility smile',
    subtitle: 'Implied volatility by strike — puts (left) carry more IV than calls',
    spot: _spot,
    strikeFormatter: (v) => _inr(v),
    smiles: [
      for (final (label, days, color) in [
        ('Weekly (6d)', 6.0, const Color(0xFF3949AB)),
        ('Monthly (27d)', 27.0, const Color(0xFF00897B)),
        ('Quarterly (90d)', 90.0, const Color(0xFFF4511E)),
      ])
        VolatilitySmile(
          label: label,
          color: color,
          points: {for (double k = 23500; k <= 25500; k += 100) k: iv(k, days)},
        ),
    ],
  );
}

/// A random-walk daily series with volume.
List<Candle> sampleCandles({int count = 140, int seed = 21, double start = 23200}) {
  final rnd = math.Random(seed);
  final out = <Candle>[];
  var price = start;
  var day = DateTime(2026, 3, 2);
  for (int i = 0; out.length < count; i++) {
    day = day.add(const Duration(days: 1));
    if (day.weekday > 5) continue;
    final drift = math.sin(i / 18) * 18 + 4;
    final open = price;
    final close = open + drift + (rnd.nextDouble() - 0.5) * 220;
    final high = math.max(open, close) + rnd.nextDouble() * 90;
    final low = math.min(open, close) - rnd.nextDouble() * 90;
    out.add(Candle(time: day, open: open, high: high, low: low, close: close, volume: (2 + rnd.nextDouble() * 4) * 1e6));
    price = close;
  }
  return out;
}

/// Candle types, indicators, volume profile, comparison, drawing tools and
/// price alerts on one candlestick chart, with simulated live ticks.
class TradingToolsDemo extends StatefulWidget {
  final bool animate;
  final bool live;
  final CandleType initialType;
  final Set<String> initialIndicators;
  final bool initialCompare;
  const TradingToolsDemo({
    super.key,
    this.animate = true,
    this.live = true,
    this.initialType = CandleType.heikinAshi,
    this.initialIndicators = const {'Supertrend'},
    this.initialCompare = false,
  });

  @override
  State<TradingToolsDemo> createState() => _TradingToolsDemoState();
}

class _TradingToolsDemoState extends State<TradingToolsDemo> {
  late List<Candle> _candles = sampleCandles();
  final _bank = sampleCandles(seed: 8, start: 51200);
  final _rnd = math.Random(4);
  Timer? _timer;
  late CandleType _type = widget.initialType;
  bool _profile = true;
  late bool _compare = widget.initialCompare;
  late final Set<String> _indicators = {...widget.initialIndicators};
  String? _lastAlert;

  static const _available = <String, CandleIndicator>{
    'Supertrend': SupertrendIndicator(),
    'Ichimoku': IchimokuIndicator(),
    'Pivots': PivotPointsIndicator(period: PivotPeriod.week),
    'Bollinger': BollingerBandsIndicator(),
    'Stochastic': StochasticIndicator(),
    'ADX': AdxIndicator(),
    'ATR': AtrIndicator(),
    'RSI': RsiIndicator(),
  };

  late final ChartDrawingController _drawings = () {
    final c = _candles;
    DrawingPoint at(int i, double price) => DrawingPoint(c[i].time, price);
    final lows = [for (final x in c) x.low];
    final highs = [for (final x in c) x.high];
    final lo = lows.sublist(20, 70).reduce(math.min), hi = highs.sublist(70, 120).reduce(math.max);
    return ChartDrawingController(drawings: [
      ChartDrawing(
        id: 'fib',
        tool: DrawingTool.fibonacci,
        color: const Color(0xFF787B86),
        points: [at(20 + lows.sublist(20, 70).indexOf(lo), lo), at(70 + highs.sublist(70, 120).indexOf(hi), hi)],
      ),
      ChartDrawing(
        id: 'trend',
        tool: DrawingTool.trendLine,
        color: const Color(0xFF2962FF),
        points: [at(8, c[8].low - 40), at(100, c[100].low - 40)],
      ),
      ChartDrawing(
        id: 'level',
        tool: DrawingTool.horizontalLine,
        color: const Color(0xFFFF9800),
        alert: true,
        points: [at(0, (c.last.close / 50).round() * 50 + 50)],
      ),
      ChartDrawing(
        id: 'note',
        tool: DrawingTool.text,
        color: const Color(0xFF8E24AA),
        text: 'Breakout',
        points: [at(86, c[86].high + 30)],
      ),
    ]);
  }();

  @override
  void initState() {
    super.initState();
    if (widget.live) {
      // Ticks move the last candle; a new candle every 15 ticks.
      var ticks = 0;
      _timer = Timer.periodic(const Duration(milliseconds: 400), (_) {
        final last = _candles.last;
        final price = last.close + (_rnd.nextDouble() - 0.48) * 28;
        setState(() {
          if (++ticks % 15 == 0) {
            final next = last.time.add(Duration(days: last.time.weekday == 5 ? 3 : 1));
            _candles = [..._candles.skip(1), Candle(time: next, open: last.close, high: price.clamp(last.close, double.infinity), low: price.clamp(0, last.close), close: price, volume: 1.5e6)];
          } else {
            _candles = [
              ..._candles.take(_candles.length - 1),
              Candle(
                time: last.time,
                open: last.open,
                high: math.max(last.high, price),
                low: math.min(last.low, price),
                close: price,
                volume: (last.volume ?? 0) + 4e4,
              ),
            ];
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _drawings.dispose();
    super.dispose();
  }

  void _onAlert(DrawingAlert a) {
    final text = 'Alert: price ${a.crossedUp ? 'crossed above' : 'fell below'} ${_inr(a.level)}';
    setState(() => _lastAlert = text);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  Future<void> _addNote() async {
    final controller = TextEditingController(text: _drawings.noteText);
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Note text'),
        content: TextField(controller: controller, autofocus: true, onSubmitted: (v) => Navigator.pop(context, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Place')),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    _drawings.noteText = text.trim();
    _drawings.startDrawing(DrawingTool.text);
  }

  @override
  Widget build(BuildContext context) {
    const tools = [
      (DrawingTool.trendLine, Icons.show_chart, 'Trend line'),
      (DrawingTool.ray, Icons.north_east, 'Ray'),
      (DrawingTool.horizontalLine, Icons.horizontal_rule, 'Horizontal level'),
      (DrawingTool.parallelChannel, Icons.view_stream_outlined, 'Parallel channel'),
      (DrawingTool.fibonacci, Icons.stacked_line_chart, 'Fibonacci retracement'),
      (DrawingTool.rectangle, Icons.crop_square, 'Rectangle'),
      (DrawingTool.measure, Icons.straighten, 'Measure'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SegmentedButton<CandleType>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: CandleType.standard, label: Text('Candles')),
            ButtonSegment(value: CandleType.heikinAshi, label: Text('Heikin-Ashi')),
            ButtonSegment(value: CandleType.renko, label: Text('Renko')),
            ButtonSegment(value: CandleType.lineBreak, label: Text('Line break')),
          ],
          selected: {_type},
          onSelectionChanged: (s) => setState(() => _type = s.first),
        ),
        FilterChip(label: const Text('Volume profile'), selected: _profile, onSelected: (v) => setState(() => _profile = v)),
        FilterChip(label: const Text('Compare BANKNIFTY'), selected: _compare, onSelected: (v) => setState(() => _compare = v)),
      ]),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 4, children: [
        for (final name in _available.keys)
          FilterChip(
            label: Text(name),
            selected: _indicators.contains(name),
            onSelected: (v) => setState(() => v ? _indicators.add(name) : _indicators.remove(name)),
          ),
      ]),
      const SizedBox(height: 6),
      ListenableBuilder(
        listenable: _drawings,
        builder: (context, _) {
          final selected = _drawings.selected;
          return Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final (tool, icon, tip) in tools)
              IconButton.outlined(
                tooltip: tip,
                isSelected: _drawings.activeTool == tool,
                icon: Icon(icon, size: 18),
                onPressed: () => _drawings.activeTool == tool ? _drawings.cancelDrawing() : _drawings.startDrawing(tool),
              ),
            IconButton.outlined(
              tooltip: 'Text note',
              isSelected: _drawings.activeTool == DrawingTool.text,
              icon: const Icon(Icons.sticky_note_2_outlined, size: 18),
              onPressed: _addNote,
            ),
            IconButton(
              tooltip: 'Magnet: snap to open/high/low/close',
              isSelected: _drawings.magnet,
              icon: Icon(_drawings.magnet ? Icons.attractions : Icons.attractions_outlined, size: 20),
              onPressed: () => setState(() => _drawings.magnet = !_drawings.magnet),
            ),
            IconButton(
              tooltip: 'Price alert on selected line',
              isSelected: selected?.alert ?? false,
              icon: Icon(selected?.alert ?? false ? Icons.notifications_active : Icons.notifications_none, size: 20),
              onPressed: selected == null || !selected.tool.supportsAlerts
                  ? null
                  : () => _drawings.setAlert(selected.id, !selected.alert),
            ),
            IconButton(
              tooltip: 'Delete selected (Del)',
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: selected == null ? null : _drawings.removeSelected,
            ),
            TextButton(onPressed: _drawings.drawings.isEmpty ? null : _drawings.clear, child: const Text('Clear')),
            if (_lastAlert != null) Text(_lastAlert!, style: Theme.of(context).textTheme.bodySmall),
          ]);
        },
      ),
      const SizedBox(height: 8),
      Expanded(
        child: CandlestickChart2D(
          title: 'NIFTY · 1D',
          subtitle: 'Pick a tool, then drag (or click twice) · the orange level has an alert (bell)',
          candles: _candles,
          candleType: _type,
          showVolume: true,
          indicators: [for (final name in _available.keys) if (_indicators.contains(name)) _available[name]!],
          volumeProfile: _profile ? const VolumeProfile() : null,
          compare: _compare ? [CandleComparison(label: 'BANKNIFTY', candles: _bank, color: const Color(0xFFFF6D00))] : const [],
          drawingController: _drawings,
          onAlert: _onAlert,
          enableAnimation: widget.animate,
          visibleCandles: 110,
          priceFormatter: (v) => _inr(v),
        ),
      ),
    ]);
  }
}

/// Greeks of the iron condor from the payoff demo.
Widget greeksDemo({bool animate = true}) => OptionGreeksChart2D(
      legs: _PayoffDemoState.strategies['Iron condor']!,
      spot: _spot,
      daysToExpiry: 6,
      volatility: 0.13,
      enableAnimation: animate,
      priceFormatter: (v) => _inr(v),
    );

/// A simulated session of total OI, sampled every 5 minutes.
List<OpenInterestSnapshot> sampleOiSession() {
  final rnd = math.Random(17);
  var call = 1.18e8, put = 1.05e8, spot = 24410.0;
  final start = DateTime(2026, 11, 16, 9, 15);
  return [
    for (int i = 0; i <= 75; i++)
      () {
        spot += (rnd.nextDouble() - 0.45) * 14;
        // Writers add puts as the market rises, calls as it falls.
        put += (spot - 24410) * 900 + rnd.nextDouble() * 6e5;
        call += (24480 - spot) * 500 + rnd.nextDouble() * 5e5;
        return OpenInterestSnapshot(time: start.add(Duration(minutes: 5 * i)), callOI: call, putOI: put, spot: spot);
      }(),
  ];
}

Widget oiTrendDemo({bool animate = true}) => OpenInterestTrendChart2D(
      title: 'NIFTY OI through the session',
      snapshots: sampleOiSession(),
      enableAnimation: animate,
    );
