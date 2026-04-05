import 'package:intl/intl.dart';

const Map<String, String> _countryToCurrency = {
  'ad': 'eur', 'andorra': 'eur',
  'ae': 'aed', 'united arab emirates': 'aed', 'uae': 'aed',
  'af': 'afn', 'afghanistan': 'afn',
  'ag': 'xcd', 'antigua and barbuda': 'xcd',
  'al': 'all', 'albania': 'all',
  'am': 'amd', 'armenia': 'amd',
  'ao': 'aoa', 'angola': 'aoa',
  'ar': 'ars', 'argentina': 'ars',
  'at': 'eur', 'austria': 'eur',
  'au': 'aud', 'australia': 'aud',
  'az': 'azn', 'azerbaijan': 'azn',
  'ba': 'bam', 'bosnia and herzegovina': 'bam', 'bosnia': 'bam',
  'bb': 'bbd', 'barbados': 'bbd',
  'bd': 'bdt', 'bangladesh': 'bdt',
  'be': 'eur', 'belgium': 'eur',
  'bf': 'xof', 'burkina faso': 'xof',
  'bg': 'bgn', 'bulgaria': 'bgn',
  'bh': 'bhd', 'bahrain': 'bhd',
  'bi': 'bif', 'burundi': 'bif',
  'bj': 'xof', 'benin': 'xof',
  'bn': 'bnd', 'brunei': 'bnd', 'brunei darussalam': 'bnd',
  'bo': 'bob', 'bolivia': 'bob',
  'br': 'brl', 'brazil': 'brl',
  'bs': 'bsd', 'bahamas': 'bsd',
  'bt': 'btn', 'bhutan': 'btn',
  'bw': 'bwp', 'botswana': 'bwp',
  'by': 'byn', 'belarus': 'byn',
  'bz': 'bzd', 'belize': 'bzd',
  'ca': 'cad', 'canada': 'cad',
  'cd': 'cdf', 'democratic republic of the congo': 'cdf', 'drc': 'cdf',
  'cf': 'xaf', 'central african republic': 'xaf',
  'cg': 'xaf', 'republic of the congo': 'xaf', 'congo': 'xaf',
  'ch': 'chf', 'switzerland': 'chf',
  'ci': 'xof', 'ivory coast': 'xof', 'côte d\'ivoire': 'xof',
  'cl': 'clp', 'chile': 'clp',
  'cm': 'xaf', 'cameroon': 'xaf',
  'cn': 'cny', 'china': 'cny',
  'co': 'cop', 'colombia': 'cop',
  'cr': 'crc', 'costa rica': 'crc',
  'cu': 'cup', 'cuba': 'cup',
  'cv': 'cve', 'cape verde': 'cve',
  'cy': 'eur', 'cyprus': 'eur',
  'cz': 'czk', 'czech republic': 'czk', 'czechia': 'czk',
  'de': 'eur', 'germany': 'eur',
  'dj': 'djf', 'djibouti': 'djf',
  'dk': 'dkk', 'denmark': 'dkk',
  'dm': 'xcd', 'dominica': 'xcd',
  'do': 'dop', 'dominican republic': 'dop',
  'dz': 'dzd', 'algeria': 'dzd',
  'ec': 'usd', 'ecuador': 'usd',
  'ee': 'eur', 'estonia': 'eur',
  'eg': 'egp', 'egypt': 'egp',
  'er': 'ern', 'eritrea': 'ern',
  'es': 'eur', 'spain': 'eur',
  'et': 'etb', 'ethiopia': 'etb',
  'fi': 'eur', 'finland': 'eur',
  'fj': 'fjd', 'fiji': 'fjd',
  'fm': 'usd', 'micronesia': 'usd',
  'fr': 'eur', 'france': 'eur',
  'ga': 'xaf', 'gabon': 'xaf',
  'gb': 'gbp', 'uk': 'gbp', 'united kingdom': 'gbp', 'great britain': 'gbp',
  'gd': 'xcd', 'grenada': 'xcd',
  'ge': 'gel', 'georgia': 'gel',
  'gh': 'ghs', 'ghana': 'ghs',
  'gm': 'gmd', 'gambia': 'gmd',
  'hk': 'hkd', 'hong kong': 'hkd',
  'fo': 'dkk', 'faroe islands': 'dkk',
  'gl': 'dkk', 'greenland': 'dkk',
  'xk': 'eur', 'kosovo': 'eur',
  'pr': 'usd', 'puerto rico': 'usd',
  're': 'eur', 'réunion': 'eur',
  'gf': 'eur', 'french guiana': 'eur',
  'gp': 'eur', 'guadeloupe': 'eur',
  'mq': 'eur', 'martinique': 'eur',
  'yt': 'eur', 'mayotte': 'eur',
  'nc': 'xpf', 'new caledonia': 'xpf',
  'pf': 'xpf', 'french polynesia': 'xpf',
  'pm': 'eur', 'saint pierre and miquelon': 'eur',
  'wf': 'xpf', 'wallis and futuna': 'xpf',
  'ax': 'eur', 'åland islands': 'eur',
  'bq': 'usd', 'caribbean netherlands': 'usd',
  'cw': 'ang', 'curaçao': 'ang',
  'sx': 'ang', 'sint maarten': 'ang',
  'aw': 'awg', 'aruba': 'awg',
  'ky': 'kyd', 'cayman islands': 'kyd',
  'bm': 'bmd', 'bermuda': 'bmd',
  'vg': 'usd', 'british virgin islands': 'usd',
  'vi': 'usd', 'u.s. virgin islands': 'usd',
  'gu': 'usd', 'guam': 'usd',
  'as': 'usd', 'american samoa': 'usd',
  'mp': 'usd', 'northern mariana islands': 'usd',
  'tc': 'usd', 'turks and caicos islands': 'usd',
  'fk': 'fkp', 'falkland islands': 'fkp',
  'gi': 'gbp', 'gibraltar': 'gbp',
  'im': 'gbp', 'isle of man': 'gbp',
  'je': 'gbp', 'jersey': 'gbp',
  'gg': 'gbp', 'guernsey': 'gbp',
  'mo': 'mop', 'macau': 'mop', 'macao': 'mop',
  'gn': 'gnf', 'guinea': 'gnf',
  'gq': 'xaf', 'equatorial guinea': 'xaf',
  'gr': 'eur', 'greece': 'eur',
  'gt': 'gtq', 'guatemala': 'gtq',
  'gw': 'xof', 'guinea-bissau': 'xof',
  'gy': 'gyd', 'guyana': 'gyd',
  'hn': 'hnl', 'honduras': 'hnl',
  'hr': 'eur', 'croatia': 'eur',
  'ht': 'htg', 'haiti': 'htg',
  'hu': 'huf', 'hungary': 'huf',
  'id': 'idr', 'indonesia': 'idr',
  'ie': 'eur', 'ireland': 'eur',
  'il': 'ils', 'israel': 'ils',
  'in': 'inr', 'india': 'inr',
  'iq': 'iqd', 'iraq': 'iqd',
  'ir': 'irr', 'iran': 'irr',
  'is': 'isk', 'iceland': 'isk',
  'it': 'eur', 'italy': 'eur',
  'jm': 'jmd', 'jamaica': 'jmd',
  'jo': 'jod', 'jordan': 'jod',
  'jp': 'jpy', 'japan': 'jpy',
  'ke': 'kes', 'kenya': 'kes',
  'kg': 'kgs', 'kyrgyzstan': 'kgs',
  'kh': 'khr', 'cambodia': 'khr',
  'ki': 'aud', 'kiribati': 'aud',
  'km': 'kmf', 'comoros': 'kmf',
  'kn': 'xcd', 'saint kitts and nevis': 'xcd',
  'kp': 'kpw', 'north korea': 'kpw',
  'kr': 'krw', 'south korea': 'krw', 'korea': 'krw',
  'kw': 'kwd', 'kuwait': 'kwd',
  'kz': 'kzt', 'kazakhstan': 'kzt',
  'la': 'lak', 'laos': 'lak',
  'lb': 'lbp', 'lebanon': 'lbp',
  'lc': 'xcd', 'saint lucia': 'xcd',
  'li': 'chf', 'liechtenstein': 'chf',
  'lk': 'lkr', 'sri lanka': 'lkr',
  'lr': 'lrd', 'liberia': 'lrd',
  'ls': 'lsl', 'lesotho': 'lsl',
  'lt': 'eur', 'lithuania': 'eur',
  'lu': 'eur', 'luxembourg': 'eur',
  'lv': 'eur', 'latvia': 'eur',
  'ly': 'lyd', 'libya': 'lyd',
  'ma': 'mad', 'morocco': 'mad',
  'mc': 'eur', 'monaco': 'eur',
  'md': 'mdl', 'moldova': 'mdl',
  'me': 'eur', 'montenegro': 'eur',
  'mg': 'mga', 'madagascar': 'mga',
  'mh': 'usd', 'marshall islands': 'usd',
  'mk': 'mkd', 'north macedonia': 'mkd', 'macedonia': 'mkd',
  'ml': 'xof', 'mali': 'xof',
  'mm': 'mmk', 'myanmar': 'mmk', 'burma': 'mmk',
  'mn': 'mnt', 'mongolia': 'mnt',
  'mr': 'mru', 'mauritania': 'mru',
  'mt': 'eur', 'malta': 'eur',
  'mu': 'mur', 'mauritius': 'mur',
  'mv': 'mvr', 'maldives': 'mvr',
  'mw': 'mwk', 'malawi': 'mwk',
  'mx': 'mxn', 'mexico': 'mxn',
  'my': 'myr', 'malaysia': 'myr',
  'mz': 'mzn', 'mozambique': 'mzn',
  'na': 'nad', 'namibia': 'nad',
  'ne': 'xof', 'niger': 'xof',
  'ng': 'ngn', 'nigeria': 'ngn',
  'ni': 'nio', 'nicaragua': 'nio',
  'nl': 'eur', 'netherlands': 'eur',
  'no': 'nok', 'norway': 'nok',
  'np': 'npr', 'nepal': 'npr',
  'nr': 'aud', 'nauru': 'aud',
  'nz': 'nzd', 'new zealand': 'nzd',
  'om': 'omr', 'oman': 'omr',
  'pa': 'pab', 'panama': 'pab',
  'pe': 'pen', 'peru': 'pen',
  'pg': 'pgk', 'papua new guinea': 'pgk',
  'ph': 'php', 'philippines': 'php',
  'pk': 'pkr', 'pakistan': 'pkr',
  'pl': 'pln', 'poland': 'pln',
  'ps': 'ils', 'palestine': 'ils',
  'pt': 'eur', 'portugal': 'eur',
  'pw': 'usd', 'palau': 'usd',
  'py': 'pyg', 'paraguay': 'pyg',
  'qa': 'qar', 'qatar': 'qar',
  'ro': 'ron', 'romania': 'ron',
  'rs': 'rsd', 'serbia': 'rsd',
  'ru': 'rub', 'russia': 'rub', 'russian federation': 'rub',
  'rw': 'rwf', 'rwanda': 'rwf',
  'sa': 'sar', 'saudi arabia': 'sar',
  'sb': 'sbd', 'solomon islands': 'sbd',
  'sc': 'scr', 'seychelles': 'scr',
  'sd': 'sdg', 'sudan': 'sdg',
  'se': 'sek', 'sweden': 'sek',
  'sg': 'sgd', 'singapore': 'sgd',
  'si': 'eur', 'slovenia': 'eur',
  'sk': 'eur', 'slovakia': 'eur',
  'sl': 'sle', 'sierra leone': 'sle',
  'sm': 'eur', 'san marino': 'eur',
  'sn': 'xof', 'senegal': 'xof',
  'so': 'sos', 'somalia': 'sos',
  'sr': 'srd', 'suriname': 'srd',
  'ss': 'ssp', 'south sudan': 'ssp',
  'st': 'stn', 'são tomé and príncipe': 'stn',
  'sv': 'usd', 'el salvador': 'usd',
  'sy': 'syp', 'syria': 'syp',
  'sz': 'szl', 'eswatini': 'szl', 'swaziland': 'szl',
  'td': 'xaf', 'chad': 'xaf',
  'tg': 'xof', 'togo': 'xof',
  'th': 'thb', 'thailand': 'thb',
  'tj': 'tjs', 'tajikistan': 'tjs',
  'tl': 'usd', 'timor-leste': 'usd', 'east timor': 'usd',
  'tm': 'tmt', 'turkmenistan': 'tmt',
  'tn': 'tnd', 'tunisia': 'tnd',
  'to': 'top', 'tonga': 'top',
  'tr': 'try', 'turkey': 'try', 'türkiye': 'try',
  'tt': 'ttd', 'trinidad and tobago': 'ttd',
  'tv': 'aud', 'tuvalu': 'aud',
  'tw': 'twd', 'taiwan': 'twd',
  'tz': 'tzs', 'tanzania': 'tzs',
  'ua': 'uah', 'ukraine': 'uah',
  'ug': 'ugx', 'uganda': 'ugx',
  'us': 'usd', 'usa': 'usd', 'united states': 'usd', 'united states of america': 'usd',
  'uy': 'uyu', 'uruguay': 'uyu',
  'uz': 'uzs', 'uzbekistan': 'uzs',
  'va': 'eur', 'vatican city': 'eur',
  'vc': 'xcd', 'saint vincent and the grenadines': 'xcd',
  've': 'ves', 'venezuela': 'ves',
  'vn': 'vnd', 'vietnam': 'vnd', 'viet nam': 'vnd',
  'vu': 'vuv', 'vanuatu': 'vuv',
  'ws': 'wst', 'samoa': 'wst',
  'ye': 'yer', 'yemen': 'yer',
  'za': 'zar', 'south africa': 'zar',
  'zm': 'zmw', 'zambia': 'zmw',
  'zw': 'zwl', 'zimbabwe': 'zwl',
};

