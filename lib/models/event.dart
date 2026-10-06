import '../utils/ticket_pricing.dart';

class Event {
  final String id;
  final String eventTitle;
  final String? eventDescription;
  final String eventDate;
  final String? eventEndDate;
  final String? eventPromotionPhoto;
  final String? status;
  final VenueInfo? venueInfo;
  final Venue? venue;
  final String? city;
  final String? country;
  final String? eventLocationAddress;
  final List<TicketInfo> ticketInfo;
  final String? eventTimezone;
  final Merchant? merchant;
  final String? merchantId;
  final String? externalMerchantId;
  final Featured? featured;
  final String? videoUrl;
  final String? transportLink;
  final String? eventLocationGeoCode;
  final bool? isSeatedEventFromApi;
  final bool? hasSeatSelectionFromApi;
  final Map<String, dynamic>? waitlistConfig;
  final int? preSaleWaitlistCount;
  final int? preSaleWaitlistCap;
  final Map<String, dynamic>? otherInfo;

  /// From public API when true.
  final bool hasDiscountCodes;

  Event({
    required this.id,
    required this.eventTitle,
    this.eventDescription,
    required this.eventDate,
    this.eventEndDate,
    this.eventPromotionPhoto,
    this.status,
    this.venueInfo,
    this.venue,
    this.city,
    this.country,
    this.eventLocationAddress,
    this.ticketInfo = const [],
    this.eventTimezone,
    this.merchant,
    this.merchantId,
    this.externalMerchantId,
    this.featured,
    this.videoUrl,
    this.transportLink,
    this.eventLocationGeoCode,
    this.isSeatedEventFromApi,
    this.hasSeatSelectionFromApi,
    this.waitlistConfig,
    this.preSaleWaitlistCount,
    this.preSaleWaitlistCap,
    this.otherInfo,
    this.hasDiscountCodes = false,
  });

  factory Event.fromJson(Map<String, dynamic> json) {
    final ticketInfoRaw = json['ticketInfo'] ?? json['tickets'];
    List<TicketInfo> ticketInfoList = [];
    if (ticketInfoRaw is List<dynamic>) {
      for (final e in ticketInfoRaw) {
        if (e == null) continue;
        final m = e is Map ? Map<String, dynamic>.from(e) : null;
        if (m != null) {
          try {
            ticketInfoList.add(TicketInfo.fromJson(m));
          } catch (_) {}
        }
      }
    }
    return Event(
      id: _str(json['_id']) ?? '',
      eventTitle: _str(json['eventTitle']) ?? '',
      eventDescription: _str(json['eventDescription']),
      eventDate: _str(json['eventDate']) ?? '',
      eventEndDate: _str(json['eventEndDate']) ?? _str(json['event_end_date']),
      eventPromotionPhoto: _str(json['eventPromotionPhoto']),
      status: _str(json['status']),
      venueInfo: _mapFrom(json['venueInfo'])?._let(VenueInfo.fromJson),
      venue: _mapFrom(json['venue'])?._let(Venue.fromJson),
      city: _str(json['city']),
      country: _str(json['country']),
      eventLocationAddress: _str(json['eventLocationAddress']),
      ticketInfo: ticketInfoList,
      eventTimezone: _str(json['eventTimezone']),
      merchant: _mapFrom(json['merchant'])?._let(Merchant.fromJson),
      merchantId: _str(json['merchantId']) ?? _str(json['merchant']?['_id']),
      externalMerchantId: _str(json['externalMerchantId']),
      featured: _mapFrom(json['featured'])?._let(Featured.fromJson),
      videoUrl: _str(json['videoUrl']),
      transportLink: _str(json['transportLink']),
      eventLocationGeoCode: _str(json['eventLocationGeoCode']),
      isSeatedEventFromApi: _boolOrNull(json, 'isSeatedEvent'),
      hasSeatSelectionFromApi: _boolOrNull(json, 'hasSeatSelection'),
      waitlistConfig: _mapFrom(json['waitlistConfig']),
      preSaleWaitlistCount: (json['pre_sale_waitlist_count'] is num)
          ? (json['pre_sale_waitlist_count'] as num).toInt()
          : null,
      preSaleWaitlistCap: (json['pre_sale_waitlist_cap'] is num)
          ? (json['pre_sale_waitlist_cap'] as num).toInt()
          : null,
      otherInfo: _mergedOtherInfoFromJson(json),
      hasDiscountCodes: json['hasDiscountCodes'] == true,
    );
  }

