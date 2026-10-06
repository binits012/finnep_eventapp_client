import 'package:flutter_test/flutter_test.dart';
import 'package:okazzo/config/app_config.dart';

void main() {
  group('appleMerchantIdentifierForRegion', () {
    test('maps each store flavor to its Stripe merchant ID', () {
      expect(
        appleMerchantIdentifierForRegion('eu'),
        'merchant.eu.finnep.okazzo',
      );
      expect(
        appleMerchantIdentifierForRegion('AU'),
        'merchant.au.finnep.okazzo',
      );
    });

    test('returns null when the region is missing', () {
      expect(appleMerchantIdentifierForRegion(null), isNull);
      expect(appleMerchantIdentifierForRegion(''), isNull);
      expect(appleMerchantIdentifierForRegion('us'), isNull);
    });
  });
}
