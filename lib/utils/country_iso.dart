import 'package:country/country.dart';

/// Default when event country is missing (web: `checkout.country || 'Finland'`).
const String defaultEventCountryName = 'Finland';

String _normalizeCountryKey(String raw) =>
    raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

String _titleCaseCountry(String raw) {
  return raw
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

Map<String, String>? _countryNameToAlpha2;
Map<String, Country>? _countryByAlpha2;

void _ensureCountryLookups() {
  if (_countryNameToAlpha2 != null) return;

  final nameToAlpha2 = <String, String>{};
  final byAlpha2 = <String, Country>{};

  void registerName(String? name, String alpha2) {
    if (name == null || name.trim().isEmpty) return;
    final key = _normalizeCountryKey(name);
    nameToAlpha2.putIfAbsent(key, () => alpha2);
    final titled = _normalizeCountryKey(_titleCaseCountry(name));
    nameToAlpha2.putIfAbsent(titled, () => alpha2);
  }

  for (final c in Countries.values) {
    byAlpha2[c.alpha2.toUpperCase()] = c;
    registerName(c.isoShortName, c.alpha2);
    registerName(c.isoLongName, c.alpha2);
    registerName(c.isoShortNameLowerCase, c.alpha2);
    for (final alt in c.unofficialNames) {
      registerName(alt, c.alpha2);
    }
  }

  _countryNameToAlpha2 = nameToAlpha2;
  _countryByAlpha2 = byAlpha2;
}

/// ISO 3166-1 alpha-2 from a country name or code (parity with web `getCountryCode`).
String? getCountryCode(String? countryName) {
  if (countryName == null || countryName.trim().isEmpty) return null;
  _ensureCountryLookups();

  final trimmed = countryName.trim();
  final key = _normalizeCountryKey(trimmed);

  if (RegExp(r'^[a-z]{2}$').hasMatch(key)) {
    final alpha2 = key.toUpperCase();
    if (_countryByAlpha2!.containsKey(alpha2)) return alpha2;
  }

  if (RegExp(r'^[a-z]{3}$').hasMatch(key)) {
    final alpha3 = key.toUpperCase();
    for (final c in Countries.values) {
      if (c.alpha3.toUpperCase() == alpha3) return c.alpha2;
    }
  }

  return _countryNameToAlpha2![key] ??
      _countryNameToAlpha2![_normalizeCountryKey(_titleCaseCountry(trimmed))];
}

Country? _countryForName(String? countryName) {
  final code = getCountryCode(countryName);
  if (code == null) return null;
  _ensureCountryLookups();
  return _countryByAlpha2![code.toUpperCase()];
}

/// Primary ISO 4217 for a country name (parity with web `getCurrencyCode`).
String getCurrencyCodeFromCountry(String countryName) {
  final country = _countryForName(countryName);
  if (country == null) return 'EUR';
  return country.currencyCode.toUpperCase();
}
