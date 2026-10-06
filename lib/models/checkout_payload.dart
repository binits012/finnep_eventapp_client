import '../utils/checkout_payment.dart';
import '../utils/currency.dart';
import '../utils/money.dart';
import '../utils/privacy.dart';
import '../utils/seat_catalog_coupon.dart';

class CheckoutPayload {
  final String eventId;
  final String eventName;
  final String merchantId;
  final String externalMerchantId;
  final String email;
  final String? fullName;
  final String ticketId;
  final String ticketName;
  final double price;
  final double serviceFee;
  final double serviceTax;
  final double orderFee;
  final double vat;

  /// UI label for base tax (e.g. VAT).
  final String? taxLabel;
  final int quantity;
  final String currency;
  final bool paytrailEnabled;
  final bool marketingOptIn;
  final List<String>? placeIds;
  final List<Map<String, dynamic>>? sectionSelections;
  final List<Map<String, dynamic>>? seatTickets;
  final String? sessionId;
  final String? country;
  final int? reservationExpiresAtMs;

  /// Precomputed total major units (seats); used for server price match.
  final double? totalAmountOverride;
  final double? finalPricePerTicket;

  /// Event has merchant discount codes enabled.
  final bool hasDiscountCodes;

  final String? couponCode;
  final String? couponId;

  /// Catalog-only discount before tax/fees (server-validated).
  final double? couponDiscountAmount;

  final List<Map<String, dynamic>>? registrationFormFields;
  final Map<String, dynamic>? registrationAnswers;

  CheckoutPayload({
    required this.eventId,
    required this.eventName,
    required this.merchantId,
    required this.externalMerchantId,
    required this.email,
    this.fullName,
    required this.ticketId,
    required this.ticketName,
    required this.price,
    this.serviceFee = 0,
    this.serviceTax = 0,
    this.orderFee = 0,
    this.vat = 0,
    this.taxLabel,
    this.quantity = 1,
    String currency = 'eur',
    this.paytrailEnabled = false,
    this.marketingOptIn = false,
    this.placeIds,
    this.sectionSelections,
    this.seatTickets,
    this.sessionId,
    this.country,
    this.reservationExpiresAtMs,
    this.totalAmountOverride,
    this.finalPricePerTicket,
    this.hasDiscountCodes = false,
    this.couponCode,
    this.couponId,
    this.couponDiscountAmount,
    this.registrationFormFields,
    this.registrationAnswers,
  }) : currency = normalizeStripeCurrencyCode(currency);

  /// Same fields with coupon applied.
  CheckoutPayload mergeAppliedCoupon({
    required String couponCode,
    required String? couponId,
    required double couponDiscountAmount,
  }) {
    return CheckoutPayload(
      eventId: eventId,
      eventName: eventName,
      merchantId: merchantId,
      externalMerchantId: externalMerchantId,
      email: email,
      fullName: fullName,
      ticketId: ticketId,
      ticketName: ticketName,
      price: price,
      serviceFee: serviceFee,
      serviceTax: serviceTax,
      orderFee: orderFee,
      vat: vat,
      taxLabel: taxLabel,
      quantity: quantity,
      currency: currency,
      paytrailEnabled: paytrailEnabled,
      marketingOptIn: marketingOptIn,
      placeIds: placeIds,
      sectionSelections: sectionSelections,
      seatTickets: seatTickets,
      sessionId: sessionId,
      country: country,
      reservationExpiresAtMs: reservationExpiresAtMs,
      totalAmountOverride: totalAmountOverride,
      finalPricePerTicket: finalPricePerTicket,
      hasDiscountCodes: hasDiscountCodes,
      couponCode: couponCode,
      couponId: couponId,
      couponDiscountAmount: couponDiscountAmount,
      registrationFormFields: registrationFormFields,
      registrationAnswers: registrationAnswers,
    );
  }

