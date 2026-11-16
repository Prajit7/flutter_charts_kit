import 'package:flutter/widgets.dart';

/// How digits are grouped in large numbers.
enum DigitGrouping {
  /// 1,234,567 — groups of three.
  thousands,

  /// 12,34,567 — Indian lakh/crore grouping: three, then twos.
  indian,

  /// 1234567 — no separators.
  none,
}

/// Number and date conventions for chart labels and tooltips, without
/// depending on `intl`.
///
/// Every chart takes formatter functions (`valueFormatter`,
/// `yTickFormatter`, `priceFormatter`, `dateFormatter`, …); build them
/// from a locale:
///
/// ```dart
/// final f = ChartLocale.of(context);       // from the app's Locale
/// BarChart2D(yTickFormatter: f.compact, ...)
/// LineChart2D(yTickFormatter: (v) => f.currency(v, decimals: 0), ...)
/// GanttChart2D(dateFormatter: f.date, ...)
/// ```
///
/// Presets: [ChartLocale.english], [ChartLocale.indian] (12,34,567 and
/// lakh/crore), [ChartLocale.german], [ChartLocale.french]; or construct
/// your own.
@immutable
class ChartLocale {
  final String decimalSeparator;
  final String groupSeparator;
  final DigitGrouping grouping;
  final String currencySymbol;

  /// Put the currency symbol after the number ("12 €") instead of before.
  final bool currencyAfter;
  final List<String> monthNames;

  /// Short scale suffixes for [compact]: thousand, million, billion — or,
  /// for Indian grouping, thousand, lakh, crore.
  final List<String> compactSuffixes;

  /// Day before month in dates ("16 Nov") vs. month first ("Nov 16").
  final bool dayFirst;

  const ChartLocale({
    this.decimalSeparator = '.',
    this.groupSeparator = ',',
    this.grouping = DigitGrouping.thousands,
    this.currencySymbol = r'$',
    this.currencyAfter = false,
    this.monthNames = const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'],
    this.compactSuffixes = const ['K', 'M', 'B'],
    this.dayFirst = false,
  });

  static const english = ChartLocale();

  /// en-IN: ₹12,34,567.89, 12.3L / 4.5Cr, "16 Nov".
  static const indian = ChartLocale(
    grouping: DigitGrouping.indian,
    currencySymbol: '₹',
    compactSuffixes: ['K', 'L', 'Cr'],
    dayFirst: true,
  );

  /// de: 1.234.567,89 €, "16. Nov".
  static const german = ChartLocale(
    decimalSeparator: ',',
    groupSeparator: '.',
    currencySymbol: '€',
    currencyAfter: true,
    monthNames: ['Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'],
    compactSuffixes: [' Tsd.', ' Mio.', ' Mrd.'],
    dayFirst: true,
  );

  /// fr: 1 234 567,89 €, "16 nov.".
  static const french = ChartLocale(
    decimalSeparator: ',',
    groupSeparator: ' ',
    currencySymbol: '€',
    currencyAfter: true,
    monthNames: ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'],
    compactSuffixes: [' k', ' M', ' Md'],
    dayFirst: true,
  );

  /// A preset for [locale]: Indian for `*_IN` and `hi`, German for `de`,
  /// French for `fr`, English otherwise.
  static ChartLocale forLocale(Locale locale) {
    if (locale.countryCode == 'IN' || locale.languageCode == 'hi') return indian;
    return switch (locale.languageCode) {
      'de' => german,
      'fr' => french,
      _ => english,
    };
  }

  /// The preset for the app's current locale.
  static ChartLocale of(BuildContext context) => forLocale(Localizations.maybeLocaleOf(context) ?? const Locale('en'));

  /// [value] with grouping and [decimals] fraction digits (trailing zeros
  /// trimmed unless [fixed]).
  String number(double value, {int decimals = 2, bool fixed = false}) {
    if (!value.isFinite) return value.isNaN ? '–' : (value > 0 ? '∞' : '-∞');
    var s = value.abs().toStringAsFixed(decimals);
    var frac = '';
    final dot = s.indexOf('.');
    if (dot >= 0) {
      frac = s.substring(dot + 1);
      s = s.substring(0, dot);
      if (!fixed) frac = frac.replaceFirst(RegExp(r'0+$'), '');
    }
    final grouped = _group(s);
    final neg = value < 0 && (double.tryParse('0.$frac') != 0 || int.parse(s) != 0);
    return '${neg ? '-' : ''}$grouped${frac.isEmpty ? '' : '$decimalSeparator$frac'}';
  }

  String _group(String digits) {
    if (grouping == DigitGrouping.none || digits.length <= 3) return digits;
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final size = grouping == DigitGrouping.indian ? 2 : 3;
    final parts = <String>[];
    while (rest.length > size) {
      parts.insert(0, rest.substring(rest.length - size));
      rest = rest.substring(0, rest.length - size);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return [...parts, last3].join(groupSeparator);
  }

  /// Short form: 1.2K, 3.4M (or 12.3L, 4.5Cr for Indian grouping).
  String compact(double value) {
    final a = value.abs();
    final scales = grouping == DigitGrouping.indian ? const [1e3, 1e5, 1e7] : const [1e3, 1e6, 1e9];
    for (int i = scales.length - 1; i >= 0; i--) {
      if (a >= scales[i]) {
        final v = value / scales[i];
        return '${number(v, decimals: v.abs() >= 100 ? 0 : 1)}${compactSuffixes[i]}';
      }
    }
    return number(value, decimals: a >= 100 ? 0 : 2);
  }

  /// [value] as money: "₹12,34,567", "1.234,50 €".
  String currency(double value, {int decimals = 2, bool fixed = true, bool compactForm = false}) {
    final body = compactForm ? compact(value.abs()) : number(value.abs(), decimals: decimals, fixed: fixed);
    final sign = value < 0 ? '-' : '';
    return currencyAfter ? '$sign$body $currencySymbol' : '$sign$currencySymbol$body';
  }

  /// [value] (a fraction, 0.123) as "12.3%" / "12,3 %".
  String percent(double value, {int decimals = 1}) =>
      '${number(value * 100, decimals: decimals, fixed: true)}${decimalSeparator == ',' ? ' %' : '%'}';

  /// "16 Nov 2026" / "Nov 16, 2026" (or without the year).
  String date(DateTime t, {bool year = true}) {
    final m = monthNames[t.month - 1];
    if (dayFirst) return year ? '${t.day} $m ${t.year}' : '${t.day} $m';
    return year ? '$m ${t.day}, ${t.year}' : '$m ${t.day}';
  }

  /// Date and 24-hour time: "16 Nov 2026 14:05".
  String dateTime(DateTime t) => '${date(t)} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
