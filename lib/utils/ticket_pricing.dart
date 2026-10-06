import 'base_price_tax.dart';
import 'money.dart';

export 'money.dart' show TicketLinePricing, computeTicketLinePricing;

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
  final vatRate = basePriceTaxPercent(vat, entertainmentTax);
  final serviceTaxRate = serviceTax ?? 0;
  final line = computeTicketLinePricing(
    basePrice: price,
    serviceFee: serviceFee ?? 0,
    vatRatePercent: vatRate,
    serviceTaxRatePercent: serviceTaxRate,
    orderFee: orderFee ?? 0,
    quantity: 1,
  );

  return TicketPriceBreakdown(
    vatRate: vatRate,
    serviceTaxRate: serviceTaxRate,
    serviceFeeAmount: line.serviceFee,
    orderFeeAmount: line.orderFee,
    vatAmountPerTicket: line.perUnitVat,
    serviceFeeTaxAmount: line.perUnitServiceTax,
    orderFeeTaxAmount: line.orderFeeServiceTax,
    subtotalPerTicket: line.perUnitSubtotal,
    totalPerTicket: moneyAdd([line.perUnitSubtotal, line.perUnitVat, line.perUnitServiceTax]),
    finalPricePerTicket: line.total,
  );
}
