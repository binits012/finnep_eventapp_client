import 'dart:convert';

import 'api_client.dart';
import '../utils/checkout_payment.dart';
import '../utils/currency.dart';
import '../utils/seat_catalog_coupon.dart';
import '../utils/seat_pricing.dart';

const _chars = 'abcdefghijklmnopqrstuvwxyz0123456789';

String _generateNonce() {
  final r = List.generate(32, (i) => _chars[(DateTime.now().microsecondsSinceEpoch + i) % _chars.length]);
  return r.join();
}

({double basePrice, double? catalogBaseSubtotalPreCoupon}) _metadataPricingInputs({
  required double basePrice,
  required int quantity,
  required bool hasSeats,
  double? totalAmountOverride,
  String? couponCode,
  double? couponDiscountAmount,
  double? catalogBaseSubtotalPreCoupon,
}) {
  final gaCoupon = totalAmountOverride == null &&
      !hasSeats &&
      (couponCode?.trim().isNotEmpty ?? false) &&
      couponDiscountAmount != null &&
      couponDiscountAmount > 0;

  if (!gaCoupon) {
    return (
      basePrice: basePrice,
      catalogBaseSubtotalPreCoupon: catalogBaseSubtotalPreCoupon,
    );
  }

  return (
    basePrice: catalogUnitBaseAfterCoupon(
      unitBasePrice: basePrice,
      quantity: quantity,
      couponCode: couponCode,
      couponDiscountAmount: couponDiscountAmount,
    ),
    catalogBaseSubtotalPreCoupon: catalogBaseSubtotalPreCoupon ??
        catalogBaseSubtotalBeforeCoupon(
          unitBasePrice: basePrice,
          quantity: quantity,
          couponCode: couponCode,
          couponDiscountAmount: couponDiscountAmount,
        ),
  );
}

Future<Map<String, dynamic>> createPaymentIntent({
  required int amountCents,
  required String currency,
  required String eventId,
  required String merchantId,
  required String externalMerchantId,
  required String email,
  required int quantity,
  required String ticketId,
  required String eventName,
  required String ticketName,
  required double basePrice,
  required double serviceFee,
  double serviceTaxRate = 0,
  double orderFee = 0,
  required double vatRate,
  double? entertainmentTax,
  String? sessionId,
  List<String>? placeIds,
  List<Map<String, dynamic>>? sectionSelections,
  List<Map<String, dynamic>>? seatTickets,
  String? country,
  String? fullName,
  double? totalAmountOverride,
  bool marketingOptIn = false,
  String? couponCode,
  String? couponId,
  double? couponDiscountAmount,
  Map<String, dynamic>? registrationAnswers,
}) async {
  final hasSeats = (placeIds != null && placeIds.isNotEmpty) ||
      (seatTickets != null && seatTickets.isNotEmpty);

  SeatCheckoutSummary? seatCfgTotals;
  double? catalogBasePre;
  final st = seatTickets;
  if (st != null && st.isNotEmpty && seatTicketsUsePricingConfiguration(st)) {
    seatCfgTotals = pricingConfigSeatSummaryFromSeatTickets(st);
    final disc = couponDiscountAmount;
    if (disc != null && disc > 0) {
      catalogBasePre = seatTicketsCatalogSum(st);
      if (seatCfgTotals != null) {
        seatCfgTotals = applyCouponToSeatSummaryTotals(
          totals: seatCfgTotals,
          discountAmount: disc,
        );
      }
    }
  }

  final pricingInputs = _metadataPricingInputs(
    basePrice: basePrice,
    quantity: quantity,
    hasSeats: hasSeats,
    totalAmountOverride: totalAmountOverride,
    couponCode: couponCode,
    couponDiscountAmount: couponDiscountAmount,
    catalogBaseSubtotalPreCoupon: catalogBasePre,
  );

  final metadata = buildPaymentMetadata(
    eventId: eventId,
    ticketId: ticketId,
    email: email,
    quantity: quantity,
    eventName: eventName,
    ticketName: ticketName,
    merchantId: merchantId,
    externalMerchantId: externalMerchantId,
    nonce: _generateNonce(),
    price: pricingInputs.basePrice,
    serviceFee: serviceFee,
    vat: vatRate,
    entertainmentTax: entertainmentTax,
    serviceTax: serviceTaxRate,
    orderFee: orderFee,
    country: country,
    marketingOptIn: marketingOptIn,
    totalAmountOverride: totalAmountOverride,
    hasSeats: hasSeats,
    couponCode: couponCode,
    couponId: couponId,
    couponDiscountAmount: couponDiscountAmount,
    catalogBaseSubtotalPreCoupon: pricingInputs.catalogBaseSubtotalPreCoupon,
    seatPricingConfigurationTotals: seatCfgTotals,
  );
  if (sessionId != null) metadata['sessionId'] = sessionId;
  if (placeIds != null && placeIds.isNotEmpty) metadata['placeIds'] = jsonEncode(placeIds);
  if (sectionSelections != null && sectionSelections.isNotEmpty) {
    metadata['sectionSelections'] = jsonEncode(sectionSelections);
  }
  if (seatTickets != null && seatTickets.isNotEmpty) {
    metadata['seatTickets'] = jsonEncode(seatTickets);
  }
  if (fullName != null && fullName.trim().isNotEmpty) {
    metadata['fullName'] = fullName.trim();
  }

  final response = await apiPost('/create-payment-intent', body: {
    'amount': amountCents,
    'currency': normalizeStripeCurrencyCode(currency),
    'paymentProvider': 'stripe',
    'metadata': metadata,
    if (registrationAnswers != null && registrationAnswers.isNotEmpty)
      'registrationAnswers': registrationAnswers,
  });
  throwIfNotOk(response);
  final body = parseJsonBody(response);
  if (body == null) throw ApiException(500, 'No response');
  return body;
}

