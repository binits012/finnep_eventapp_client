import 'base_price_tax.dart';
import 'money.dart';

class SeatLineBreakdown {
  const SeatLineBreakdown({
    required this.basePrice,
    required this.serviceFee,
    required this.entertainmentTaxPercent,
    required this.entertainmentTaxAmount,
    required this.serviceTaxPercent,
    required this.serviceTaxAmount,
    required this.ticketPrice,
  });

  final double basePrice;
  final double serviceFee;
  final double entertainmentTaxPercent;
  final double entertainmentTaxAmount;
  final double serviceTaxPercent;
  final double serviceTaxAmount;
  final double ticketPrice;
}

class OrderFeeBreakdown {
  const OrderFeeBreakdown({
    required this.orderFee,
    required this.orderFeeTax,
    required this.orderFeeTotal,
    required this.serviceTaxPercent,
  });

  final double orderFee;
  final double orderFeeTax;
  final double orderFeeTotal;
  final double serviceTaxPercent;
}

class SeatCheckoutSummary {
  const SeatCheckoutSummary({
    required this.totalBasePrice,
    required this.totalServiceFee,
    required this.totalEntertainmentTaxAmount,
    required this.totalServiceTaxAmount,
    required this.totalVatAmount,
    required this.entertainmentTaxRate,
    required this.vatRate,
    required this.orderFee,
    required this.orderFeeServiceTax,
    required this.orderFeeTotal,
    required this.seatsSubtotal,
    required this.total,
  });

  final double totalBasePrice;
  final double totalServiceFee;
  final double totalEntertainmentTaxAmount;
  final double totalServiceTaxAmount;
  final double totalVatAmount;
  final double entertainmentTaxRate;
  final double vatRate;
  final double orderFee;
  final double orderFeeServiceTax;
  final double orderFeeTotal;
  final double seatsSubtotal;
  final double total;
}

SeatLineBreakdown computeSeatLinePrice({
  required double basePrice,
  double serviceFee = 0,
  double? vat,
  double? entertainmentTax,
  double serviceTax = 0,
}) {
  final vatRatePercent = basePriceTaxPercent(vat, entertainmentTax);
  final line = computeTicketLinePricing(
    basePrice: basePrice,
    serviceFee: serviceFee,
    vatRatePercent: vatRatePercent,
    serviceTaxRatePercent: serviceTax,
    orderFee: 0,
    quantity: 1,
  );
  return SeatLineBreakdown(
    basePrice: line.basePrice,
    serviceFee: line.serviceFee,
    entertainmentTaxPercent: vatRatePercent,
    entertainmentTaxAmount: line.perUnitVat,
    serviceTaxPercent: serviceTax,
    serviceTaxAmount: line.perUnitServiceTax,
    ticketPrice: line.perUnitTotal,
  );
}

OrderFeeBreakdown computeOrderFeeTotal(
  double orderFee,
  double serviceTaxRatePercent,
) {
  final fee = roundMoney(orderFee);
  final tax = fee > 0 && serviceTaxRatePercent > 0
      ? moneyPercentOf(fee, serviceTaxRatePercent)
      : 0.0;
  return OrderFeeBreakdown(
    orderFee: fee,
    orderFeeTax: tax,
    orderFeeTotal: moneyAdd([fee, tax]),
    serviceTaxPercent: serviceTaxRatePercent,
  );
}

SeatCheckoutSummary computePricingConfigSeatSummary({
  required List<({double basePrice, double serviceFee})> lines,
  required double taxRatePercent,
  required double serviceTaxRatePercent,
  required double orderFee,
}) {
  var totalBaseExact = 0.0;
  var totalSvcExact = 0.0;
  for (final line in lines) {
    totalBaseExact += line.basePrice;
    totalSvcExact += line.serviceFee;
  }

  final totalBasePrice = roundMoney(totalBaseExact);
  final totalServiceFee = roundMoney(totalSvcExact);
  final totalEntertainmentTaxAmount =
      moneyPercentOfExactSum(totalBaseExact, taxRatePercent);
  final totalServiceTaxAmount =
      moneyPercentOfExactSum(totalSvcExact, serviceTaxRatePercent);

  final seatsSubtotal = moneyAdd([
    totalBasePrice,
    totalServiceFee,
    totalEntertainmentTaxAmount,
    totalServiceTaxAmount,
  ]);
  final order = computeOrderFeeTotal(orderFee, serviceTaxRatePercent);

  return SeatCheckoutSummary(
    totalBasePrice: totalBasePrice,
    totalServiceFee: totalServiceFee,
    totalEntertainmentTaxAmount: totalEntertainmentTaxAmount,
    totalServiceTaxAmount: totalServiceTaxAmount,
    totalVatAmount: totalEntertainmentTaxAmount,
    entertainmentTaxRate: taxRatePercent,
    vatRate: taxRatePercent,
    orderFee: order.orderFee,
    orderFeeServiceTax: order.orderFeeTax,
    orderFeeTotal: order.orderFeeTotal,
    seatsSubtotal: seatsSubtotal,
    total: moneyAdd([seatsSubtotal, order.orderFeeTotal]),
  );
}

