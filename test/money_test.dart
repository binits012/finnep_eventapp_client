import 'package:flutter_test/flutter_test.dart';
import 'package:okazzo/utils/money.dart';
import 'package:okazzo/utils/seat_catalog_coupon.dart';
import 'package:okazzo/utils/seat_pricing.dart';
import 'package:okazzo/utils/ticket_pricing.dart';

void main() {
  test('roundMoney uses 2 decimals', () {
    expect(roundMoney(11.345), 11.35);
    expect(roundMoney(102.149), 102.15);
  });

  test('10 EUR base + 13.5% VAT × 9 = 102.15', () {
    final perUnit = calculateTicketPrice(
      price: 10,
      vat: 13.5,
      serviceFee: 0,
      orderFee: 0,
    );
    expect(perUnit.vatAmountPerTicket, 1.35);
    expect(perUnit.finalPricePerTicket, 11.35);

    final line = computeTicketLinePricing(
      basePrice: 10,
      vatRatePercent: 13.5,
      quantity: 9,
    );
    expect(line.total, 102.15);
  });

  test('ticket_info seat summary sums per-seat lines', () {
    final line = computeSeatLinePrice(basePrice: 10, entertainmentTax: 13.5);
    final summary = computeTicketInfoSeatSummary(
      lines: List.generate(9, (_) => line),
      orderFee: 0,
      serviceTaxRatePercent: 0,
      vatRatePercent: 13.5,
    );
    expect(summary.total, 102.15);
  });

  test('ticket_info seated coupon discounts base only', () {
    final line = computeTicketLinePricing(
      basePrice: 100,
      serviceFee: 10,
      vatRatePercent: 10,
      serviceTaxRatePercent: 20,
      orderFee: 5,
    );

    final discounted = discountedSeatCheckoutTotalFromPayload(
      totalAmountOverride: line.total,
      orderFeeRoot: 5,
      serviceFeeRoot: 10,
      vatRatePercent: 10,
      orderServiceTaxRatePercent: 20,
      seatTickets: [
        {'price': 100, 'totalPerTicket': 122},
      ],
      couponDiscountOnCatalogSum: 10,
    );

    expect(discounted, 117);
  });

  test('pricing configuration seated coupon discounts base only', () {
    final summary = computePricingConfigSeatSummary(
      lines: [(basePrice: 100.0, serviceFee: 10.0)],
      taxRatePercent: 10,
      serviceTaxRatePercent: 20,
      orderFee: 5,
    );

    final discounted = discountedSeatCheckoutTotalFromPayload(
      totalAmountOverride: summary.total,
      orderFeeRoot: 5,
      serviceFeeRoot: 10,
      vatRatePercent: 10,
      orderServiceTaxRatePercent: 20,
      seatTickets: [
        {
          'pricing': {
            'basePrice': 100,
            'serviceFee': 10,
            'tax': 10,
            'serviceTax': 20,
            'orderFee': 5,
          },
        },
      ],
      couponDiscountOnCatalogSum: 10,
    );

    expect(discounted, 117);
  });
}
