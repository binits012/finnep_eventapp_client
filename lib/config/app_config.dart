import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Per-build market for API `x-country-code`: set `MARKET_COUNTRY_CODE` (alpha-2).
/// `APP_REGION=au` implies `AU`; EU region has no implicit country — set env explicitly.
const Map<String, String> _regionBaseUrls = <String, String>{
  'au': 'https://okazzo.com.au/front',
  'eu': 'https://okazzo.eu/front',
};

String get apiBaseUrl {
  final region = (dotenv.env['APP_REGION'] ?? '').trim().toLowerCase();
  final configuredBaseUrl = (dotenv.env['API_BASE_URL'] ?? '').trim();
  final regionBaseUrl = _regionBaseUrls[region];

  String baseUrl;
  if (configuredBaseUrl.isNotEmpty) {
    baseUrl = configuredBaseUrl.startsWith('http')
        ? configuredBaseUrl
        : 'https://$configuredBaseUrl';
  } else {
    baseUrl = regionBaseUrl ?? _regionBaseUrls['au']!;
  }

  if (Platform.isAndroid && baseUrl.contains('localhost')) {
    baseUrl = baseUrl.replaceAll('localhost', '10.0.2.2');
  }

  return baseUrl;
}

/// Consumer site origin (no `/front`) for static pages: /contact, /privacy, /terms.
/// Override with `PUBLIC_SITE_BASE_URL` in `.env` if needed; otherwise derived from [apiBaseUrl].
String get publicSiteBaseUrl {
  final configured = (dotenv.env['PUBLIC_SITE_BASE_URL'] ?? '').trim();
  if (configured.isNotEmpty) {
    return configured.startsWith('http') ? configured : 'https://$configured';
  }
  var base = apiBaseUrl;
  if (base.endsWith('/front')) {
    base = base.substring(0, base.length - '/front'.length);
  } else if (base.endsWith('/front/')) {
    base = base.substring(0, base.length - '/front/'.length);
  }
  if (Platform.isAndroid && base.contains('localhost')) {
    base = base.replaceAll('localhost', '10.0.2.2');
  }
  return base;
}

String get publicContactUrl => '$publicSiteBaseUrl/contact';
String get publicPrivacyUrl => '$publicSiteBaseUrl/privacy';
String get publicTermsUrl => '$publicSiteBaseUrl/terms';

String get stripePublishableKey {
  const fromDefine = String.fromEnvironment('STRIPE_PUBLISHABLE_KEY', defaultValue: '');
  if (fromDefine.isNotEmpty) {
    return fromDefine;
  }
  return dotenv.env['STRIPE_PUBLISHABLE_KEY'] ?? '';
}

String get stripeMerchantDisplayName =>
    dotenv.env['STRIPE_MERCHANT_DISPLAY_NAME'] ?? 'Okazzo';

/// ISO 3166-1 alpha-2 of this build's Stripe account. Google Pay and Apple Pay
/// both require this, not the event country.
String get stripeMerchantCountryCode {
  final value = (dotenv.env['STRIPE_MERCHANT_COUNTRY_CODE'] ?? 'FI')
      .trim()
      .toUpperCase();
  if (value.length == 2) return value;
  return 'FI';
}

const String stripeAppleMerchantIdEu = 'merchant.eu.finnep.okazzo';
const String stripeAppleMerchantIdAu = 'merchant.au.finnep.okazzo';

/// Apple Pay merchant ID for this build. EU and AU are separate Stripe accounts,
/// so each flavor must use the merchant ID registered on that account.
String? appleMerchantIdentifierForRegion(String? region) {
  switch ((region ?? '').trim().toLowerCase()) {
    case 'au':
      return stripeAppleMerchantIdAu;
    case 'eu':
      return stripeAppleMerchantIdEu;
    default:
      return null;
  }
}

/// iOS only. Prefers [APP_REGION] from the env file (same account as the Stripe key),
/// then the Flutter flavor.
String? get stripeAppleMerchantIdentifier {
  if (!Platform.isIOS) return null;
  final fromEnv = appleMerchantIdentifierForRegion(dotenv.env['APP_REGION']);
  if (fromEnv != null) return fromEnv;
  return appleMerchantIdentifierForRegion(appFlavor);
}
