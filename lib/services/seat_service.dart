import '../models/seat.dart';
import '../utils/place_id_decoder.dart';
import '../utils/ticket_pricing.dart';
import 'api_client.dart';

Future<SeatMapData> getEventSeats(String eventId) async {
  final response = await apiGet('/event/$eventId/seats');
  throwIfNotOk(response);
  final body = parseJsonBody(response);
  if (body == null) throw ApiException(500, 'Empty response');
  // Backend returns { data: { placeIds, sold, reserved, sections, ... } }
  final data = body['data'] as Map<String, dynamic>? ?? body;
  return SeatMapData.fromJson(data);
}

/// Reserve seats. Payload: placeIds, sessionId, email only (no fullName).
Future<Map<String, dynamic>> reserveSeats(
  String eventId,
  List<String> placeIds,
  String sessionId, {
  String? email,
}) async {
  final body = <String, dynamic>{
    'placeIds': placeIds,
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
  final response = await apiPost('/event/$eventId/seats/release', body: {
    'placeIds': placeIds,
    'sessionId': sessionId,
  });
  throwIfNotOk(response);
}

Future<void> sendSeatOtp(
  String eventId,
  String email, {
  String? fullName,
  List<String>? placeIds,
  String? locale,
}) async {
  var path = '/event/$eventId/seats/send-otp';
  if (locale != null && locale.isNotEmpty) {
    path += '?locale=${Uri.encodeComponent(locale)}';
  }
  final body = <String, dynamic>{
    'email': email,
    if (fullName != null && fullName.trim().isNotEmpty) 'fullName': fullName.trim(),
    if (placeIds != null && placeIds.isNotEmpty) 'placeIds': placeIds,
  };
  final response = await apiPost(path, body: body);
  throwIfNotOk(response);
}

Future<void> verifySeatOtp(
  String eventId,
  String email,
  String otp, {
  List<String>? placeIds,
}) async {
  final body = <String, dynamic>{
    'email': email,
    'otp': otp,
    if (placeIds != null && placeIds.isNotEmpty) 'placeIds': placeIds,
  };
  final response = await apiPost('/event/$eventId/seats/verify-otp', body: body);
  throwIfNotOk(response);
}

double _round3(double v) => (v * 1000).round() / 1000.0;

List<SeatModel> decodeSeats(SeatMapData data) {
  final soldSet = data.sold.toSet();
  final reservedSet = data.reserved.toSet();
  final list = <SeatModel>[];
  // Prefer tier over zone (match web: Base 27 + Tax 3.645 = 30.645)
  for (var i = 0; i < data.placeIds.length; i++) {
    final placeId = data.placeIds[i];
    final decoded = decodePlaceId(placeId);
    if (decoded == null) continue;
    var status = SeatStatus.available;
    if (!decoded.available) {
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
        basePrice = _round3(tier.basePrice);
        taxAmount = _round3(breakdown.subtotalPerTicket - tier.basePrice);
        final feeInclTax = breakdown.totalPerTicket - breakdown.subtotalPerTicket;
        serviceFeeAmount = feeInclTax > 0 ? _round3(feeInclTax) : null;
        price = _round3(breakdown.totalPerTicket);
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
    list.add(SeatModel(
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
    ));
  }
  return list;
}
