class GuestTicket {
  final String id;
  final String? ticketFor;
  final String? event;
  final String? eventTitle;
  final String? eventDate;
  final String? purchaseDate;
  final Map<String, dynamic>? qrCode;
  final Map<String, dynamic>? ics;
  final String? venue;
  final String? ticketName;
  final String? orderId;
  final String? quantity;
  final String? totalAmount;
  final String? currency;
  final String? paymentMethod;
  final String? basePrice;
  final String? serviceFee;
  final Map<String, dynamic>? raw;

  GuestTicket({
    required this.id,
    this.ticketFor,
    this.event,
    this.eventTitle,
    this.eventDate,
    this.purchaseDate,
    this.qrCode,
    this.ics,
    this.venue,
    this.ticketName,
    this.orderId,
    this.quantity,
    this.totalAmount,
    this.currency,
    this.paymentMethod,
    this.basePrice,
    this.serviceFee,
    this.raw,
  });

  factory GuestTicket.fromJson(Map<String, dynamic> json) {
    final event = _map(json['event']);
    final ticketInfo = _map(json['ticketInfo']);
    String? fromAny(String key) => _string(json[key]) ?? _stringFromMap(ticketInfo, key) ?? _stringFromMap(event, key);
    return GuestTicket(
      id: _idString(json['_id']),
      ticketFor: fromAny('ticketFor') ?? _string(json['email']),
      event: _string(json['event']),
      eventTitle: _string(json['eventTitle']) ?? _stringFromMap(event, 'eventTitle') ?? fromAny('eventName'),
      eventDate: _string(json['eventDate']) ?? _stringFromMap(event, 'eventDate') ?? fromAny('date'),
      purchaseDate: _string(json['purchaseDate']) ?? _string(json['createdAt']),
      qrCode: _qrCodeFromJson(json['qrCode']),
      ics: _map(json['ics']),
      venue: fromAny('venue') ?? fromAny('location') ?? _stringFromMap(event, 'venue'),
      ticketName: fromAny('ticketName') ?? fromAny('ticketType'),
      orderId: fromAny('orderId') ?? fromAny('orderRef') ?? fromAny('reference'),
      quantity: fromAny('quantity') ?? _string(json['qty']),
      totalAmount: fromAny('totalAmount') ?? fromAny('total') ?? _string(json['amount']),
      currency: fromAny('currency'),
      paymentMethod: fromAny('paymentMethod') ?? fromAny('paymentProvider'),
      basePrice: fromAny('basePrice') ?? fromAny('price'),
      serviceFee: fromAny('serviceFee'),
      raw: json,
    );
  }
}

String _idString(dynamic v) {
  if (v == null) return '';
  if (v is String) return v;
  if (v is Map && v['_id'] != null) return _idString(v['_id']);
  return v.toString();
}

String? _string(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  return v.toString();
}

String? _stringFromMap(dynamic v, String key) {
  if (v is! Map<String, dynamic>) return null;
  return _string(v[key]);
}

Map<String, dynamic>? _map(dynamic v) {
  if (v == null) return null;
  if (v is Map<String, dynamic>) return v;
  return null;
}

Map<String, dynamic>? _qrCodeFromJson(dynamic v) {
  if (v == null) return null;
  if (v is Map<String, dynamic>) return v;
  if (v is String) return {'data': v};
  return null;
}
