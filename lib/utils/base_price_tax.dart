/// Effective base-price tax % (entertainment tax when > 0, else VAT). Matches web/backend.
double basePriceTaxPercent(double? vat, double? entertainmentTax) {
  final et = entertainmentTax ?? 0;
  if (et > 0) return et;
  return vat ?? 0;
}
