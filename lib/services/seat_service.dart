import '../models/seat.dart';
import '../utils/money.dart';
import '../utils/place_id_decoder.dart';
import '../utils/ticket_pricing.dart';
import 'api_client.dart';

Future<SeatMapData> getEventSeats(
  String eventId, {
  String? email,
  String? sessionId,
  String? checkoutToken,
}) async {
  final query = <String, String>{
    if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
    if (sessionId != null && sessionId.trim().isNotEmpty)
      'sessionId': sessionId.trim(),
    if (checkoutToken != null && checkoutToken.trim().isNotEmpty)
      'checkoutToken': checkoutToken.trim(),
  };
  final suffix = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
  final response = await apiGet('/event/$eventId/seats$suffix');
  throwIfNotOk(response);
  final body = parseJsonBody(response);
  if (body == null) throw ApiException(500, 'Empty response');
  // Backend returns { data: { placeIds, sold, reserved, ownReserved, sections, ... } }
  final data = body['data'] as Map<String, dynamic>? ?? body;
  return SeatMapData.fromJson(data);
}

/// Reserve seats. Payload: placeIds, sessionId, email only (no fullName).
Future<Map<String, dynamic>> reserveSeats(
  String eventId,
  List<String> placeIds,
  String sessionId, {
  String? email,
  List<Map<String, dynamic>>? sectionSelections,
}) async {
  final body = <String, dynamic>{
    'placeIds': placeIds,
    if (sectionSelections != null && sectionSelections.isNotEmpty)
      'sectionSelections': sectionSelections,
    'sessionId': sessionId,
    if (email != null && email.isNotEmpty) 'email': email,
  };
  final response = await apiPost('/event/$eventId/seats/reserve', body: body);
  throwIfNotOk(response);
  return parseJsonBody(response) ?? {};
}

Future<void> releaseSeats(
  String eventId,
  List<String> placeIds,
  String sessionId,
) async {
  final response = await apiPost(
    '/event/$eventId/seats/release',
    body: {'placeIds': placeIds, 'sessionId': sessionId},
  );
  throwIfNotOk(response);
}

Future<void> sendSeatOtp(
  String eventId,
  String email, {
  String? fullName,
  List<String>? placeIds,
  List<Map<String, dynamic>>? sectionSelections,
  String? locale,
}) async {
  var path = '/event/$eventId/seats/send-otp';
  if (locale != null && locale.isNotEmpty) {
    path += '?locale=${Uri.encodeComponent(locale)}';
  }
  final body = <String, dynamic>{
    'email': email,
    if (fullName != null && fullName.trim().isNotEmpty)
      'fullName': fullName.trim(),
    if (placeIds != null && placeIds.isNotEmpty) 'placeIds': placeIds,
    if (sectionSelections != null && sectionSelections.isNotEmpty)
      'sectionSelections': sectionSelections,
  };
  final response = await apiPost(path, body: body);
  throwIfNotOk(response);
}

Future<void> verifySeatOtp(
  String eventId,
  String email,
  String otp, {
  List<String>? placeIds,
  List<Map<String, dynamic>>? sectionSelections,
}) async {
  final body = <String, dynamic>{
    'email': email,
    'otp': otp,
    if (placeIds != null && placeIds.isNotEmpty) 'placeIds': placeIds,
    if (sectionSelections != null && sectionSelections.isNotEmpty)
      'sectionSelections': sectionSelections,
  };
  final response = await apiPost(
    '/event/$eventId/seats/verify-otp',
    body: body,
  );
  throwIfNotOk(response);
}

Future<bool> checkSeatEmailTrust(String eventId, String email) async {
  final response = await apiPost(
    '/event/$eventId/seats/check-email-trust',
    body: {'email': email},
  );
  throwIfNotOk(response);
  final json = parseJsonBody(response);
  final data = json?['data'];
  if (data is Map) return data['trusted'] == true;
  return json?['trusted'] == true;
}

int _statusPriority(SeatStatus status) {
  switch (status) {
    case SeatStatus.sold:
      return 2;
    case SeatStatus.reserved:
      return 1;
    case SeatStatus.available:
      return 0;
  }
}

List<SeatModel> decodeSeats(SeatMapData data) {
  final soldSet = data.sold.toSet();
  final reservedSet = data.reserved.toSet();
  final ownReservedSet = data.ownReserved.toSet();
  final byPlaceId = <String, SeatModel>{};
  // Prefer tier over zone (match web: Base 27 + Tax 3.645 = 30.645)
  for (var i = 0; i < data.placeIds.length; i++) {
    final placeId = data.placeIds[i];
    final decoded = decodePlaceId(placeId);
    if (decoded == null) continue;
    var status = SeatStatus.available;
    if (ownReservedSet.contains(placeId)) {
      status = SeatStatus.available;
    } else if (!decoded.available) {
      status = SeatStatus.sold;
    } else if (soldSet.contains(placeId)) {
      status = SeatStatus.sold;
    } else if (reservedSet.contains(placeId)) {
      status = SeatStatus.reserved;
    }
    double? price;
    double? basePrice;
    double? taxAmount;
    double? serviceFeeAmount;
    // 1) Try tier first (parity with web: Base + Tax + Service Fee = Total, round to 3 decimals)
    if (data.pricingConfig != null && decoded.tierCode.isNotEmpty) {
      PricingTier? tier;
      for (final t in data.pricingConfig!.tiers) {
        if (t.id == decoded.tierCode) {
          tier = t;
          break;
        }
      }
      if (tier != null) {
        final breakdown = calculateTicketPrice(
          price: tier.basePrice,
          vat: tier.tax,
          serviceTax: tier.serviceTax,
          serviceFee: tier.serviceFee,
          orderFee: 0,
        );
        basePrice = roundMoney(tier.basePrice);
        taxAmount = roundMoney(breakdown.vatAmountPerTicket);
        final feeInclTax =
            breakdown.serviceFeeTaxAmount + breakdown.serviceFeeAmount;
        serviceFeeAmount = feeInclTax > 0 ? roundMoney(feeInclTax) : null;
        price = roundMoney(breakdown.totalPerTicket);
      }
    }
    // 2) Fall back to zone if no tier match
    if (price == null) {
      for (final zone in data.pricingZones) {
        if (i >= zone.start && i <= zone.end) {
          price = zone.price;
          break;
        }
      }
    }
    final nextSeat = SeatModel(
      placeId: placeId,
      x: decoded.x,
      y: decoded.y,
      row: decoded.row.toString(),
      seat: decoded.seat.toString(),
      section: decoded.section,
      price: price,
      basePrice: basePrice,
      taxAmount: taxAmount,
      serviceFeeAmount: serviceFeeAmount,
      status: status,
      tags: decoded.tags,
    );
    final existing = byPlaceId[placeId];
    if (existing == null) {
      byPlaceId[placeId] = nextSeat;
    } else {
      final currentPriority = _statusPriority(existing.status);
      final nextPriority = _statusPriority(nextSeat.status);
      byPlaceId[placeId] = nextPriority >= currentPriority
          ? nextSeat
          : existing;
    }
  }
  return byPlaceId.values.toList();
}
