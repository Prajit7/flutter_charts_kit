import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A demo chart with a "</> Code" button that shows a copyable snippet —
/// the demo site doubles as interactive docs.
class CodeCard extends StatelessWidget {
  final Widget child;
  final String code;
  final double height;

  const CodeCard({super.key, required this.child, required this.code, this.height = 380});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: SizedBox(
        height: height,
        child: Stack(children: [
          Positioned.fill(child: child),
          Positioned(
            right: 0,
            top: 0,
            child: TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, textStyle: const TextStyle(fontSize: 12)),
              onPressed: () => _show(context),
              icon: const Icon(Icons.code, size: 16),
              label: const Text('Code'),
            ),
          ),
        ]),
      ),
    );
  }

  void _show(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(children: [
                const Expanded(child: Text('Example', style: TextStyle(fontWeight: FontWeight.w700))),
                TextButton.icon(
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code.trim()));
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Copied')));
                  },
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ]),
            ),
            Flexible(
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectableText(code.trim(), style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.45)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Snippets for the demo cards, keyed by chart.
const snippets = <String, String>{
  'payoff': r'''
OptionPayoffChart2D(
  spot: 24480,
  daysToExpiry: 6,
  volatility: 0.13,            // for legs without their own iv
  legs: const [
    OptionLeg.put(strike: 24200, premium: 18, quantity: 1, lotSize: 75),
    OptionLeg.put(strike: 24300, premium: 34, quantity: -1, lotSize: 75),
    OptionLeg.call(strike: 24700, premium: 30, quantity: -1, lotSize: 75),
    OptionLeg.call(strike: 24800, premium: 15, quantity: 1, lotSize: 75),
  ],
)''',
  'greeks': r'''
OptionGreeksChart2D(legs: legs, spot: 24480, daysToExpiry: 6, volatility: 0.13)

// Or the numbers directly:
final g = OptionMath.positionGreeks(legs, 24480, daysToExpiry: 6, volatility: 0.13);
print('Δ ${g.delta}  Γ ${g.gamma}  Θ ${g.theta}/day  V ${g.vega}');''',
  'oi': r'''
OpenInterestChart2D(
  spot: 24480,
  view: OpenInterestView.total,   // or .change
  strikes: [
    OptionStrikeData(strike: 24500, callOI: 8.2e6, putOI: 6.1e6, callOIChange: 9e5, putOIChange: -2e5),
    // ...
  ],
)''',
  'oiTrend': r'''
OpenInterestTrendChart2D(
  title: 'NIFTY OI through the session',
  snapshots: [
    OpenInterestSnapshot(time: t, callOI: 1.2e8, putOI: 1.1e8),
    // ... one per interval
  ],
)''',
  'depth': r'''
MarketDepthChart2D(
  bids: [DepthLevel(24479.5, 300), DepthLevel(24479, 1200)],
  asks: [DepthLevel(24480.5, 450), DepthLevel(24481, 900)],
)
// Pass new lists as the book updates — no entrance replay.''',
  'smile': r'''
VolatilitySmileChart2D(
  spot: 24480,
  smiles: [
    VolatilitySmile(label: 'Weekly', color: Colors.indigo,
        points: {24000: 0.168, 24500: 0.131, 25000: 0.142}),
  ],
)

// IV from an option price:
OptionMath.impliedVolatility(price: 182, type: OptionType.call,
    spot: 24480, strike: 24500, years: 6 / 365);''',
  'trading': r'''
final drawings = ChartDrawingController(magnet: true);

CandlestickChart2D(
  candles: candles,
  candleType: CandleType.heikinAshi,     // renko, lineBreak, standard
  volumeProfile: const VolumeProfile(),
  indicators: const [SupertrendIndicator(), StochasticIndicator()],
  compare: [CandleComparison(label: 'BANKNIFTY', candles: bank, color: Colors.orange)],
  drawingController: drawings,
  onAlert: (a) => print('Crossed ${a.level}'),
)

drawings.startDrawing(DrawingTool.fibonacci);
drawings.setAlert(drawings.selectedId!, true);
final saved = jsonEncode(drawings.toJson());''',
  'bump': r'''
BumpChart2D(
  periods: ['Q1', 'Q2', 'Q3', 'Q4'],
  series: const [
    CategorySeries(name: 'Zepto', color: Colors.purple, values: [40, 52, 61, 70]),
    CategorySeries(name: 'Blinkit', color: Colors.amber, values: [72, 70, 68, 66]),
  ],
)''',
  'slope': r'''
SlopeChart2D(
  startLabel: 'Before', endLabel: 'After',
  items: const [
    SlopeItem(label: 'Organic', start: 3.1, end: 4.2),
    SlopeItem(label: 'Email', start: 5.6, end: 5.1),
  ],
)''',
  'marimekko': r'''
MarimekkoChart2D(
  categories: ['Retail', 'SMB', 'Enterprise'],
  series: const [
    CategorySeries(name: 'Us', color: Colors.indigo, values: [120, 210, 90]),
    CategorySeries(name: 'Rival', color: Colors.teal, values: [300, 140, 260]),
  ],
)''',
  'stream': r'''
StreamgraphChart2D(
  labels: months,
  baseline: StreamBaseline.silhouette,   // wiggle, zero
  series: [CategorySeries(name: 'Pop', color: Colors.pink, values: pop), ...],
)''',
  'beeswarm': r'''
BeeswarmChart2D(groups: [
  BeeswarmGroup(label: 'Mumbai', color: Colors.indigo, values: latenciesMs),
])''',
  'ridgeline': r'''
RidgelineChart2D(groups: [
  for (final m in months) RidgelineGroup(label: m.name, values: m.dailyMax),
])''',
  'tree': r'''
TreeChart2D(
  orientation: TreeOrientation.leftToRight,
  initialDepth: 2,                 // deeper levels start collapsed
  root: TreeChartNode(label: 'CEO', children: [
    TreeChartNode(label: 'CTO', subtitle: 'Engineering', children: [...]),
  ]),
)''',
  'timeline': r'''
TimelineChart2D(events: [
  TimelineEvent(start: DateTime(2025, 1, 15), title: 'Founded'),
  TimelineEvent(start: DateTime(2025, 2, 1), end: DateTime(2025, 6, 30), title: 'Beta'),
])''',
  'table': r'''
ChartWithTable(
  chart: MarimekkoChart2D(categories: segments, series: series),
  table: ChartDataTable.fromCategorySeries(categories: segments, series: series),
)

// Locale-aware formatters (no intl dependency):
final f = ChartLocale.of(context);      // ChartLocale.indian → 12,34,567 / 4.5Cr
BarChart2D(yTickFormatter: f.compact, ...)''',
};