Future<Map<String, dynamic>> createPaytrailPayment({
  required int amountCents,
  required String currency,
  required String eventId,
  required String merchantId,
  required String externalMerchantId,
  required String email,
  required int quantity,
  required String ticketId,
  required String eventName,
  required String ticketName,
  required double basePrice,
  required double serviceFee,
  double serviceTaxRate = 0,
  double orderFee = 0,
  required double vatRate,
  double? entertainmentTax,
  String? sessionId,
  List<String>? placeIds,
  List<Map<String, dynamic>>? sectionSelections,
  List<Map<String, dynamic>>? seatTickets,
  String? country,
  String? fullName,
  double? totalAmountOverride,
  bool marketingOptIn = false,
  String? couponCode,
  String? couponId,
  double? couponDiscountAmount,
  Map<String, dynamic>? registrationAnswers,
}) async {
  final hasSeats = (placeIds != null && placeIds.isNotEmpty) ||
      (seatTickets != null && seatTickets.isNotEmpty);

  SeatCheckoutSummary? seatCfgTotals;
  double? catalogBasePre;
  final stPt = seatTickets;
  if (stPt != null && stPt.isNotEmpty && seatTicketsUsePricingConfiguration(stPt)) {
    seatCfgTotals = pricingConfigSeatSummaryFromSeatTickets(stPt);
    final disc = couponDiscountAmount;
    if (disc != null && disc > 0) {
      catalogBasePre = seatTicketsCatalogSum(stPt);
      if (seatCfgTotals != null) {
        seatCfgTotals = applyCouponToSeatSummaryTotals(
          totals: seatCfgTotals,
          discountAmount: disc,
        );
      }
    }
  }

  final pricingInputs = _metadataPricingInputs(
    basePrice: basePrice,
    quantity: quantity,
    hasSeats: hasSeats,
    totalAmountOverride: totalAmountOverride,
    couponCode: couponCode,
    couponDiscountAmount: couponDiscountAmount,
    catalogBaseSubtotalPreCoupon: catalogBasePre,
  );

  final metadata = buildPaymentMetadata(
    eventId: eventId,
    ticketId: ticketId,
    email: email,
    quantity: quantity,
    eventName: eventName,
    ticketName: ticketName,
    merchantId: merchantId,
    externalMerchantId: externalMerchantId,
    nonce: _generateNonce(),
    price: pricingInputs.basePrice,
    serviceFee: serviceFee,
    vat: vatRate,
    entertainmentTax: entertainmentTax ?? vatRate,
    serviceTax: serviceTaxRate,
    orderFee: orderFee,
    country: country,
    marketingOptIn: marketingOptIn,
    totalAmountOverride: totalAmountOverride,
    hasSeats: hasSeats,
    couponCode: couponCode,
    couponId: couponId,
    couponDiscountAmount: couponDiscountAmount,
    catalogBaseSubtotalPreCoupon: pricingInputs.catalogBaseSubtotalPreCoupon,
    seatPricingConfigurationTotals: seatCfgTotals,
  );
  if (sessionId != null) metadata['sessionId'] = sessionId;
  if (placeIds != null && placeIds.isNotEmpty) metadata['placeIds'] = jsonEncode(placeIds);
  if (sectionSelections != null && sectionSelections.isNotEmpty) {
    metadata['sectionSelections'] = jsonEncode(sectionSelections);
  }
  if (seatTickets != null && seatTickets.isNotEmpty) {
    metadata['seatTickets'] = jsonEncode(seatTickets);
  }
  if (fullName != null && fullName.trim().isNotEmpty) {
    metadata['fullName'] = fullName.trim();
  }

  final response = await apiPost('/create-paytrail-payment-app', body: {
    'amount': amountCents,
    'currency': normalizeStripeCurrencyCode(currency),
    'paymentProvider': 'paytrail',
    'metadata': metadata,
    if (registrationAnswers != null && registrationAnswers.isNotEmpty)
      'registrationAnswers': registrationAnswers,
  });
  throwIfNotOk(response);
  final body = parseJsonBody(response);
  if (body == null) throw ApiException(500, 'No response');
  return body;
}

