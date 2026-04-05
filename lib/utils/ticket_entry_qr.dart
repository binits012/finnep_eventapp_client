/// Aligns with web client: backend may still return a parent/master QR for qty>1,
/// but the app only shows per-guest entry QRs in that case.
int parseTicketOrderQuantity(String? quantityStr, Map<String, dynamic>? ticketInfo) {
  final s = (quantityStr ?? '').trim();
  if (s.isNotEmpty) {
    final n = int.tryParse(s);
    if (n != null && n >= 1) return n;
  }
  if (ticketInfo != null) {
    final q = ticketInfo['quantity'];
    final n2 = int.tryParse(q?.toString().trim() ?? '');
    if (n2 != null && n2 >= 1) return n2;
  }
  return 1;
}

bool showMasterEntryQrOnClient(int orderQuantity) => orderQuantity <= 1;

/// `ticketInfo.childQRCodes` from API: `{ childIndex, childQrCodeValue }`.
List<Map<String, dynamic>> parseChildQrCodes(Map<String, dynamic>? ticketInfo) {
  if (ticketInfo == null) return [];
  final list = ticketInfo['childQRCodes'];
  if (list is! List) return [];
  final out = <Map<String, dynamic>>[];
  for (final item in list) {
    if (item is! Map) continue;
    final m = Map<String, dynamic>.from(item);
    final v = (m['childQrCodeValue'] ?? m['child_qr_code_value'])?.toString().trim() ?? '';
    if (v.isEmpty) continue;
    out.add(m);
  }
  return out;
}