  factory CheckoutPayload.fromJson(Map<String, dynamic> json) {
    return CheckoutPayload(
      eventId: (json['eventId'] ?? '').toString(),
      eventName: (json['eventName'] ?? '').toString(),
      merchantId: (json['merchantId'] ?? '').toString(),
      externalMerchantId: (json['externalMerchantId'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      fullName: json['fullName']?.toString(),
      ticketId: (json['ticketId'] ?? '').toString(),
      ticketName: (json['ticketName'] ?? '').toString(),
      price: (json['price'] as num?)?.toDouble() ?? 0,
      serviceFee: (json['serviceFee'] as num?)?.toDouble() ?? 0,
      serviceTax: (json['serviceTax'] as num?)?.toDouble() ?? 0,
      orderFee: (json['orderFee'] as num?)?.toDouble() ?? 0,
      vat: (json['vat'] as num?)?.toDouble() ?? 0,
      taxLabel: json['taxLabel']?.toString(),
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      currency: (json['currency'] ?? 'eur').toString(),
      paytrailEnabled: json['paytrailEnabled'] == true,
      marketingOptIn: json['marketingOptIn'] == true,
      placeIds: (json['placeIds'] is List)
          ? (json['placeIds'] as List).map((e) => e.toString()).toList()
          : null,
      sectionSelections: (json['sectionSelections'] is List)
          ? (json['sectionSelections'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : null,
      seatTickets: (json['seatTickets'] is List)
          ? (json['seatTickets'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : null,
      sessionId: json['sessionId']?.toString(),
      country: json['country']?.toString(),
      reservationExpiresAtMs: (json['reservationExpiresAtMs'] as num?)?.toInt(),
      totalAmountOverride: (json['totalAmountOverride'] as num?)?.toDouble(),
      finalPricePerTicket: (json['finalPricePerTicket'] as num?)?.toDouble(),
      hasDiscountCodes: json['hasDiscountCodes'] == true,
      couponCode: json['couponCode']?.toString(),
      couponId: json['couponId']?.toString(),
      couponDiscountAmount: (json['couponDiscountAmount'] as num?)?.toDouble(),
      registrationFormFields: (json['registrationFormFields'] is List)
          ? (json['registrationFormFields'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : null,
      registrationAnswers: json['registrationAnswers'] is Map
          ? Map<String, dynamic>.from(json['registrationAnswers'] as Map)
          : null,
    );
  }

  /// Per-unit catalog base after coupon (non-seat lines).
  double get effectiveUnitBaseForLine {
    return catalogUnitBaseAfterCoupon(
      unitBasePrice: price,
      quantity: quantity,
      couponCode: couponCode,
      couponDiscountAmount: couponDiscountAmount,
    );
  }

  double? get _seatTotalAfterCatalogCoupon {
    final code = couponCode?.trim() ?? '';
    final disc = couponDiscountAmount;
    if (code.isEmpty || disc == null || !(disc > 0)) return null;
    if (totalAmountOverride == null || !(totalAmountOverride! > 0)) return null;
    final st = seatTickets;
    if (st == null || st.isEmpty) return null;
    return discountedSeatCheckoutTotalFromPayload(
      totalAmountOverride: totalAmountOverride!,
      orderFeeRoot: orderFee,
      serviceFeeRoot: serviceFee,
      vatRatePercent: vat,
      orderServiceTaxRatePercent: serviceTax,
      seatTickets: st,
      couponDiscountOnCatalogSum: disc,
    );
  }

  /// Amount to charge in cents (line math, or seat override with optional coupon adjustment).
  int get totalCents {
    if (totalAmountOverride != null && totalAmountOverride! > 0) {
      final adjTotal = _seatTotalAfterCatalogCoupon;
      final amount = adjTotal != null
          ? roundMoney(adjTotal)
          : roundMoney(totalAmountOverride!);
      final cents = (amount * 100).round();
      return cents < 1 ? 1 : cents;
    }
    final line = computeTicketLinePricing(
      basePrice: effectiveUnitBaseForLine,
      serviceFee: serviceFee,
      vatRatePercent: vat,
      serviceTaxRatePercent: serviceTax,
      orderFee: orderFee,
      quantity: quantity,
    );
    final cents = (roundMoney(line.total) * 100).round();
    return cents < 1 ? 1 : cents;
  }

  @override
  String toString() {
    return 'CheckoutPayload('
        'eventId: $eventId, '
        'eventName: $eventName, '
        'merchantId: $merchantId, '
        'externalMerchantId: $externalMerchantId, '
        'email: ${maskEmailForDisplay(email)}, '
        'fullName: $fullName, '
        'ticketId: $ticketId, '
        'ticketName: $ticketName, '
        'price: $price, '
        'serviceFee: $serviceFee, '
        'serviceTax: $serviceTax, '
        'orderFee: $orderFee, '
        'vat: $vat, '
        'taxLabel: $taxLabel, '
        'quantity: $quantity, '
        'currency: $currency, '
        'paytrailEnabled: $paytrailEnabled, '
        'marketingOptIn: $marketingOptIn, '
        'placeIds: $placeIds, '
        'sectionSelections: $sectionSelections, '
        'seatTickets: $seatTickets, '
        'sessionId: $sessionId, '
        'country: $country, '
        'reservationExpiresAtMs: $reservationExpiresAtMs, '
        'totalAmountOverride: $totalAmountOverride, '
        'totalCents: $totalCents, '
        'finalPricePerTicket: $finalPricePerTicket, '
        'hasDiscountCodes: $hasDiscountCodes, '
        'couponCode: $couponCode, '
        'couponDiscountAmount: $couponDiscountAmount'
        ')';
  }

  Map<String, dynamic> toJson() {
    return {
      'eventId': eventId,
      'eventName': eventName,
      'merchantId': merchantId,
      'externalMerchantId': externalMerchantId,
      'email': email,
      'fullName': fullName,
      'ticketId': ticketId,
      'ticketName': ticketName,
      'price': price,
      'serviceFee': serviceFee,
      'serviceTax': serviceTax,
      'orderFee': orderFee,
      'vat': vat,
      'taxLabel': taxLabel,
      'quantity': quantity,
      'currency': currency,
      'paytrailEnabled': paytrailEnabled,
      'marketingOptIn': marketingOptIn,
      'placeIds': placeIds,
      'sectionSelections': sectionSelections,
      'seatTickets': seatTickets,
      'sessionId': sessionId,
      'country': country,
      'reservationExpiresAtMs': reservationExpiresAtMs,
      'totalAmountOverride': totalAmountOverride,
      'totalCents': totalCents,
      'finalPricePerTicket': finalPricePerTicket,
      'hasDiscountCodes': hasDiscountCodes,
      'couponCode': couponCode,
      'couponId': couponId,
      'couponDiscountAmount': couponDiscountAmount,
      'registrationFormFields': registrationFormFields,
      'registrationAnswers': registrationAnswers,
    };
  }
}
