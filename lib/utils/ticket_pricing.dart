class TicketPriceBreakdown {
  final double vatRate;
  final double serviceTaxRate;
  final double serviceFeeAmount;
  final double orderFeeAmount;
  final double vatAmountPerTicket;
  final double serviceFeeTaxAmount;
  final double orderFeeTaxAmount;
  final double subtotalPerTicket;
  final double totalPerTicket;
  final double finalPricePerTicket;

  const TicketPriceBreakdown({
    required this.vatRate,
    required this.serviceTaxRate,
    required this.serviceFeeAmount,
    required this.orderFeeAmount,
    required this.vatAmountPerTicket,
    required this.serviceFeeTaxAmount,
    required this.orderFeeTaxAmount,
    required this.subtotalPerTicket,
    required this.totalPerTicket,
    required this.finalPricePerTicket,
  });
}

TicketPriceBreakdown calculateTicketPrice({
  required double price,
  double? vat,
  double? entertainmentTax,
  double? serviceTax,
  double? serviceFee,
  double? orderFee,
}) {
  // Match backend/web precedence: use entertainmentTax only when > 0, otherwise use VAT.
  final entertainmentRate = entertainmentTax ?? 0;
  final vatRate = entertainmentRate > 0 ? entertainmentRate : (vat ?? 0);
  final serviceTaxRate = serviceTax ?? 0;
  final serviceFeeAmount = serviceFee ?? 0;
  final orderFeeAmount = orderFee ?? 0;

  final vatMultiplier = vatRate > 0 ? (vatRate / 100) : 0.0;
  final vatAmountPerTicket = price * vatMultiplier;
  final subtotalPerTicket = price + vatAmountPerTicket;
  final serviceTaxMultiplier = serviceTaxRate > 0 ? (serviceTaxRate / 100) : 0.0;
  final serviceFeeTaxAmount = serviceFeeAmount * serviceTaxMultiplier;
  final orderFeeTaxAmount = orderFeeAmount * serviceTaxMultiplier;
  final totalPerTicket = subtotalPerTicket +
      serviceFeeAmount +
      serviceFeeTaxAmount;
  final finalPricePerTicket = totalPerTicket +
      orderFeeAmount +
      orderFeeTaxAmount;

  return TicketPriceBreakdown(
    vatRate: vatRate,
    serviceTaxRate: serviceTaxRate,
    serviceFeeAmount: serviceFeeAmount,
    orderFeeAmount: orderFeeAmount,
    vatAmountPerTicket: vatAmountPerTicket,
    serviceFeeTaxAmount: serviceFeeTaxAmount,
    orderFeeTaxAmount: orderFeeTaxAmount,
    subtotalPerTicket: subtotalPerTicket,
    totalPerTicket: totalPerTicket,
    finalPricePerTicket: finalPricePerTicket,
  );
}

