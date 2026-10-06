import 'money.dart';
import 'seat_pricing.dart';

/// Sum of per-line catalog bases in [seatTickets].
double seatTicketsCatalogSum(List<Map<String, dynamic>> tickets) {
  if (tickets.isEmpty) return 0;
  if (seatTicketsUsePricingConfiguration(tickets)) {
    return tickets.fold<double>(0, (acc, m) {
      final pr = m['pricing'];
      if (pr is! Map) return acc;
      final raw = pr['basePrice'];
      final v = (raw is num)
          ? raw.toDouble()
          : (double.tryParse(raw?.toString() ?? '') ?? 0);
      return roundMoney(acc + v);
    });
  }
  return tickets.fold<double>(0, (acc, m) {
    final raw = m['price'];
    final v = (raw is num)
        ? raw.toDouble()
        : (double.tryParse(raw?.toString() ?? '') ?? 0);
    return roundMoney(acc + v);
  });
}

bool seatTicketsUsePricingConfiguration(List<Map<String, dynamic>> tickets) =>
    tickets.isNotEmpty &&
    tickets.every(
      (m) => (m['pricing'] is Map) && ((m['pricing'] as Map).isNotEmpty),
    );

/// Aggregate [SeatCheckoutSummary] from `seatTickets` with `pricing` maps (pricing_configuration).
/// Same inputs as seat selection checkout; backend Paytrail PRIORITY 1 expects these aggregates in metadata.
SeatCheckoutSummary? pricingConfigSeatSummaryFromSeatTickets(
  List<Map<String, dynamic>> seatTickets,
) {
  if (!seatTicketsUsePricingConfiguration(seatTickets)) return null;

  final svcOrig = _serviceFeesPricingConfig(seatTickets);
  final prFirstRaw = seatTickets.first['pricing'];
  final Map<String, dynamic> prFirst = prFirstRaw is Map
      ? Map<String, dynamic>.from(prFirstRaw)
      : <String, dynamic>{};

  final taxRate = (prFirst['tax'] is num)
      ? (prFirst['tax'] as num).toDouble()
      : double.tryParse(prFirst['tax']?.toString() ?? '') ?? 0;
  final svcTaxRate = (prFirst['serviceTax'] is num)
      ? (prFirst['serviceTax'] as num).toDouble()
      : double.tryParse(prFirst['serviceTax']?.toString() ?? '') ?? 0;
  double of = (prFirst['orderFee'] is num)
      ? (prFirst['orderFee'] as num).toDouble()
      : double.tryParse(prFirst['orderFee']?.toString() ?? '') ?? 0;

  final lines = <({double basePrice, double serviceFee})>[];
  for (var i = 0; i < seatTickets.length; i++) {
    final prDyn = seatTickets[i]['pricing'];
    if (prDyn is Map) {
      final pr = Map<String, dynamic>.from(prDyn);
      final fo = pr['orderFee'];
      final parsedFo = (fo is num)
          ? fo.toDouble()
          : double.tryParse(fo?.toString() ?? '');
      if (parsedFo != null && parsedFo > 0) {
        of = parsedFo;
      }
    }

    final prSeat = seatTickets[i]['pricing'];
    if (prSeat is! Map) continue;
    final prMap = Map<String, dynamic>.from(prSeat);
    final rawB = prMap['basePrice'];
    final b = (rawB is num)
        ? rawB.toDouble()
        : (double.tryParse(rawB?.toString() ?? '') ?? 0);
    final sfDyn = svcOrig.length > i ? svcOrig[i] : null;
    final sf = (sfDyn ?? 0.0).toDouble();
    lines.add((basePrice: b, serviceFee: sf));
  }

  if (lines.isEmpty) return null;
  return computePricingConfigSeatSummary(
    lines: lines,
    taxRatePercent: taxRate,
    serviceTaxRatePercent: svcTaxRate,
    orderFee: of,
  );
}

List<double?> _serviceFeesPricingConfig(List<Map<String, dynamic>> tickets) =>
    tickets
        .map((m) {
          final pr = m['pricing'];
          if (pr is! Map) return null;
          final raw = pr['serviceFee'];
          return (raw is num)
              ? raw.toDouble()
              : double.tryParse(raw?.toString() ?? '');
        })
        .toList(growable: false);

/// Seat total after coupon: for `pricing_configuration`, matches web `applyCouponToSummaryTotals`
/// (aggregate base - discount, then `moneyPercentOf` on base tax). For ticket_info seats,
/// keeps service/order fees intact and applies the coupon to catalog base only.
double? discountedSeatCheckoutTotalFromPayload({
  required double totalAmountOverride,
  required double orderFeeRoot,
  required double serviceFeeRoot,
  required double vatRatePercent,
  required double orderServiceTaxRatePercent,
  required List<Map<String, dynamic>> seatTickets,
  required double couponDiscountOnCatalogSum,
}) {
  if (!(couponDiscountOnCatalogSum > 0)) return null;
  if (!(totalAmountOverride > 0)) return null;

  if (seatTicketsUsePricingConfiguration(seatTickets)) {
    final summary = pricingConfigSeatSummaryFromSeatTickets(seatTickets);
    if (summary == null) return null;
    return applyCouponToSeatSummaryTotals(
      totals: summary,
      discountAmount: couponDiscountOnCatalogSum,
    ).total;
  }

  final ticketInfoLines = seatTickets.map((m) {
    final raw = m['price'];
    final base = (raw is num)
        ? raw.toDouble()
        : (double.tryParse(raw?.toString() ?? '') ?? 0);
    return computeSeatLinePrice(
      basePrice: base,
      serviceFee: serviceFeeRoot,
      entertainmentTax: vatRatePercent,
      serviceTax: orderServiceTaxRatePercent,
    );
  }).toList();

  if (ticketInfoLines.isEmpty || !ticketInfoLines.any((l) => l.basePrice > 0)) {
    return null;
  }

  final summary = computeTicketInfoSeatSummary(
    lines: ticketInfoLines,
    orderFee: orderFeeRoot,
    serviceTaxRatePercent: orderServiceTaxRatePercent,
    vatRatePercent: vatRatePercent,
  );
  return applyCouponToSeatSummaryTotals(
    totals: summary,
    discountAmount: couponDiscountOnCatalogSum,
  ).total;
}
