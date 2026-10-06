import '../models/event.dart';

const String _defaultIncludedFeesFootnoteText = 'Price includes GST and other fees';

String _formatFootnoteWithParentheses(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return trimmed;
  if (trimmed.startsWith('(') && trimmed.endsWith(')')) return trimmed;
  return '($trimmed)';
}

/// Min payable price for the listing “From …” chip.
/// Matches web/checkout logic by using `finalPricePerTicket`.
double? eventListingMinPayable(Event event) {
  if (event.ticketInfo.isEmpty) return null;
  if (event.hasSeatSelection) return null; // Listing UI should hide price chip for seat events.

  final totals = event.ticketInfo.map((t) => t.finalPricePerTicket).toList();
  if (totals.isEmpty) return null;
  return totals.reduce((a, b) => a < b ? a : b);
}

/// Optional footnote under the listing “From …” chip.
/// Returns formatted text with parentheses, or `null` when mode is not enabled.
String? eventListingIncludedFeesFootnote(Event event) {
  final otherInfo = event.otherInfo;
  if (otherInfo == null) return null;
  if (event.hasSeatSelection) return null;

  final ticketListingPricingRaw = otherInfo['ticketListingPricing'];
  if (ticketListingPricingRaw is! Map) return null;

  final modeRaw = ticketListingPricingRaw['mode'];
  final mode = modeRaw?.toString();
  if (mode != 'included_fees_note') return null;

  final captionRaw = ticketListingPricingRaw['caption'];
  final caption = captionRaw is String ? captionRaw.trim() : '';

  final text = caption.isNotEmpty ? caption : _defaultIncludedFeesFootnoteText;
  if (text.trim().isEmpty) return null;
  return _formatFootnoteWithParentheses(text);
}