/// Catalog discount only on aggregate base; service fees unchanged; base tax via [moneyPercentOf]
/// (same as web `applyCouponToSummaryTotals`).
SeatCheckoutSummary applyCouponToSeatSummaryTotals({
  required SeatCheckoutSummary totals,
  required double discountAmount,
}) {
  final capped = discountAmount.isFinite ? discountAmount : 0.0;
  final low = capped < 0 ? 0.0 : capped;
  final high = low > totals.totalBasePrice ? totals.totalBasePrice : low;
  final appliedDiscount = roundMoney(high);
  final discountedBase = roundMoney(
    (totals.totalBasePrice - appliedDiscount).clamp(0.0, double.infinity),
  );
  final taxRate = totals.entertainmentTaxRate != 0
      ? totals.entertainmentTaxRate
      : totals.vatRate;
  final totalEntertainmentTaxAmount = moneyPercentOf(discountedBase, taxRate);
  final seatsSubtotal = moneyAdd([
    discountedBase,
    totals.totalServiceFee,
    totalEntertainmentTaxAmount,
    totals.totalServiceTaxAmount,
  ]);
  final grandTotal = moneyAdd([
    discountedBase,
    totals.totalServiceFee,
    totalEntertainmentTaxAmount,
    totals.totalServiceTaxAmount,
    totals.orderFee,
    totals.orderFeeServiceTax,
  ]);

  return SeatCheckoutSummary(
    totalBasePrice: discountedBase,
    totalServiceFee: totals.totalServiceFee,
    totalEntertainmentTaxAmount: totalEntertainmentTaxAmount,
    totalServiceTaxAmount: totals.totalServiceTaxAmount,
    totalVatAmount: totalEntertainmentTaxAmount,
    entertainmentTaxRate: totals.entertainmentTaxRate,
    vatRate: totals.vatRate,
    orderFee: totals.orderFee,
    orderFeeServiceTax: totals.orderFeeServiceTax,
    orderFeeTotal: totals.orderFeeTotal,
    seatsSubtotal: seatsSubtotal,
    total: grandTotal,
  );
}

SeatCheckoutSummary computeTicketInfoSeatSummary({
  required List<SeatLineBreakdown> lines,
  required double orderFee,
  required double serviceTaxRatePercent,
  required double vatRatePercent,
}) {
  final totalBasePrice = moneyAdd(lines.map((l) => l.basePrice));
  final totalServiceFee = moneyAdd(lines.map((l) => l.serviceFee));
  final totalEntertainmentTaxAmount =
      moneyAdd(lines.map((l) => l.entertainmentTaxAmount));
  final totalServiceTaxAmount = moneyAdd(lines.map((l) => l.serviceTaxAmount));
  final seatsSubtotal = moneyAdd(lines.map((l) => l.ticketPrice));
  final order = computeOrderFeeTotal(orderFee, serviceTaxRatePercent);

  return SeatCheckoutSummary(
    totalBasePrice: totalBasePrice,
    totalServiceFee: totalServiceFee,
    totalEntertainmentTaxAmount: totalEntertainmentTaxAmount,
    totalServiceTaxAmount: totalServiceTaxAmount,
    totalVatAmount: totalEntertainmentTaxAmount,
    entertainmentTaxRate: vatRatePercent,
    vatRate: vatRatePercent,
    orderFee: order.orderFee,
    orderFeeServiceTax: order.orderFeeTax,
    orderFeeTotal: order.orderFeeTotal,
    seatsSubtotal: seatsSubtotal,
    total: moneyAdd([seatsSubtotal, order.orderFeeTotal]),
  );
}