/// ISO 3166-1 alpha-3 country codes → alpha-2 for [currencyFromCountry] lookup.
const Map<String, String> _iso3166Alpha3ToAlpha2 = {
  'che': 'ch',
  'gbr': 'gb',
  'deu': 'de',
  'fra': 'fr',
  'ita': 'it',
  'esp': 'es',
  'usa': 'us',
  'fin': 'fi',
  'swe': 'se',
  'nor': 'no',
  'dnk': 'dk',
  'nld': 'nl',
  'bel': 'be',
  'aut': 'at',
  'prt': 'pt',
  'pol': 'pl',
  'cze': 'cz',
  'hun': 'hu',
  'rou': 'ro',
  'bgr': 'bg',
  'hrv': 'hr',
  'grc': 'gr',
  'irl': 'ie',
  'lux': 'lu',
  'mlt': 'mt',
  'cyp': 'cy',
  'svk': 'sk',
  'svn': 'si',
  'est': 'ee',
  'lva': 'lv',
  'ltu': 'lt',
};

/// Mistaken alpha-3 country codes (or other 3-letter junk) → ISO 4217 for Stripe.
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
/// Parity with web: trim, strip zero-width chars, alias by full key or letters-only (e.g. `c h e` → chf).
String normalizeStripeCurrencyCode(String raw) {
  var t = raw.trim();
  if (t.isEmpty) return 'eur';
  t = t.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
  final key = t.toLowerCase();
  final lettersOnly = key.replaceAll(RegExp(r'[^a-z]'), '');
  return _stripeCurrencyAliases[key] ?? _stripeCurrencyAliases[lettersOnly] ?? key;
}

