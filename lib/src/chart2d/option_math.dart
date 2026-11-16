import 'dart:math' as math;

/// What an [OptionLeg] holds.
enum OptionType {
  call,
  put,

  /// The underlying itself (stock or future): payoff is linear in price.
  underlying,
}

/// One leg of an options strategy.
///
/// [quantity] is signed: positive to buy, negative to sell (write).
/// [premium] is the price paid or received per unit — for an
/// [OptionType.underlying] leg, its entry price. Payoffs are multiplied by
/// [lotSize] (e.g. 75 for a NIFTY lot, 100 for a US equity option).
///
/// ```dart
/// // Short straddle at 24,500
/// final legs = [
///   OptionLeg.call(strike: 24500, premium: 180, quantity: -1, lotSize: 75),
///   OptionLeg.put(strike: 24500, premium: 165, quantity: -1, lotSize: 75),
/// ];
/// ```
class OptionLeg {
  final OptionType type;
  final double strike;
  final double premium;
  final double quantity;
  final double lotSize;

  /// Implied volatility (0.18 = 18%) for this leg's "today" value; falls
  /// back to the chart's volatility.
  final double? iv;

  /// Days to this leg's expiry, for calendar/diagonal spreads; falls back
  /// to the chart's daysToExpiry.
  final double? daysToExpiry;
  final String? label;

  const OptionLeg({
    required this.type,
    required this.strike,
    required this.premium,
    this.quantity = 1,
    this.lotSize = 1,
    this.iv,
    this.daysToExpiry,
    this.label,
  });

  const OptionLeg.call({
    required this.strike,
    required this.premium,
    this.quantity = 1,
    this.lotSize = 1,
    this.iv,
    this.daysToExpiry,
    this.label,
  }) : type = OptionType.call;

  const OptionLeg.put({
    required this.strike,
    required this.premium,
    this.quantity = 1,
    this.lotSize = 1,
    this.iv,
    this.daysToExpiry,
    this.label,
  }) : type = OptionType.put;

  /// A position in the underlying (stock/future) entered at [price].
  const OptionLeg.underlying({required double price, this.quantity = 1, this.lotSize = 1, this.label})
      : type = OptionType.underlying,
        strike = price,
        premium = price,
        iv = null,
        daysToExpiry = null;

  bool get isBuy => quantity > 0;

  /// Value per unit at expiry with the underlying at [spot].
  double intrinsic(double spot) => switch (type) {
        OptionType.call => math.max(0, spot - strike),
        OptionType.put => math.max(0, strike - spot),
        OptionType.underlying => spot,
      };

  /// Profit or loss of this leg at expiry.
  double payoffAtExpiry(double spot) => quantity * lotSize * (intrinsic(spot) - premium);

  /// Short description, e.g. "+1 24500 CE" / "-2 24000 PE" / "+1 FUT".
  String get description {
    final q = '${quantity > 0 ? '+' : ''}${quantity == quantity.roundToDouble() ? quantity.toInt() : quantity}';
    final k = strike == strike.roundToDouble() ? strike.toInt().toString() : strike.toString();
    return switch (type) {
      OptionType.call => '$q $k CE',
      OptionType.put => '$q $k PE',
      OptionType.underlying => '$q FUT @ $k',
    };
  }
}

/// Black-Scholes sensitivities of one option (per unit).
class OptionGreeks {
  final double price;
  final double delta;

  /// Change in delta per 1 move in the underlying.
  final double gamma;

  /// Value lost per calendar day.
  final double theta;

  /// Value change per 1 percentage point of volatility.
  final double vega;

  /// Value change per 1 percentage point of interest rate.
  final double rho;

  const OptionGreeks({
    required this.price,
    required this.delta,
    required this.gamma,
    required this.theta,
    required this.vega,
    required this.rho,
  });
}

