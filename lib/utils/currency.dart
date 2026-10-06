import 'package:intl/intl.dart';

import 'country_iso.dart';
import 'money.dart';

/// Mistaken alpha-3 country codes (or other 3-letter junk) → ISO 4217 for Stripe.
/// Parity with web `MISTAKEN_CURRENCY_LABELS` / `STRIPE_CURRENCY_ALIASES`.
const Map<String, String> _stripeCurrencyAliases = {
  'che': 'chf',
  'gbr': 'gbp',
  'deu': 'eur',
  'fra': 'eur',
  'ita': 'eur',
  'esp': 'eur',
  'usa': 'usd',
  'fin': 'eur',
  'swe': 'sek',
  'nor': 'nok',
  'dnk': 'dkk',
};

/// Returns lowercase ISO 4217 suitable for Stripe PaymentIntent `currency`.
String normalizeStripeCurrencyCode(String raw) {
  var t = raw.trim();
  if (t.isEmpty) return 'eur';
  t = t.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
  final key = t.toLowerCase();
  final lettersOnly = key.replaceAll(RegExp(r'[^a-z]'), '');
  return _stripeCurrencyAliases[key] ?? _stripeCurrencyAliases[lettersOnly] ?? key;
}

/// ISO 4217 code for UI labels (e.g. mistaken `che` → `CHF`).
String normalizeDisplayCurrencyCode(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return 'EUR';
  return normalizeStripeCurrencyCode(t).toUpperCase();
}

/// Lowercase ISO 4217 from [event.country] (parity with web `getCurrencyCode`).
String currencyFromCountry(String? country) {
  final name = (country == null || country.trim().isEmpty)
      ? defaultEventCountryName
      : country.trim();
  return normalizeStripeCurrencyCode(getCurrencyCodeFromCountry(name));
}

/// Display symbol from a raw currency field — parity with web `getCurrencySymbolFromIsoCode`.
String currencySymbolFromIsoCode(String? raw) {
  final code = normalizeDisplayCurrencyCode(raw ?? '');
  try {
    final f = NumberFormat.currency(locale: 'en_US', name: code);
    return f.currencySymbol;
  } catch (_) {
    return currencySymbol(code);
  }
}

/// Display symbol from country name — parity with web `getCurrencySymbol`.
String currencySymbolFromCountry(String countryName) {
  return currencySymbolFromIsoCode(getCurrencyCodeFromCountry(countryName));
}

