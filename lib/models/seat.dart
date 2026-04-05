import '../utils/currency.dart';

enum SeatStatus { available, sold, reserved }

class SeatModel {
  final String placeId;
  final double? x;
  final double? y;
  final String? row;
  final String? seat;
  final String? section;
  final double? price;
  /// When from tier: base before tax (e.g. 27.0). Null when from zone.
  final double? basePrice;
  /// When from tier: tax amount (e.g. 3.645). Null when from zone.
  final double? taxAmount;
  final double? taxPercentage;
  /// When from tier: service fee amount (fee + fee*tax). Null when from zone or zero.
  final double? serviceFeeAmount;
  final double? serviceFeePercentage;
  final double? orderFeeAmount;
  final SeatStatus status;
  final List<String> tags;


  SeatModel({
    required this.placeId,
    this.x,
    this.y,
    this.row,
    this.seat,
    this.section,
    this.price,
    this.basePrice,
    this.taxAmount,
    this.taxPercentage,
    this.serviceFeeAmount,
    this.serviceFeePercentage,
    this.orderFeeAmount, 
    required this.status,
    this.tags = const [],
  });
}

class SeatMapData {
  final List<String> placeIds;
  final List<String> sold;
  final List<String> reserved;
  final List<SectionModel> sections;
  final List<AreaSectionModel> areaSections;
  final dynamic backgroundSvg;
  final List<PricingZone> pricingZones;
  final PricingConfig? pricingConfig;
  final Map<String, dynamic>? venue;

  SeatMapData({
    required this.placeIds,
    required this.sold,
    required this.reserved,
    required this.sections,
    this.areaSections = const [],
    this.backgroundSvg,
    this.pricingZones = const [],
    this.pricingConfig,
    this.venue,
  });

  factory SeatMapData.fromJson(Map<String, dynamic> json) {
    final placeIds = (json['placeIds'] as List<dynamic>?)?.cast<String>() ?? [];
    final sold = (json['sold'] as List<dynamic>?)?.cast<String>() ?? [];
    final reserved = (json['reserved'] as List<dynamic>?)?.cast<String>() ?? [];
    final sectionsList = json['sections'] as List<dynamic>? ?? [];
    final sections = sectionsList
        .map((e) => SectionModel.fromJson(e as Map<String, dynamic>))
        .toList();
    final areaSectionsList = json['areaSections'] as List<dynamic>? ?? [];
    final areaSections = areaSectionsList
        .map((e) => AreaSectionModel.fromJson(e as Map<String, dynamic>))
        .toList();
    final sectionsWithAreaMeta =
        SeatMapData._mergeSectionPolygonsWithAreaMeta(sections, areaSections);
    final zonesList = json['pricingZones'] as List<dynamic>? ?? [];
    final pricingZones = zonesList
        .map((e) => PricingZone.fromJson(e as Map<String, dynamic>))
        .toList();
    PricingConfig? pricingConfig;
    if (json['pricingConfig'] != null) {
      pricingConfig = PricingConfig.fromJson(json['pricingConfig'] as Map<String, dynamic>);
    }
    return SeatMapData(
      placeIds: placeIds,
      sold: sold,
      reserved: reserved,
      sections: sectionsWithAreaMeta,
      areaSections: areaSections,
      backgroundSvg: json['backgroundSvg'],
      pricingZones: pricingZones,
      pricingConfig: pricingConfig,
      venue: json['venue'] as Map<String, dynamic>?,
    );
  }

  /// Copy [declaredCapacity] / [selectionMode] from `areaSections` onto matching `sections` (for map styling).
  static List<SectionModel> _mergeSectionPolygonsWithAreaMeta(
    List<SectionModel> sections,
    List<AreaSectionModel> areas,
  ) {
    if (areas.isEmpty) return sections;
    final byId = {for (final a in areas) a.id: a};
    return sections.map((s) {
      final a = byId[s.id];
      if (a == null) return s;
      return SectionModel(
        id: s.id,
        name: s.name,
        color: s.color,
        polygon: s.polygon,
        spacingConfig: s.spacingConfig,
        selectionMode: s.selectionMode ?? a.selectionMode,
        declaredCapacity: s.declaredCapacity ?? a.declaredCapacity,
      );
    }).toList();
  }
}

class AreaSectionModel {
  final String id;
  final String name;
  final String sectionType;
  final String selectionMode;
  final int capacity;
  /// When present and 0 with [selectionMode] == area, section is not sold (map polygon only).
  final int? declaredCapacity;
  final int soldCount;
  final int reservedCount;
  final int availableCount;
  final String color;

  AreaSectionModel({
    required this.id,
    required this.name,
    required this.sectionType,
    required this.selectionMode,
    required this.capacity,
    this.declaredCapacity,
    required this.soldCount,
    required this.reservedCount,
    required this.availableCount,
    required this.color,
  });

  /// Area-level section with CMS capacity 0 is shown on the map but cannot be purchased.
  bool get isPurchasableForAreaFlow {
    if (selectionMode != 'area') return true;
    if (declaredCapacity == null) return true;
    return declaredCapacity != 0;
  }