  /// Seated storefront flow: manifests, pricing_configuration, or explicit flags—not `venueId` alone.
  bool get hasSeatSelection {
    if (isSeatedEventFromApi == true) return true;
    if (hasSeatSelectionFromApi == true) return true;
    final v = venue;
    if (v != null && v.hasSeatSelection == true) return true;
    final mv = v?.manifestVersion ?? 0;
    if (mv > 0) return true;
    final locked = (v?.lockedManifestId ?? '').trim();
    if (locked.isNotEmpty) return true;
    if (v?.pricingModel == 'pricing_configuration') return true;
    return false;
  }

  List<TicketInfo> get customerVisibleTicketInfo => ticketInfo
      .where((t) => !isTicketHiddenFromCustomer(t.status))
      .toList(growable: false);

  /// Pre_sale / sold_out waitlist modes from CMS config + ticket flags.
  String? get waitlistOffer {
    final wc = waitlistConfig;
    final eventType = otherInfo?['eventExtraInfo'] is Map
        ? (otherInfo?['eventExtraInfo'] as Map)['eventType']
        : null;
    if (wc == null || eventType == 'free') return null;
    if (wc['pre_sale_enabled'] == true) return 'pre_sale';
    final hasSoldOut = customerVisibleTicketInfo.any(
      (t) => t.status == 'sold_out',
    );
    if (wc['sold_out_enabled'] == true && hasSoldOut) return 'sold_out';
    return null;
  }

  /// Listing cards must not show a ticket price while sales are closed.
  /// Pre-sale always hides the price. Sold-out waitlist hides it when no
  /// visible ticket is still available or low stock.
  bool get isListingOnWaitlist {
    final offer = waitlistOffer;
    if (offer == 'pre_sale') return true;
    if (offer != 'sold_out') return false;
    final hasOnSale = customerVisibleTicketInfo.any(
      (ticket) => ticket.status == 'available' || ticket.status == 'low_stock',
    );
    return !hasOnSale;
  }

  /// True when pre-sale waitlist has a cap and current count has reached it.
  bool get isPreSaleWaitlistFull {
    if (waitlistOffer != 'pre_sale') return false;
    final cap = preSaleWaitlistCap;
    if (cap == null) return false;
    final count = preSaleWaitlistCount ?? 0;
    return count >= cap;
  }

  /// Free event: `eventType === 'free'` or all visible tickets price 0.
  bool get isFreeEvent {
    final eventType = otherInfo?['eventExtraInfo'] is Map
        ? (otherInfo?['eventExtraInfo'] as Map)['eventType']
        : null;
    if (eventType == 'free') return true;
    if (customerVisibleTicketInfo.isEmpty) return false;
    return customerVisibleTicketInfo.every((t) => t.price == 0);
  }

  /// Matches web `events` / event detail helpers:
  /// `event?.otherInfo?.isExternalEvent === true`.
  ///
  /// Use [suppressesMerchantAndPriceMarkersLikeWebHome] for homepage cards —
  /// the web homepage uses ordinary JS truthiness on that flag (`!flag`).
  bool get isExternalEvent => otherInfo?['isExternalEvent'] == true;

  /// Homepage parity: `event.otherInfo?.isExternalEvent` is treated as falsy /
  /// truthy like plain JavaScript (web `HomePage` organizer + price chips).
  bool get suppressesMerchantAndPriceMarkersLikeWebHome =>
      _javascriptTruthy(otherInfo?['isExternalEvent']);

  /// Web `EventDetail` external CTA anchor: `event.otherInfo.externalEventDetails`.
  /// Only http(s); optional snake_case fallback for payloads.
  String? get webExternalTicketUrl {
    final oi = otherInfo;
    if (oi == null) return null;

    bool isHttpUrl(String value) =>
        value.startsWith('http://') || value.startsWith('https://');

    String? coerce(dynamic raw) {
      final value = raw?.toString().trim();
      if (value != null && value.isNotEmpty && isHttpUrl(value)) {
        return value;
      }
      return null;
    }

    return coerce(oi['externalEventDetails']) ??
        coerce(oi['external_event_details']);
  }