/// Called after Stripe payment succeeds. Backend needs placeIds and seatTickets in
/// request body to mark seats as sold (Stripe metadata has 500-char limit so they
/// are not stored there).
Future<Map<String, dynamic>> paymentSuccess({
  required String paymentIntentId,
  required String eventId,
  required String email,
  required String merchantId,
  String? ticketId,
  int? quantity,
  String? eventName,
  String? ticketName,
  String? externalMerchantId,
  String? sessionId,
  List<String>? placeIds,
  List<Map<String, dynamic>>? sectionSelections,
  List<Map<String, dynamic>>? seatTickets,
  bool marketingOptIn = false,
}) async {
  final metadata = <String, dynamic>{
    'eventId': eventId,
    'email': email,
    'merchantId': merchantId,
  };
  if (ticketId != null) metadata['ticketId'] = ticketId;
  if (quantity != null) metadata['quantity'] = quantity.toString();
  if (eventName != null) metadata['eventName'] = eventName;
  if (ticketName != null) metadata['ticketName'] = ticketName;
  if (externalMerchantId != null) metadata['externalMerchantId'] = externalMerchantId;
  if (sessionId != null) metadata['sessionId'] = sessionId;
  metadata['marketingOptIn'] = marketingOptIn;
  metadata['locale'] = 'en-US';
  if (placeIds != null && placeIds.isNotEmpty) metadata['placeIds'] = placeIds;
  if (sectionSelections != null && sectionSelections.isNotEmpty) {
    metadata['sectionSelections'] = sectionSelections;
  }
  if (seatTickets != null && seatTickets.isNotEmpty) metadata['seatTickets'] = seatTickets;

  final response = await apiPost('/payment-success', body: {
    'paymentIntentId': paymentIntentId,
    'metadata': metadata,
  });
  throwIfNotOk(response);
  final body = parseJsonBody(response);
  if (body == null) throw ApiException(500, 'No response');
  return body;
}

Future<Map<String, dynamic>> verifyPaytrailPayment({
  required String stamp,
  required String transactionId,
  required Map<String, dynamic> checkoutData,
}) async {
  final response = await apiPost('/verify-paytrail-payment', body: {
    'stamp': stamp,
    'transactionId': transactionId,
    ...checkoutData,
  });
  throwIfNotOk(response);
  final body = parseJsonBody(response);
  if (body == null) throw ApiException(500, 'No response');
  return body;
}