/// Pure-Dart option maths: Black-Scholes pricing and Greeks, implied
/// volatility, and strategy payoffs, breakevens and extremes.
///
/// Volatility and rates are fractions (0.18 = 18%); time is in years.
abstract final class OptionMath {
  /// Standard normal cumulative distribution (Abramowitz–Stegun 26.2.17,
  /// error < 7.5e-8).
  static double normCdf(double x) {
    if (x.isNaN) return double.nan;
    if (x < -10) return 0;
    if (x > 10) return 1;
    final t = 1 / (1 + 0.2316419 * x.abs());
    final poly = t * (0.319381530 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))));
    final tail = normPdf(x) * poly;
    return x >= 0 ? 1 - tail : tail;
  }

  /// Standard normal density.
  static double normPdf(double x) => math.exp(-x * x / 2) / math.sqrt(2 * math.pi);

  /// Black-Scholes price of a European option (no dividends). At or after
  /// expiry, or with zero volatility, this is the discounted intrinsic value.
  static double blackScholes({
    required OptionType type,
    required double spot,
    required double strike,
    required double years,
    required double volatility,
    double rate = 0,
  }) =>
      greeks(type: type, spot: spot, strike: strike, years: years, volatility: volatility, rate: rate).price;

  /// Black-Scholes price and Greeks.
  static OptionGreeks greeks({
    required OptionType type,
    required double spot,
    required double strike,
    required double years,
    required double volatility,
    double rate = 0,
  }) {
    if (type == OptionType.underlying) {
      return OptionGreeks(price: spot, delta: 1, gamma: 0, theta: 0, vega: 0, rho: 0);
    }
    final isCall = type == OptionType.call;
    if (years <= 0 || volatility <= 0 || spot <= 0 || strike <= 0) {
      final disc = years > 0 ? math.exp(-rate * years) : 1.0;
      final intrinsic = isCall ? math.max(0.0, spot - strike * disc) : math.max(0.0, strike * disc - spot);
      final itm = isCall ? spot > strike : spot < strike;
      return OptionGreeks(price: intrinsic, delta: itm ? (isCall ? 1 : -1) : 0, gamma: 0, theta: 0, vega: 0, rho: 0);
    }
    final sqrtT = math.sqrt(years);
    final d1 = (math.log(spot / strike) + (rate + volatility * volatility / 2) * years) / (volatility * sqrtT);
    final d2 = d1 - volatility * sqrtT;
    final disc = math.exp(-rate * years);
    final pdf1 = normPdf(d1);
    final price = isCall
        ? spot * normCdf(d1) - strike * disc * normCdf(d2)
        : strike * disc * normCdf(-d2) - spot * normCdf(-d1);
    final delta = isCall ? normCdf(d1) : normCdf(d1) - 1;
    final gamma = pdf1 / (spot * volatility * sqrtT);
    final thetaYear = -spot * pdf1 * volatility / (2 * sqrtT) +
        (isCall ? -rate * strike * disc * normCdf(d2) : rate * strike * disc * normCdf(-d2));
    final vega = spot * pdf1 * sqrtT / 100;
    final rho = (isCall ? strike * years * disc * normCdf(d2) : -strike * years * disc * normCdf(-d2)) / 100;
    return OptionGreeks(price: math.max(0, price), delta: delta, gamma: gamma, theta: thetaYear / 365, vega: vega, rho: rho);
  }

  /// The volatility at which Black-Scholes gives [price], or null when no
  /// volatility does (price below intrinsic or above the spot/strike bound).
  /// Newton's method with a bisection fallback.
  static double? impliedVolatility({
    required double price,
    required OptionType type,
    required double spot,
    required double strike,
    required double years,
    double rate = 0,
  }) {
    if (type == OptionType.underlying || years <= 0 || price <= 0 || spot <= 0 || strike <= 0) return null;
    double f(double v) => blackScholes(type: type, spot: spot, strike: strike, years: years, volatility: v, rate: rate) - price;
    var lo = 1e-4, hi = 5.0;
    if (f(lo) > 0 || f(hi) < 0) return null;
    var v = 0.3;
    for (int i = 0; i < 50; i++) {
      final diff = f(v);
      if (diff.abs() < 1e-7) return v;
      diff > 0 ? hi = v : lo = v;
      final g = greeks(type: type, spot: spot, strike: strike, years: years, volatility: v, rate: rate);
      final vega = g.vega * 100;
      var next = vega > 1e-10 ? v - diff / vega : (lo + hi) / 2;
      if (!(next > lo && next < hi)) next = (lo + hi) / 2;
      if ((next - v).abs() < 1e-9) return next;
      v = next;
    }
    return v;
  }

  /// Total profit/loss of [legs] at expiry with the underlying at [spot].
  static double payoffAtExpiry(List<OptionLeg> legs, double spot) =>
      legs.fold(0.0, (s, l) => s + l.payoffAtExpiry(spot));

  /// Profit/loss of [legs] if valued now, [daysElapsed] days from today:
  /// each leg's remaining time is its own daysToExpiry (or [daysToExpiry])
  /// minus [daysElapsed], priced with its own iv (or [volatility]).
  static double payoffBeforeExpiry(
    List<OptionLeg> legs,
    double spot, {
    required double daysToExpiry,
    double daysElapsed = 0,
    double volatility = 0.2,
    double rate = 0,
  }) {
    var total = 0.0;
    for (final l in legs) {
      if (l.type == OptionType.underlying) {
        total += l.payoffAtExpiry(spot);
        continue;
      }
      final days = (l.daysToExpiry ?? daysToExpiry) - daysElapsed;
      final value = blackScholes(
          type: l.type, spot: spot, strike: l.strike, years: days / 365, volatility: l.iv ?? volatility, rate: rate);
      total += l.quantity * l.lotSize * (value - l.premium);
    }
    return total;
  }

  /// A whole position's Greeks at [spot]: each leg's Black-Scholes Greeks
  /// × quantity × lot size, summed. [OptionGreeks.price] is the position's
  /// P&L (as [payoffBeforeExpiry]).
  static OptionGreeks positionGreeks(
    List<OptionLeg> legs,
    double spot, {
    required double daysToExpiry,
    double daysElapsed = 0,
    double volatility = 0.2,
    double rate = 0,
  }) {
    double delta = 0, gamma = 0, theta = 0, vega = 0, rho = 0;
    for (final l in legs) {
      final m = l.quantity * l.lotSize;
      final g = greeks(
        type: l.type,
        spot: spot,
        strike: l.strike,
        years: ((l.daysToExpiry ?? daysToExpiry) - daysElapsed) / 365,
        volatility: l.iv ?? volatility,
        rate: rate,
      );
      delta += m * g.delta;
      gamma += m * g.gamma;
      theta += m * g.theta;
      vega += m * g.vega;
      rho += m * g.rho;
    }
    return OptionGreeks(
      price: payoffBeforeExpiry(legs, spot,
          daysToExpiry: daysToExpiry, daysElapsed: daysElapsed, volatility: volatility, rate: rate),
      delta: delta,
      gamma: gamma,
      theta: theta,
      vega: vega,
      rho: rho,
    );
  }

  /// Net premium: positive = credit received, negative = debit paid.
  static double netPremium(List<OptionLeg> legs) => legs
      .where((l) => l.type != OptionType.underlying)
      .fold(0.0, (s, l) => s - l.quantity * l.lotSize * l.premium);

  /// Spot prices where the expiry payoff crosses zero, in ascending order.
  /// The payoff is piecewise linear with kinks at the strikes, so each
  /// segment is solved exactly.
  static List<double> breakevens(List<OptionLeg> legs) {
    final pts = _kinks(legs);
    final out = <double>[];
    for (int i = 0; i + 1 < pts.length; i++) {
      final a = pts[i], b = pts[i + 1];
      final pa = payoffAtExpiry(legs, a), pb = payoffAtExpiry(legs, b);
      if (pa == 0 && (out.isEmpty || (out.last - a).abs() > 1e-9)) out.add(a);
      if ((pa < 0 && pb > 0) || (pa > 0 && pb < 0)) out.add(a + (b - a) * (-pa) / (pb - pa));
    }
    final last = pts.last;
    if (payoffAtExpiry(legs, last) == 0 && (out.isEmpty || (out.last - last).abs() > 1e-9)) out.add(last);
    // Beyond the last kink the payoff is linear: solve it there too.
    final slope = upsideSlope(legs);
    final pl = payoffAtExpiry(legs, last);
    if (slope != 0 && pl * slope < 0) out.add(last - pl / slope);
    return out;
  }

  /// How fast the expiry payoff grows per unit of spot as spot → ∞.
  static double upsideSlope(List<OptionLeg> legs) => legs
      .where((l) => l.type != OptionType.put)
      .fold(0.0, (s, l) => s + l.quantity * l.lotSize);

  /// Maximum profit at expiry, or null when unlimited.
  static double? maxProfit(List<OptionLeg> legs) {
    if (upsideSlope(legs) > 1e-12) return null;
    return _kinks(legs).map((s) => payoffAtExpiry(legs, s)).reduce(math.max);
  }

  /// Maximum loss at expiry as a negative number (or 0), or null when
  /// unlimited.
  static double? maxLoss(List<OptionLeg> legs) {
    if (upsideSlope(legs) < -1e-12) return null;
    return math.min(0, _kinks(legs).map((s) => payoffAtExpiry(legs, s)).reduce(math.min));
  }

  /// 0, every strike, and a point past the highest strike.
  static List<double> _kinks(List<OptionLeg> legs) {
    final strikes = {0.0, for (final l in legs) if (l.type != OptionType.underlying) l.strike}.toList()..sort();
    final top = legs.isEmpty ? 1.0 : legs.map((l) => l.strike).reduce(math.max);
    strikes.add(math.max(strikes.last, top) * 1.5 + 1);
    return strikes;
  }

  /// One-standard-deviation expected move: spot·e^(±σ√t).
  static (double, double) expectedMove(double spot, double volatility, double days) {
    final s = volatility * math.sqrt(math.max(0, days) / 365);
    return (spot * math.exp(-s), spot * math.exp(s));
  }

  /// The strike where option writers pay out least at expiry — "max pain".
  /// [strikes] are (strike, callOI, putOI).
  static double? maxPain(List<(double, double, double)> strikes) {
    if (strikes.isEmpty) return null;
    double? best;
    var bestPain = double.infinity;
    for (final (s, _, _) in strikes) {
      var pain = 0.0;
      for (final (k, c, p) in strikes) {
        pain += c * math.max(0, s - k) + p * math.max(0, k - s);
      }
      if (pain < bestPain) {
        bestPain = pain;
        best = s;
      }
    }
    return best;
  }
}