/// ISO 4217 code for UI labels (e.g. mistaken `che` → `CHF`). Same alias map as Stripe.
String normalizeDisplayCurrencyCode(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return 'EUR';
  return normalizeStripeCurrencyCode(t).toUpperCase();
}

/// Lowercase ISO 4217 from [event.country] (name, alpha-2, or mistaken alpha-3 like `CHE` → ch).
/// Uses [_countryToCurrency] (same intent as web country→currency, without npm `currency-codes` ordering bugs).
String currencyFromCountry(String? country) {
  if (country == null || country.isEmpty) return 'eur';
  final key = country.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  final alpha2 = _iso3166Alpha3ToAlpha2[key];
  final resolved = alpha2 != null
      ? (_countryToCurrency[alpha2] ?? 'eur')
      : (_countryToCurrency[key] ?? 'eur');
  return normalizeStripeCurrencyCode(resolved);
}

/// Display symbol (or ISO code) from a raw currency field — parity with web [getCurrencySymbolFromIsoCode].
/// Prefer when ticket/manifest `currency` is known; use [currencySymbol] with [currencyFromCountry] for country-only APIs.
String currencySymbolFromIsoCode(String? raw) {
  final code = normalizeDisplayCurrencyCode(raw ?? '');
  try {
    final f = NumberFormat.currency(locale: 'en_US', name: code);
    return f.currencySymbol;
  } catch (_) {
    return currencySymbol(code);
  }
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

/// Amount first, then ISO 4217 code (web parity: `76.000 CHF`, not prefix symbol).
String formatPrice(double amount, String currencyCode) {
  final normalizedCode = normalizeStripeCurrencyCode(currencyCode);
  final display = normalizeDisplayCurrencyCode(currencyCode);
  final code = normalizedCode.toLowerCase();
  const zeroDecimals = {'jpy', 'krw', 'vnd', 'cny', 'clp', 'kpw', 'pyg'};
  if (zeroDecimals.contains(code)) {
    return '${amount.toStringAsFixed(0)} $display';
  }
  final truncated = _truncateFixed(amount, 3);
  return '${truncated.toStringAsFixed(3)} $display';
}

/// Format with fixed decimals; suffix ISO code (e.g. `27.000 EUR`).
String formatPriceWithDecimals(double amount, String currencyCode, int decimals) {
  final display = normalizeDisplayCurrencyCode(currencyCode);
  final truncated = _truncateFixed(amount, decimals);
  return '${truncated.toStringAsFixed(decimals)} $display';
}

double _pow10(int n) {
  double r = 1.0;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}

/// Truncate to fixed decimals while guarding against float dust
/// (e.g. 17.024999999 -> 17.025 for 3 decimals).
double _truncateFixed(double amount, int decimals) {
  final factor = _pow10(decimals);
  final scaled = amount * factor;
  final epsilon = amount >= 0 ? 1e-9 : -1e-9;
  return (scaled + epsilon).truncate() / factor;
}
