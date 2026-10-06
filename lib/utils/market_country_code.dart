import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../config/app_config.dart';

/// Known production hostnames → market code (parity with web `marketCountryCode.ts`).
/// Generic TLDs (e.g. okazzo.eu) omit the header unless env override is set.
const Map<String, String> _hostToMarket = {
  'okazzo.com.au': 'AU',
  'www.okazzo.com.au': 'AU',
  'okazzo.fi': 'FI',
  'www.okazzo.fi': 'FI',
  'okazzo.se': 'SE',
  'www.okazzo.se': 'SE',
  'okazzo.no': 'NO',
  'www.okazzo.no': 'NO',
  'okazzo.dk': 'DK',
  'www.okazzo.dk': 'DK',
};

String _normalizeHost(String? host) {
  if (host == null || host.trim().isEmpty) return '';
  return host.trim().toLowerCase().split(':').first.replaceAll(RegExp(r'\.$'), '');
}

String? _envMarketOverride() {
  final explicit = (dotenv.env['MARKET_COUNTRY_CODE'] ?? '').trim().toUpperCase();
  if (explicit.length == 2 && RegExp(r'^[A-Z]{2}$').hasMatch(explicit)) {
    return explicit;
  }
  final legacy = (dotenv.env['NEXT_PUBLIC_MARKET_COUNTRY'] ?? '')
      .trim()
      .toUpperCase();
  if (legacy.length == 2 && RegExp(r'^[A-Z]{2}$').hasMatch(legacy)) {
    return legacy;
  }
  return null;
}

String? _marketFromConfiguredSiteHost() {
  for (final base in [publicSiteBaseUrl, apiBaseUrl]) {
    try {
      final host = _normalizeHost(Uri.parse(base).host);
      final market = _hostToMarket[host];
      if (market != null) return market;
    } catch (_) {
      // ignore malformed URL
    }
  }
  return null;
}

/// ISO 3166-1 alpha-2 for the `x-country-code` header on public API calls.
///
/// Priority (aligned with web):
/// 1. [MARKET_COUNTRY_CODE] or [NEXT_PUBLIC_MARKET_COUNTRY] in `.env`
/// 2. [APP_REGION]=`au` → `AU`
/// 3. Hostname from [publicSiteBaseUrl] / [apiBaseUrl] (e.g. okazzo.dk → DK)
/// 4. Otherwise no header (okazzo.eu cluster)
String? resolveMarketCountryCodeForApi() {
  final fromEnv = _envMarketOverride();
  if (fromEnv != null) return fromEnv;

  final region = (dotenv.env['APP_REGION'] ?? '').trim().toLowerCase();
  if (region == 'au') return 'AU';

  return _marketFromConfiguredSiteHost();
}
