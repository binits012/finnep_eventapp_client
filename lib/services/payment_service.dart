import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import '../utils/ticket_pricing.dart';

const _chars = 'abcdefghijklmnopqrstuvwxyz0123456789';

String _generateNonce() {
  final r = List.generate(32, (i) => _chars[(DateTime.now().microsecondsSinceEpoch + i) % _chars.length]);
  return r.join();
}

String _fmt(num n, [int decimals = 2]) {
  if (decimals == 0) return n.round().toString();
  return n.toStringAsFixed(decimals);
}

String _fmtRate(num n) {
  // Preserve decimals (e.g. 13.5, 25.5) and trim trailing zeros.
  final s = _fmt(n, 2);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
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
  String? sessionId,
  List<String>? placeIds,
  List<Map<String, dynamic>>? sectionSelections,
  List<Map<String, dynamic>>? seatTickets,
  String? country,
  String? fullName,
  double? totalAmountOverride,
}) async {
  // orderFee is per transaction (not per ticket). Keep per-ticket subtotal separate.
  final subtotalNoVat = (basePrice + serviceFee) * quantity;
  final vatAmount = (basePrice * quantity) * (vatRate / 100);
  final serviceTaxMultiplier = serviceTaxRate > 0 ? (serviceTaxRate / 100) : 0.0;
  final serviceTaxAmount = (serviceFee * quantity) * serviceTaxMultiplier;
  final orderFeeServiceTax = orderFee * serviceTaxMultiplier;
  final totalAmount = totalAmountOverride ??
      (subtotalNoVat + vatAmount + serviceTaxAmount + orderFee + orderFeeServiceTax);
  final totalBasePrice = basePrice * quantity;
  final totalServiceFee = serviceFee * quantity;
  final totalOrderFee = orderFee;
  final stripeBreakdown = calculateTicketPrice(
    price: basePrice,
    vat: vatRate,
    entertainmentTax: null,
    serviceTax: serviceTaxRate,
    serviceFee: serviceFee,
    orderFee: 0,
  );
  final perUnitSubtotal = stripeBreakdown.subtotalPerTicket;
  final perUnitTotal = stripeBreakdown.finalPricePerTicket;
  // When override is set (e.g. seatTickets), backend validates amount against its own recalculation; use 3 decimals for metadata parity with web.
  final totalAmountDecimals = totalAmountOverride != null ? 3 : 2;
  debugPrint('[Payment service] createPaymentIntent: basePrice=$basePrice serviceFee=$serviceFee orderFee=$orderFee qty=$quantity vatRate=$vatRate% serviceTaxRate=$serviceTaxRate');
  debugPrint('[Payment service] subtotalNoVat=$subtotalNoVat vatAmount=$vatAmount totalAmount=$totalAmount override=$totalAmountOverride → amountCents=$amountCents (${amountCents / 100} €)');
  final metadata = <String, dynamic>{
    'eventId': eventId,
    'ticketId': ticketId,
    'email': email,
    'quantity': quantity.toString(),
    'eventName': eventName,
    'ticketName': ticketName,
    'merchantId': merchantId,
    'externalMerchantId': externalMerchantId,
    'nonce': _generateNonce(),
    'basePrice': _fmt(basePrice, 0),
    'subtotal': _fmt(subtotalNoVat, 3),
    'serviceFee': _fmt(serviceFee, 0),
    'totalServiceFee': _fmt(totalServiceFee),
    'serviceTax': _fmtRate(serviceTaxRate),
    'serviceTaxAmount': _fmt(serviceTaxAmount, 3),
    'vatRate': _fmtRate(vatRate),
    'vatAmount': _fmt(vatAmount, 3),
    'orderFee': _fmt(orderFee, 0),
    'orderFeeServiceTax': _fmt(orderFeeServiceTax, 3),
    'totalOrderFee': _fmt(totalOrderFee, 3),
    'totalAmount': _fmt(totalAmount, totalAmountDecimals),
    'perUnitSubtotal': _fmt(perUnitSubtotal, 0),
    'perUnitTotal': _fmt(perUnitTotal, 3),
    'totalBasePrice': _fmt(totalBasePrice, 0),
    'totalVatAmount': _fmt(vatAmount, 3),
    'country': country ?? '',
    'marketingOptIn': false,
    'locale': 'en-US',
  };
  if (sessionId != null) metadata['sessionId'] = sessionId;
  if (placeIds != null && placeIds.isNotEmpty) metadata['placeIds'] = jsonEncode(placeIds);
  if (sectionSelections != null && sectionSelections.isNotEmpty) metadata['sectionSelections'] = jsonEncode(sectionSelections);
  if (seatTickets != null && seatTickets.isNotEmpty) metadata['seatTickets'] = jsonEncode(seatTickets);
  if (fullName != null && fullName.trim().isNotEmpty) metadata['fullName'] = fullName.trim();

  final response = await apiPost('/create-payment-intent', body: {
    'amount': amountCents,
    'currency': currency,
    'paymentProvider': 'stripe',
    'metadata': metadata,
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
  String? sessionId,
  List<String>? placeIds,
  List<Map<String, dynamic>>? sectionSelections,
  List<Map<String, dynamic>>? seatTickets,
  String? country,
  String? fullName,
  double? totalAmountOverride,
}) async {
  // orderFee is per transaction (not per ticket).
  final subtotalNoVat = (basePrice + serviceFee) * quantity;
  final vatAmount = (basePrice * quantity) * (vatRate / 100);
  final serviceTaxMultiplier = serviceTaxRate > 0 ? (serviceTaxRate / 100) : 0.0;
  final serviceTaxAmount = (serviceFee * quantity) * serviceTaxMultiplier;
  final orderFeeServiceTax = orderFee * serviceTaxMultiplier;

  final hasSeats = (placeIds != null && placeIds.isNotEmpty) ||
      (seatTickets != null && seatTickets.isNotEmpty);
  final meta3 = hasSeats || totalAmountOverride != null;

  // Totals (match web): base/service/order are simple sums; taxes are separate fields.
  final totalBasePrice = basePrice * quantity;
  final totalServiceFee = serviceFee * quantity;
  final totalOrderFee = orderFee;

  // For seats, backend/web use "entertainmentTax" naming (even when it's effectively vatRate).
  final entertainmentTax = vatRate;
  final entertainmentTaxAmount = (basePrice * quantity) * (entertainmentTax / 100);
  final paytrailBreakdown = calculateTicketPrice(
    price: basePrice,
    vat: vatRate,
    entertainmentTax: null,
    serviceTax: serviceTaxRate,
    serviceFee: serviceFee,
    orderFee: 0,
  );
  final perUnitSubtotal = paytrailBreakdown.subtotalPerTicket;
  final computedTotalAmount = (paytrailBreakdown.finalPricePerTicket * quantity) + orderFee + orderFeeServiceTax;
  final totalAmountForMeta = totalAmountOverride ?? computedTotalAmount;
  final totalAmountDecimalsPaytrail = meta3 ? 3 : 2;
  final perUnitTotal = paytrailBreakdown.finalPricePerTicket;

  debugPrint('[Payment service] createPaytrailPayment: basePrice=$basePrice serviceFee=$serviceFee orderFee=$orderFee qty=$quantity vatRate=$vatRate%');
  debugPrint('[Payment service] subtotalNoVat=$subtotalNoVat vatAmount=$vatAmount totalAmount=$computedTotalAmount override=$totalAmountOverride → amountCents=$amountCents (${amountCents / 100} €)');
  final metadata = <String, dynamic>{
    'eventId': eventId,
    'ticketId': ticketId,
    'email': email,
    'quantity': quantity.toString(),
    'eventName': eventName,
    'ticketName': ticketName,
    'merchantId': merchantId,
    'externalMerchantId': externalMerchantId,
    'nonce': _generateNonce(),
    'basePrice': _fmt(basePrice, 0),
    'subtotal': _fmt(subtotalNoVat, meta3 ? 3 : 2),
    'serviceFee': _fmt(serviceFee, 0),
    'totalServiceFee': _fmt(totalServiceFee),
    'serviceTax': _fmtRate(serviceTaxRate),
    'serviceTaxAmount': _fmt(serviceTaxAmount, meta3 ? 3 : 2),
    'vatRate': _fmtRate(vatRate),
    'vatAmount': _fmt(vatAmount, meta3 ? 3 : 2),
    'orderFee': _fmt(orderFee, 0),
    'orderFeeServiceTax': _fmt(orderFeeServiceTax, meta3 ? 3 : 2),
    'totalOrderFee': _fmt(totalOrderFee, meta3 ? 3 : 2),
    'totalAmount': _fmt(totalAmountForMeta, totalAmountDecimalsPaytrail),
    'perUnitSubtotal': _fmt(perUnitSubtotal, 0),
    'perUnitTotal': _fmt(perUnitTotal, meta3 ? 3 : 2),
    'totalBasePrice': _fmt(totalBasePrice, meta3 ? 3 : 0),
    'totalVatAmount': _fmt(vatAmount, meta3 ? 3 : 2),
    'country': country ?? '',
    'marketingOptIn': false,
    'locale': 'en-US',
  };
  if (meta3) {
    // Match web payload fields for seated events
    metadata['entertainmentTax'] = _fmtRate(entertainmentTax);
    metadata['entertainmentTaxAmount'] = _fmt(entertainmentTaxAmount, 3);
    metadata['totalEntertainmentTaxAmount'] = _fmt(entertainmentTaxAmount, 3);
    metadata['serviceTax'] = _fmtRate(serviceTaxRate);
    metadata['orderFee'] = _fmt(orderFee, 0);
  }
  if (sessionId != null) metadata['sessionId'] = sessionId;
  if (placeIds != null && placeIds.isNotEmpty) metadata['placeIds'] = jsonEncode(placeIds);
  if (sectionSelections != null && sectionSelections.isNotEmpty) metadata['sectionSelections'] = jsonEncode(sectionSelections);
  if (seatTickets != null && seatTickets.isNotEmpty) metadata['seatTickets'] = jsonEncode(seatTickets);
  if (fullName != null && fullName.trim().isNotEmpty) metadata['fullName'] = fullName.trim();

  // Mobile app endpoint: uses PAYTRAIL_APP_RETURN_URL to deep-link back to the app after payment.
  final response = await apiPost('/create-paytrail-payment-app', body: {
    'amount': amountCents,
    'currency': currency,
    'paymentProvider': 'paytrail',
    'metadata': metadata,
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
  metadata['marketingOptIn'] = false;
  metadata['locale'] = 'en-US';
  if (placeIds != null && placeIds.isNotEmpty) metadata['placeIds'] = placeIds;
  if (sectionSelections != null && sectionSelections.isNotEmpty) metadata['sectionSelections'] = sectionSelections;
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
