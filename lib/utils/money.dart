// Monetary arithmetic: round to 2 decimals after every step (cents).

double roundMoney(num? amount) {
  if (amount == null) return 0;
  final n = amount is double ? amount : amount.toDouble();
  if (!n.isFinite) return 0;
  return (n * 100).roundToDouble() / 100;
}

double moneyPercentOf(num base, num ratePercent) {
  return roundMoney(roundMoney(base) * (ratePercent / 100));
}

/// Tax on exact summed base (pricing_configuration aggregates).
double moneyPercentOfExactSum(num baseExact, num ratePercent) {
  return roundMoney(baseExact.toDouble() * (ratePercent / 100));
}

double moneyAdd(Iterable<num> amounts) {
  var sum = 0.0;
  for (final part in amounts) {
    sum = roundMoney(sum + roundMoney(part));
  }
  return sum;
}

double moneyMul(num unit, int quantity) {
  final qty = quantity < 0 ? 0 : quantity;
  return roundMoney(roundMoney(unit) * qty);
}

String moneyToMetadataString(num amount) {
  return roundMoney(amount).toStringAsFixed(2);
}

class TicketLinePricing {
  const TicketLinePricing({
    required this.basePrice,
    required this.serviceFee,
    required this.perUnitSubtotal,
    required this.perUnitVat,
    required this.perUnitServiceTax,
    required this.perUnitTotal,
    required this.totalBasePrice,
    required this.totalServiceFee,
    required this.totalVatAmount,
    required this.totalServiceTaxAmount,
    required this.orderFee,
    required this.orderFeeServiceTax,
    required this.total,
  });

  final double basePrice;
  final double serviceFee;
  final double perUnitSubtotal;
  final double perUnitVat;
  final double perUnitServiceTax;
  final double perUnitTotal;
  final double totalBasePrice;
  final double totalServiceFee;
  final double totalVatAmount;
  final double totalServiceTaxAmount;
  final double orderFee;
  final double orderFeeServiceTax;
  final double total;
}

TicketLinePricing computeTicketLinePricing({
  required double basePrice,
  double serviceFee = 0,
  required double vatRatePercent,
  double serviceTaxRatePercent = 0,
  double orderFee = 0,
  int quantity = 1,
}) {
  final qty = quantity < 1 ? 1 : quantity;
  final bp = roundMoney(basePrice);
  final sf = roundMoney(serviceFee);

  final perUnitSubtotal = moneyAdd([bp, sf]);
  final perUnitVat = moneyPercentOf(bp, vatRatePercent);
  final perUnitServiceTax = sf > 0 && serviceTaxRatePercent > 0
      ? moneyPercentOf(sf, serviceTaxRatePercent)
      : 0.0;
  final perUnitTotal = moneyAdd([perUnitSubtotal, perUnitVat, perUnitServiceTax]);

  final totalBasePrice = moneyMul(bp, qty);
  final totalServiceFee = moneyMul(sf, qty);
  final totalVatAmount = moneyMul(perUnitVat, qty);
  final totalServiceTaxAmount = moneyMul(perUnitServiceTax, qty);

  final of = roundMoney(orderFee);
  final orderFeeServiceTax = of > 0 && serviceTaxRatePercent > 0
      ? moneyPercentOf(of, serviceTaxRatePercent)
      : 0.0;

  final total = moneyAdd([
    moneyMul(perUnitTotal, qty),
    of,
    orderFeeServiceTax,
  ]);

  return TicketLinePricing(
    basePrice: bp,
    serviceFee: sf,
    perUnitSubtotal: perUnitSubtotal,
    perUnitVat: perUnitVat,
    perUnitServiceTax: perUnitServiceTax,
    perUnitTotal: perUnitTotal,
    totalBasePrice: totalBasePrice,
    totalServiceFee: totalServiceFee,
    totalVatAmount: totalVatAmount,
    totalServiceTaxAmount: totalServiceTaxAmount,
    orderFee: of,
    orderFeeServiceTax: orderFeeServiceTax,
    total: total,
  );
}