  factory AreaSectionModel.fromJson(Map<String, dynamic> json) {
    final dc = json['declaredCapacity'];
    return AreaSectionModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      sectionType: json['sectionType']?.toString() ?? 'Area',
      selectionMode: json['selectionMode']?.toString() ?? 'area',
      capacity: (json['capacity'] as num?)?.toInt() ?? 0,
      declaredCapacity: dc == null ? null : (dc as num).toInt(),
      soldCount: (json['soldCount'] as num?)?.toInt() ?? 0,
      reservedCount: (json['reservedCount'] as num?)?.toInt() ?? 0,
      availableCount: (json['availableCount'] as num?)?.toInt() ?? 0,
      color: json['color']?.toString() ?? '#1976D2',
    );
  }
}

class SectionModel {
  final String id;
  final String name;
  final String color;
  final List<SectionPoint> polygon;
  final SectionSpacingConfig? spacingConfig;
  final String? selectionMode;
  final int? declaredCapacity;

  SectionModel({
    required this.id,
    required this.name,
    required this.color,
    this.polygon = const [],
    this.spacingConfig,
    this.selectionMode,
    this.declaredCapacity,
  });

  bool get isInactiveAreaHighlight =>
      selectionMode == 'area' && declaredCapacity == 0;

  factory SectionModel.fromJson(Map<String, dynamic> json) {
    final dc = json['declaredCapacity'];
    return SectionModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      color: json['color'] as String? ?? '#cccccc',
      polygon: (json['polygon'] as List<dynamic>? ?? [])
          .map((e) => SectionPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      spacingConfig: json['spacingConfig'] is Map<String, dynamic>
          ? SectionSpacingConfig.fromJson(
              json['spacingConfig'] as Map<String, dynamic>,
            )
          : null,
      selectionMode: json['selectionMode']?.toString(),
      declaredCapacity: dc == null ? null : (dc as num).toInt(),
    );
  }
}

class SectionPoint {
  final double x;
  final double y;

  SectionPoint({required this.x, required this.y});

  factory SectionPoint.fromJson(Map<String, dynamic> json) => SectionPoint(
        x: (json['x'] as num?)?.toDouble() ?? 0,
        y: (json['y'] as num?)?.toDouble() ?? 0,
      );
}

class SectionSpacingConfig {
  final double seatSpacingVisual;
  final double rowSpacingVisual;
  final double topMargin;
  final double rotationAngle;

  SectionSpacingConfig({
    this.seatSpacingVisual = 1.0,
    this.rowSpacingVisual = 1.0,
    this.topMargin = 0,
    this.rotationAngle = 0,
  });

  factory SectionSpacingConfig.fromJson(Map<String, dynamic> json) =>
      SectionSpacingConfig(
        seatSpacingVisual:
            (json['seatSpacingVisual'] as num?)?.toDouble() ?? 1.0,
        rowSpacingVisual:
            (json['rowSpacingVisual'] as num?)?.toDouble() ?? 1.0,
        topMargin: (json['topMargin'] as num?)?.toDouble() ?? 0,
        rotationAngle: (json['rotationAngle'] as num?)?.toDouble() ?? 0,
      );
}

class PricingZone {
  final int start;
  final int end;
  final double price;
  final String? section;

  PricingZone({required this.start, required this.end, required this.price, this.section});

  factory PricingZone.fromJson(Map<String, dynamic> json) => PricingZone(
        start: json['start'] as int? ?? 0,
        end: json['end'] as int? ?? 0,
        price: ((json['price'] as num?)?.toDouble() ?? 0) / 100,
        section: json['section'] as String?,
      );
}

class PricingConfig {
  final String currency;
  final double orderFee;
  final List<PricingTier> tiers;

  PricingConfig({required this.currency, this.orderFee = 0, this.tiers = const []});

  factory PricingConfig.fromJson(Map<String, dynamic> json) {
    final tiersList = json['tiers'] as List<dynamic>? ?? [];
    return PricingConfig(
      currency: normalizeStripeCurrencyCode((json['currency'] as String?) ?? 'eur'),
      orderFee: (json['orderFee'] as num?)?.toDouble() ?? 0,
      tiers: tiersList
          .map((e) => PricingTier.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class PricingTier {
  final String id;
  final double basePrice;
  final double tax;
  final double serviceFee;
  final double serviceTax;

  PricingTier({
    required this.id,
    required this.basePrice,
    this.tax = 0,
    this.serviceFee = 0,
    this.serviceTax = 0,
  });

  factory PricingTier.fromJson(Map<String, dynamic> json) => PricingTier(
        id: json['id'] as String? ?? '',
        basePrice: (json['basePrice'] as num?)?.toDouble() ?? 0,
        tax: (json['tax'] as num?)?.toDouble() ?? 0,
        serviceFee: (json['serviceFee'] as num?)?.toDouble() ?? 0,
        serviceTax: (json['serviceTax'] as num?)?.toDouble() ?? 0,
      );
}
