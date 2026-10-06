import 'package:flutter_test/flutter_test.dart';
import 'package:okazzo/utils/country_iso.dart';
import 'package:okazzo/utils/currency.dart';

void main() {
  group('getCountryCode (web parity)', () {
    test('resolves common event country names', () {
      expect(getCountryCode('Finland'), 'FI');
      expect(getCountryCode('Denmark'), 'DK');
      expect(getCountryCode('Germany'), 'DE');
      expect(getCountryCode('Ireland'), 'IE');
      expect(getCountryCode('United States'), 'US');
      expect(getCountryCode('united kingdom'), 'GB');
    });

    test('resolves alpha-2 and alpha-3 codes', () {
      expect(getCountryCode('DK'), 'DK');
      expect(getCountryCode('CHE'), 'CH');
    });
  });

  group('currencyFromCountry (web parity)', () {
    test('maps countries to ISO 4217', () {
      expect(currencyFromCountry('Finland'), 'eur');
      expect(currencyFromCountry('Denmark'), 'dkk');
      expect(currencyFromCountry('Switzerland'), 'chf');
      expect(currencyFromCountry('Australia'), 'aud');
    });

    test('defaults missing country to Finland/EUR', () {
      expect(currencyFromCountry(null), 'eur');
      expect(currencyFromCountry(''), 'eur');
    });
  });
}
