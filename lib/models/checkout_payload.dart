import '../utils/ticket_pricing.dart';

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
  /// Display label for the base tax rate shown in UI.
  /// Example: "VAT".
  final String? taxLabel;
  final int quantity;
  final String currency;
  final bool paytrailEnabled;
  final List<String>? placeIds;
  final List<Map<String, dynamic>>? sectionSelections;
  final List<Map<String, dynamic>>? seatTickets;
  final String? sessionId;
  final String? country;
  final int? reservationExpiresAtMs;
  /// When set (e.g. from ticket.totalPerTicket * qty), amount uses this so backend match succeeds.
  final double? totalAmountOverride;
  final double? finalPricePerTicket;

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
    this.currency = 'eur',
    this.paytrailEnabled = false,
    this.placeIds,
    this.sectionSelections,
    this.seatTickets,
    this.sessionId,
    this.country,
    this.reservationExpiresAtMs,
    this.totalAmountOverride,
    this.finalPricePerTicket,
  });

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
    );
  }

  /// Total in cents. Matches backend: per-ticket total (orderFee not in per-ticket) * qty + orderFee + orderFeeTax once.
  /// - If totalAmountOverride is set (e.g. seat selection), use it.
  /// - Else always compute from breakdown so we never double-count order fee (API finalPricePerTicket may include it per ticket).
  int get totalCents {
    if (totalAmountOverride != null && totalAmountOverride! > 0) {
      final cents = (totalAmountOverride! * 100).round();
      return cents < 1 ? 1 : cents;
    }
    // Order fee is per transaction. Per-ticket total excludes it; add once at the end.
    final breakdown = calculateTicketPrice(
      price: price,
      vat: vat,
      entertainmentTax: null,
      serviceTax: serviceTax,
      serviceFee: serviceFee,
      orderFee: 0,
    );
    final orderFeeTax = orderFee * (serviceTax / 100);
    final total = (breakdown.finalPricePerTicket * quantity) + orderFee + orderFeeTax;
    final cents = (total * 100).round();
    return cents < 1 ? 1 : cents;
  }



  @override
String toString() {
  return 'CheckoutPayload('
    'eventId: $eventId, '
    'eventName: $eventName, '
    'merchantId: $merchantId, '
    'externalMerchantId: $externalMerchantId, '
    'email: $email, '
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
    'placeIds: $placeIds, '
    'sectionSelections: $sectionSelections, '
    'seatTickets: $seatTickets, '
    'sessionId: $sessionId, '
    'country: $country, '
    'reservationExpiresAtMs: $reservationExpiresAtMs, '
    'totalAmountOverride: $totalAmountOverride, '
    'totalCents: $totalCents, '
    'finalPricePerTicket: $finalPricePerTicket'
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
      'placeIds': placeIds,
      'sectionSelections': sectionSelections,
      'seatTickets': seatTickets,
      'sessionId': sessionId,
      'country': country,
      'reservationExpiresAtMs': reservationExpiresAtMs,
      'totalAmountOverride': totalAmountOverride,
      'totalCents': totalCents,
      'finalPricePerTicket': finalPricePerTicket,
    };
  }
}