const Map<String, String> _currencySymbols = {
  'eur': '€', 'gbp': '£', 'usd': '\$', 'jpy': '¥', 'cny': '¥', 'krw': '₩', 'kpw': '₩',
  'inr': '₹', 'rub': '₽', 'byn': 'Br', 'try': '₺', 'brl': 'R\$', 'zar': 'R', 'ils': '₪',
  'pln': 'zł', 'uah': '₴', 'kzt': '₸', 'thb': '฿', 'vnd': '₫', 'php': '₱', 'ngn': '₦',
  'pkr': '₨', 'npr': '₨', 'lkr': 'Rs', 'bdt': '৳', 'mmk': 'K', 'khr': '៛', 'lak': '₭',
  'gel': '₾', 'amd': '֏', 'azn': '₼', 'uzs': "so'm", 'gmd': 'D', 'ghs': '₵', 'mad': 'د.م.',
  'tnd': 'د.ت', 'iqd': 'ع.د', 'irr': '﷼', 'yer': '﷼', 'sar': 'ر.س', 'qar': 'ر.ق', 'kwd': 'د.ك',
  'bhd': 'د.ب', 'omr': 'ر.ع', 'aed': 'د.إ', 'egp': 'E£', 'lbp': 'ل.ل', 'syp': '£', 'jod': 'د.ا',
  'sek': 'kr', 'nok': 'kr', 'dkk': 'kr', 'isk': 'kr', 'czk': 'Kč', 'ron': 'lei', 'bgn': 'лв',
  'rsd': 'дин.', 'mkd': 'ден.', 'mdl': 'L', 'huf': 'Ft', 'pyg': '₲', 'uyu': '\$', 'ars': '\$',
  'clp': '\$', 'cop': '\$', 'mxn': '\$', 'pen': 'S/', 'ves': 'Bs.S.', 'bob': 'Bs.', 'srd': '\$',
  'pab': 'B/.', 'dop': '\$', 'crc': '₡', 'nio': 'C\$', 'gtq': 'Q', 'hnl': 'L',
  'aud': '\$', 'cad': '\$', 'nzd': '\$', 'chf': 'Fr', 'xof': 'CFA', 'xaf': 'FCFA', 'xpf': 'Fr',
  'kes': 'K', 'tzs': 'TSh', 'ugx': 'USh', 'rwf': 'Fr', 'bif': 'Fr', 'djf': 'Fr',
  'etb': 'Br', 'sos': 'S', 'sll': 'Le', 'sle': 'Le', 'gnf': 'Fr', 'mru': 'UM',
  'mga': 'Ar', 'scr': '₨', 'mur': '₨', 'kmf': 'Fr', 'cdf': 'Fr', 'mwk': 'MK',
  'zmw': 'ZK', 'bwp': 'P', 'nad': '\$', 'szl': 'L', 'lsl': 'L', 'mzn': 'MT', 'aoa': 'Kz',
  'ern': 'Nfk', 'sdg': 'ج.س.', 'ssp': '£', 'stn': 'Db', 'cve': '\$', 'gyd': '\$', 'sbd': '\$',
  'fjd': '\$', 'vuv': 'Vt', 'wst': 'T', 'top': 'T\$', 'pgk': 'K', 'idr': 'Rp',
  'myr': 'RM', 'sgd': '\$', 'bnd': '\$', 'hkd': '\$', 'mop': 'P', 'twd': '\$', 'jmd': '\$',
  'ttd': '\$', 'bbd': '\$', 'bzd': '\$', 'bsd': '\$', 'kyd': '\$', 'bmd': '\$', 'awg': 'ƒ',
  'ang': 'ƒ', 'fkp': '£', 'cup': '\$', 'dzd': 'د.ج', 'lyd': 'ل.د', 'tjs': 'SM', 'tmt': 'm',
  'kgs': 'с', 'mnt': '₮', 'btn': 'Nu.', 'lrd': '\$', 'all': 'L', 'bam': 'KM',
};

String currencySymbol(String currencyCode) {
  final normalized = normalizeStripeCurrencyCode(currencyCode);
  final lower = normalized.toLowerCase();
  return _currencySymbols[lower] ?? normalized.toUpperCase();
}

/// Amount first, then ISO 4217 code (web parity: `76.000 CHF`).
String formatPrice(double amount, String currencyCode) {
  final normalizedCode = normalizeStripeCurrencyCode(currencyCode);
  final display = normalizeDisplayCurrencyCode(currencyCode);
  final code = normalizedCode.toLowerCase();
  const zeroDecimals = {'jpy', 'krw', 'vnd', 'cny', 'clp', 'kpw', 'pyg'};
  if (zeroDecimals.contains(code)) {
    return '${amount.toStringAsFixed(0)} $display';
  }
  return '${roundMoney(amount).toStringAsFixed(2)} $display';
}

String formatPriceWithDecimals(double amount, String currencyCode, int decimals) {
  final display = normalizeDisplayCurrencyCode(currencyCode);
  final decimalsToShow = decimals < 0 ? 0 : (decimals > 2 ? 2 : decimals);
  return '${roundMoney(amount).toStringAsFixed(decimalsToShow)} $display';
}

String formatFinalTotal(double amount, String currencyCode) {
  final display = normalizeDisplayCurrencyCode(currencyCode);
  return '${roundMoney(amount).toStringAsFixed(2)} $display';
}
