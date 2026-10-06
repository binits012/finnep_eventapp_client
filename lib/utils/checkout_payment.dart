import 'base_price_tax.dart';
import 'country_iso.dart';
import 'money.dart';
import 'seat_pricing.dart';

String formatTaxRateDisplay(num rate) {
  final s = roundMoney(rate).toStringAsFixed(2);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

bool isEntertainmentTaxOnBase(double? entertainmentTax) =>
    (entertainmentTax ?? 0) > 0;

class CheckoutPricingSnapshot {
  const CheckoutPricingSnapshot({
    required this.line,
    required this.total,
    required this.totalEntertainmentTaxAmount,
    required this.baseTaxPct,
    required this.serviceTaxRate,
  });

  final TicketLinePricing line;
  final double total;
  final double totalEntertainmentTaxAmount;
  final double baseTaxPct;
  final double serviceTaxRate;
}

CheckoutPricingSnapshot resolveCheckoutPricing({
  required double price,
  double serviceFee = 0,
  required double vat,
  double? entertainmentTax,
  double serviceTax = 0,
  double orderFee = 0,
  int quantity = 1,
  double? total,
  double? totalBasePrice,
  double? totalServiceFee,
  double? totalVatAmount,
  double? totalEntertainmentTaxAmount,
  double? entertainmentTaxAmount,
  double? totalServiceTaxAmount,
  double? serviceTaxAmount,
  double? orderFeeServiceTax,
  bool hasSeatTotals = false,
}) {
  final baseTaxPct = basePriceTaxPercent(vat, entertainmentTax);
  final serviceTaxRate = serviceTax;
  final qty = quantity < 1 ? 1 : quantity;

  final line = computeTicketLinePricing(
    basePrice: price,
    serviceFee: serviceFee,
    vatRatePercent: baseTaxPct,
    serviceTaxRatePercent: serviceTaxRate,
    orderFee: orderFee,
    quantity: qty,
  );

  if (hasSeatTotals &&
      totalBasePrice != null &&
      totalServiceFee != null) {
    final tb = roundMoney(totalBasePrice);
    final tsf = roundMoney(totalServiceFee);
    final totalVat = roundMoney(
      totalVatAmount ??
          totalEntertainmentTaxAmount ??
          entertainmentTaxAmount ??
          line.totalVatAmount,
    );
    final totalEnt = roundMoney(
      totalEntertainmentTaxAmount ?? entertainmentTaxAmount ?? totalVat,
    );
    final totalSvcTax = roundMoney(
      totalServiceTaxAmount ?? serviceTaxAmount ?? line.totalServiceTaxAmount,
    );
    final of = roundMoney(orderFee);
    final ofst = roundMoney(orderFeeServiceTax ?? line.orderFeeServiceTax);
    final computedTotal = roundMoney(
      total ??
          moneyAdd([tb, tsf, totalEnt, totalSvcTax, of, ofst]),
    );
    return CheckoutPricingSnapshot(
      line: line.copyWith(
        totalBasePrice: tb,
        totalServiceFee: tsf,
        totalVatAmount: totalVat,
        totalServiceTaxAmount: totalSvcTax,
        orderFee: of,
        orderFeeServiceTax: ofst,
        total: computedTotal,
      ),
      total: computedTotal,
      totalEntertainmentTaxAmount: totalEnt,
      baseTaxPct: baseTaxPct,
      serviceTaxRate: serviceTaxRate,
    );
  }

  final computedTotal = roundMoney(total ?? line.total);
  return CheckoutPricingSnapshot(
    line: line,
    total: computedTotal,
    totalEntertainmentTaxAmount: line.totalVatAmount,
    baseTaxPct: baseTaxPct,
    serviceTaxRate: serviceTaxRate,
  );
}

extension _TicketLinePricingCopy on TicketLinePricing {
  TicketLinePricing copyWith({
    double? totalBasePrice,
    double? totalServiceFee,
    double? totalVatAmount,
    double? totalServiceTaxAmount,
    double? orderFee,
    double? orderFeeServiceTax,
    double? total,
  }) {
    return TicketLinePricing(
      basePrice: basePrice,
      serviceFee: serviceFee,
      perUnitSubtotal: perUnitSubtotal,
      perUnitVat: perUnitVat,
      perUnitServiceTax: perUnitServiceTax,
      perUnitTotal: perUnitTotal,
      totalBasePrice: totalBasePrice ?? this.totalBasePrice,
      totalServiceFee: totalServiceFee ?? this.totalServiceFee,
      totalVatAmount: totalVatAmount ?? this.totalVatAmount,
      totalServiceTaxAmount: totalServiceTaxAmount ?? this.totalServiceTaxAmount,
      orderFee: orderFee ?? this.orderFee,
      orderFeeServiceTax: orderFeeServiceTax ?? this.orderFeeServiceTax,
      total: total ?? this.total,
    );
  }
}

Map<String, dynamic> buildPaymentMetadata({
  required String eventId,
  required String ticketId,
  required String email,
  required int quantity,
  required String eventName,
  required String ticketName,
  required String merchantId,
  required String externalMerchantId,
  required String nonce,
  required double price,
  double serviceFee = 0,
  required double vat,
  double? entertainmentTax,
  double serviceTax = 0,
  double orderFee = 0,
  String? country,
  bool marketingOptIn = false,
  double? totalAmountOverride,
  bool hasSeats = false,
  String? couponCode,
  String? couponId,
  double? couponDiscountAmount,
  double? catalogBaseSubtotalPreCoupon,
  SeatCheckoutSummary? seatPricingConfigurationTotals,
}) {
  final pricing = resolveCheckoutPricing(
    price: price,
    serviceFee: serviceFee,
    vat: vat,
    entertainmentTax: entertainmentTax,
    serviceTax: serviceTax,
    orderFee: orderFee,
    quantity: quantity,
    total: totalAmountOverride,
  );
  final line = pricing.line;
  final total = pricing.total;
  final baseTaxPct = pricing.baseTaxPct;
  final serviceTaxRate = pricing.serviceTaxRate;

  final metadata = <String, dynamic>{
    'eventId': eventId,
    'ticketId': ticketId,
    'email': email,
    'quantity': quantity.toString(),
    'eventName': eventName,
    'ticketName': ticketName,
    'merchantId': merchantId,
    'externalMerchantId': externalMerchantId,
    'nonce': nonce,
    'basePrice': moneyToMetadataString(price),
    'subtotal': moneyToMetadataString(line.totalBasePrice),
    'serviceFee': moneyToMetadataString(serviceFee),
    'totalServiceFee': moneyToMetadataString(line.totalServiceFee),
    'serviceTax': formatTaxRateDisplay(serviceTaxRate),
    'serviceTaxAmount': moneyToMetadataString(line.totalServiceTaxAmount),
    'vatRate': formatTaxRateDisplay(baseTaxPct),
    'vatAmount': moneyToMetadataString(line.totalVatAmount),
    'orderFee': moneyToMetadataString(line.orderFee),
    'orderFeeServiceTax': moneyToMetadataString(line.orderFeeServiceTax),
    'totalOrderFee': moneyToMetadataString(line.orderFee),
    'totalAmount': moneyToMetadataString(total),
    'perUnitSubtotal': moneyToMetadataString(line.perUnitSubtotal),
    'perUnitTotal': moneyToMetadataString(line.perUnitTotal),
    'totalBasePrice': moneyToMetadataString(line.totalBasePrice),
    'totalVatAmount': moneyToMetadataString(line.totalVatAmount),
    'country': (country == null || country.trim().isEmpty)
        ? defaultEventCountryName
        : country.trim(),
    'marketingOptIn': marketingOptIn,
    'locale': 'en-US',
  };

  final cc = couponCode?.trim() ?? '';
  if (cc.isNotEmpty) {
    metadata['couponCode'] = cc.toUpperCase();
    final cid = couponId?.trim() ?? '';
    final discRaw = couponDiscountAmount;
    if (cid.isNotEmpty && discRaw != null && discRaw > 0) {
      metadata['couponId'] = cid;
      metadata['couponDiscountAmount'] =
          moneyToMetadataString(roundMoney(discRaw));
    }
    if (discRaw != null &&
        discRaw > 0 &&
        catalogBaseSubtotalPreCoupon != null &&
        catalogBaseSubtotalPreCoupon > 0) {
      metadata['catalogBaseSubtotal'] =
          moneyToMetadataString(roundMoney(catalogBaseSubtotalPreCoupon));
    }
  }

  final cfg = seatPricingConfigurationTotals;
  if (cfg != null) {
    final seatTaxRateDisplay =
        cfg.entertainmentTaxRate != 0 ? cfg.entertainmentTaxRate : cfg.vatRate;

    metadata['subtotal'] = moneyToMetadataString(cfg.totalBasePrice);
    metadata['totalBasePrice'] = moneyToMetadataString(cfg.totalBasePrice);
    metadata['totalServiceFee'] = moneyToMetadataString(cfg.totalServiceFee);
    metadata['totalVatAmount'] =
        moneyToMetadataString(cfg.totalEntertainmentTaxAmount);
    metadata['vatAmount'] =
        moneyToMetadataString(cfg.totalEntertainmentTaxAmount);
    metadata['vatRate'] = formatTaxRateDisplay(seatTaxRateDisplay);
    metadata['serviceTax'] = formatTaxRateDisplay(serviceTaxRate);
    metadata['serviceTaxAmount'] =
        moneyToMetadataString(cfg.totalServiceTaxAmount);
    metadata['totalServiceTaxAmount'] =
        moneyToMetadataString(cfg.totalServiceTaxAmount);
    metadata['orderFee'] = moneyToMetadataString(cfg.orderFee);
    metadata['orderFeeServiceTax'] =
        moneyToMetadataString(cfg.orderFeeServiceTax);
    metadata['totalOrderFee'] = moneyToMetadataString(cfg.orderFee);
    metadata['totalAmount'] = moneyToMetadataString(cfg.total);

    if (seatTaxRateDisplay > 0) {
      metadata['entertainmentTax'] =
          formatTaxRateDisplay(seatTaxRateDisplay);
      metadata['entertainmentTaxAmount'] =
          moneyToMetadataString(cfg.totalEntertainmentTaxAmount);
      if (hasSeats) {
        metadata['totalEntertainmentTaxAmount'] =
            moneyToMetadataString(cfg.totalEntertainmentTaxAmount);
      }
    }
  } else if (isEntertainmentTaxOnBase(entertainmentTax)) {
    metadata['entertainmentTax'] = formatTaxRateDisplay(entertainmentTax!);
    metadata['entertainmentTaxAmount'] =
        moneyToMetadataString(pricing.totalEntertainmentTaxAmount);
    if (hasSeats) {
      metadata['totalEntertainmentTaxAmount'] =
          moneyToMetadataString(pricing.totalEntertainmentTaxAmount);
    }
  }

  return metadata;
}

/// Per-unit catalog base after coupon (GA / non-seat-override lines).
double catalogUnitBaseAfterCoupon({
  required double unitBasePrice,
  required int quantity,
  String? couponCode,
  double? couponDiscountAmount,
}) {
  final code = couponCode?.trim() ?? '';
  final discountAmt = couponDiscountAmount;
  if (code.isEmpty || discountAmt == null || discountAmt <= 0) {
    return unitBasePrice;
  }

  final catalogSubtotal = roundMoney(unitBasePrice * quantity);
  final cappedDiscount =
      discountAmt > catalogSubtotal ? catalogSubtotal : discountAmt;
  final discountedSubtotal = roundMoney(catalogSubtotal - cappedDiscount);
  if (quantity < 1) return unitBasePrice;
  return roundMoney(discountedSubtotal / quantity);
}

/// Pre-coupon catalog base subtotal for payment metadata when a coupon applies.
double? catalogBaseSubtotalBeforeCoupon({
  required double unitBasePrice,
  required int quantity,
  String? couponCode,
  double? couponDiscountAmount,
}) {
  final code = couponCode?.trim() ?? '';
  final discountAmt = couponDiscountAmount;
  if (code.isEmpty || discountAmt == null || discountAmt <= 0) return null;
  return roundMoney(unitBasePrice * quantity);
}