  /// Resolved external ticket URL (extraInfo/otherInfo).
  String? get externalTicketUrl {
    final extraInfo = otherInfo?['eventExtraInfo'] is Map
        ? Map<String, dynamic>.from(otherInfo!['eventExtraInfo'] as Map)
        : const <String, dynamic>{};
    final root = otherInfo ?? const <String, dynamic>{};

    String? pick(Map<String, dynamic> map, List<String> keys) {
      for (final key in keys) {
        final raw = map[key];
        final value = raw?.toString().trim();
        if (value != null &&
            value.isNotEmpty &&
            (value.startsWith('http://') || value.startsWith('https://'))) {
          return value;
        }
      }
      return null;
    }

    const candidates = <String>[
      'externalEventDetails',
      'external_event_details',
      'externalTicketUrl',
      'external_ticket_url',
      'ticketUrl',
      'ticket_url',
      'externalUrl',
      'external_url',
      'bookingUrl',
      'booking_url',
    ];

    return pick(extraInfo, candidates) ?? pick(root, candidates);
  }

  /// With seat maps, rely on seat inventory; otherwise every visible ticket row is depleted.
  bool get isSoldOut {
    if (hasSeatSelection) return false;
    if (customerVisibleTicketInfo.isEmpty) return false;
    return customerVisibleTicketInfo.every(
      (t) =>
          t.status == 'sold_out' || (t.available != null && t.available! <= 0),
    );
  }
}

bool isTicketHiddenFromCustomer(String? status) =>
    status == 'inactive' || status == 'disabled';

/// Mirrors JavaScript truthiness used on web homepage for external listings.
bool _javascriptTruthy(dynamic v) {
  if (v == null || v == false) {
    return false;
  }
  if (v == true) {
    return true;
  }
  if (v is num) {
    if (v is double && v.isNaN) {
      return false;
    }
    return v != 0;
  }
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s.isEmpty) return false;
    const falsyWords = {'false', 'no', '0', 'undefined', 'null', 'off'};
    return !falsyWords.contains(s);
  }
  return true;
}

/// Merges `otherInfo` and `other_info` (camelCase wins on collisions).
Map<String, dynamic>? _mergedOtherInfoFromJson(Map<String, dynamic> json) {
  final c = _mapFrom(json['otherInfo']);
  final s = _mapFrom(json['other_info']);
  if (c == null) return s;
  if (s == null) return c;
  return <String, dynamic>{...s, ...c};
}

/// Safely convert any map to `Map<String, dynamic>` for fromJson.
Map<String, dynamic>? _mapFrom(dynamic v) {
  if (v == null) return null;
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

bool? _boolOrNull(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) return null;
  final value = json[key];
  if (value is bool) return value;
  return null;
}

extension _Let<T> on T {
  R _let<R>(R Function(T) f) => f(this);
}

class VenueInfo {
  final String? name;
  final String? description;
  final String? website;

  VenueInfo({this.name, this.description, this.website});

  factory VenueInfo.fromJson(Map<String, dynamic> json) => VenueInfo(
    name: _str(json['name']),
    description: _str(json['description']),
    website: _str(json['media']?['website']) ?? _str(json['website']),
  );
}

class Venue {
  final String? name;
  final String? venueId;
  final bool? hasSeatSelection;
  final String? lockedManifestId;
  final String? pricingModel;
  final int? manifestVersion;

  Venue({
    this.name,
    this.venueId,
    this.hasSeatSelection,
    this.lockedManifestId,
    this.pricingModel,
    this.manifestVersion,
  });

  factory Venue.fromJson(Map<String, dynamic> json) => Venue(
    name: _str(json['name']),
    venueId: _venueIdFromJson(json['venueId']),
    hasSeatSelection: json['hasSeatSelection'] == true,
    lockedManifestId: _str(json['lockedManifestId']),
    pricingModel: _str(json['pricingModel']),
    manifestVersion: (json['manifestVersion'] is num)
        ? (json['manifestVersion'] as num).toInt()
        : null,
  );
}

/// Handles venueId as string or MongoDB-style object (e.g. {"\$oid": "..."}).
String? _venueIdFromJson(dynamic v) {
  if (v == null) return null;
  if (v is String && v.isNotEmpty) return v;
  if (v is Map && v.containsKey(r'$oid')) return v[r'$oid']?.toString();
  if (v is Map && v.containsKey('_id')) return v['_id']?.toString();
  return v.toString().trim().isEmpty ? null : v.toString();
}

