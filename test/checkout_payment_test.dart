import 'package:flutter_test/flutter_test.dart';
import 'package:okazzo/utils/checkout_payment.dart';
import 'package:okazzo/utils/money.dart';
import 'package:okazzo/utils/ticket_pricing.dart';

void main() {
  test('GA coupon metadata total matches discounted charge math', () {
    const unitBase = 20.0;
    const quantity = 2;
    const discount = 10.0;
    const vat = 24.0;

    final unitAfter = catalogUnitBaseAfterCoupon(
      unitBasePrice: unitBase,
      quantity: quantity,
      couponCode: 'SAVE10',
      couponDiscountAmount: discount,
    );
    expect(unitAfter, 15.0);

    final line = computeTicketLinePricing(
      basePrice: unitAfter,
      vatRatePercent: vat,
      quantity: quantity,
    );

    final metadata = buildPaymentMetadata(
      eventId: 'event-1',
      ticketId: 'ticket-1',
      email: 'buyer@example.com',
      quantity: quantity,
      eventName: 'Test Event',
      ticketName: 'General Admission',
      merchantId: 'merchant-1',
      externalMerchantId: 'ext-1',
      nonce: 'nonce-1',
      price: unitAfter,
      vat: vat,
      couponCode: 'SAVE10',
      couponId: 'coupon-1',
      couponDiscountAmount: discount,
      catalogBaseSubtotalPreCoupon: catalogBaseSubtotalBeforeCoupon(
        unitBasePrice: unitBase,
        quantity: quantity,
        couponCode: 'SAVE10',
        couponDiscountAmount: discount,
      ),
    );

    expect(metadata['totalAmount'], moneyToMetadataString(line.total));
    expect(metadata['catalogBaseSubtotal'], '40.00');
    expect(metadata['basePrice'], '15.00');
  });
}