class TicketInfo {
  final String id;
  final String name;
  final double price;
  final int quantity;

  /// For recurring/season passes:
  /// total number of entries/scans allowed for a single purchased pass (QR).
  /// When present (>0), checkout should lock quantity to `1`.
  final int? scanCount;
  final int? available;
  final double? serviceFee;
  final double? entertainmentTax;
  final double? serviceTax;
  final double? orderFee;
  final double? vat;
  final String? status;

  TicketInfo({
    required this.id,
    required this.name,
    required this.price,
    this.quantity = 1,
    this.scanCount,
    this.available,
    this.serviceFee,
    this.entertainmentTax,
    this.serviceTax,
    this.orderFee,
    this.vat,
    this.status,
  });

  factory TicketInfo.fromJson(Map<String, dynamic> json) => TicketInfo(
    id: _str(json['_id']) ?? '',
    name: _str(json['name']) ?? '',
    price: _toDouble(json['price']) ?? 0,
    quantity: (json['quantity'] is num) ? (json['quantity'] as num).toInt() : 1,
    scanCount: (json['scanCount'] is num)
        ? (json['scanCount'] as num).toInt()
        : (json['scan_count'] is num)
        ? (json['scan_count'] as num).toInt()
        : (json['scanCount'] != null || json['scan_count'] != null)
        ? int.tryParse((json['scanCount'] ?? json['scan_count']).toString())
        : null,
    available: (json['available'] is num)
        ? (json['available'] as num).toInt()
        : null,
    serviceFee: _toDouble(json['serviceFee']),
    entertainmentTax: _toDouble(json['entertainmentTax']),
    serviceTax: _toDouble(json['serviceTax']),
    orderFee: _toDouble(json['orderFee']),
    vat: _toDouble(json['vat']),
    status: _str(json['status']),
  );

  TicketPriceBreakdown get _priceBreakdown => calculateTicketPrice(
    price: price,
    vat: vat,
    entertainmentTax: entertainmentTax,
    serviceTax: serviceTax,
    serviceFee: serviceFee,
    orderFee: orderFee,
  );

  double get vatRate => _priceBreakdown.vatRate;
  double get vatAmountPerTicket => _priceBreakdown.vatAmountPerTicket;
  double get serviceFeeAmount => _priceBreakdown.serviceFeeAmount;
  double get serviceFeeTaxAmount => _priceBreakdown.serviceFeeTaxAmount;
  double get orderFeeAmount => _priceBreakdown.orderFeeAmount;
  double get orderFeeTaxAmount => _priceBreakdown.orderFeeTaxAmount;
  double get subtotalPerTicket => _priceBreakdown.subtotalPerTicket;
  double get totalPerTicket => _priceBreakdown.totalPerTicket;
  double get finalPricePerTicket => _priceBreakdown.finalPricePerTicket;
}

class Merchant {
  final String? id;
  final String? name;
  final String? logo;
  final String? website;
  final String? merchantId;
  final String? stripeAccount;
  final bool paytrailEnabled;

  Merchant({
    this.id,
    this.name,
    this.logo,
    this.website,
    this.merchantId,
    this.stripeAccount,
    this.paytrailEnabled = false,
  });

  factory Merchant.fromJson(Map<String, dynamic> json) => Merchant(
    id: _str(json['_id']),
    name: _str(json['name']),
    logo: _str(json['logo']),
    website: _str(json['website']),
    merchantId: _str(json['merchantId']),
    stripeAccount: _str(json['stripeAccount']),
    paytrailEnabled: json['paytrailEnabled'] == true,
  );
}

String? _str(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  return v.toString();
}

double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

class Featured {
  final bool isFeatured;
  final String? featuredType;
  final int priority;

  Featured({this.isFeatured = false, this.featuredType, this.priority = 0});

  factory Featured.fromJson(Map<String, dynamic> json) => Featured(
    isFeatured: json['isFeatured'] == true,
    featuredType: _str(json['featuredType']),
    priority: (json['priority'] is num) ? (json['priority'] as num).toInt() : 0,
  );
}
